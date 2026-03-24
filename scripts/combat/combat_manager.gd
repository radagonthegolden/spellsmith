extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

const CombatStateResource := preload("res://scripts/combat/combat_state.gd")
const CombatEnemyLibraryResource := preload("res://scripts/combat/combat_enemy_library.gd")

@export var enemies_file_path: String = "res://data/enemies.json"
@export var progress_aspect_count: int = 3
@export var context_max_value: int = 6

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler

@onready var player_ui: BattlerUI = $"../HiddenUi/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../HiddenUi/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../HiddenUi/TurnRow/TurnLabel"
@onready var battle_log = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"

@onready var fight_notes_frame: PanelContainer = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame"
@onready var fight_notes: RichTextLabel = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame/FightNotesMargin/FightNotes"
@onready var ollama_client: OllamaClient = $"../spell/OllamaClient"
@onready var aspect_library: AspectLibrary = $"../spell/AspectLibrary"

var enemy_library = CombatEnemyLibraryResource.new()
var state = CombatStateResource.new()

var active: bool = false
var current_enemy: Dictionary = {}
var descriptor_vector: Array = []
var prepared_enemy_spell: Dictionary = {}
var last_player_spell_name: String = ""
var last_player_resonance: float = 0.0
var last_player_profile: Array = []
var last_context_update: Dictionary = {}
var last_defense_summary: String = ""

func _ready() -> void:
	enemy_library.load_from_file(enemies_file_path)
	_set_ui_visible(false)
	fight_notes.text = ""

func start_battle(enemy_name: String = "Enemy") -> void:
	var enemy: Dictionary = enemy_library.get_enemy(enemy_name)
	if enemy.is_empty():
		push_error("Enemy not found: " + enemy_name)
		return

	var descriptor: Array = await enemy_library.build_descriptor_vector(enemy, ollama_client)
	if descriptor.is_empty():
		push_error("Failed to build descriptor vector for enemy: " + enemy_name)
		return

	active = true
	current_enemy = enemy
	descriptor_vector = descriptor
	prepared_enemy_spell = {}
	last_player_spell_name = ""
	last_player_resonance = 0.0
	last_player_profile = []
	last_context_update = {}
	last_defense_summary = "The duel has just begun."

	player.reset_health()
	opponent.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy_name
	state.setup(aspect_library.get_aspect_names(), context_max_value)

	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()

	turn_label.text = "Turn: Player"
	_set_ui_visible(true)
	_log_line("")
	_log_line("A hostile presence condenses into the manuscript.")
	await _prepare_enemy_spell()
	_refresh_fight_notes()

func _on_spell_encoded(spell_embedding: Array, text: String) -> void:
	if not active:
		return

	turn_label.text = "Turn: Player"
	var spell_aspect_scores: Array = aspect_library.score_embedding(spell_embedding, text)
	var resonance: float = SemanticScorer.cosine_similarity(spell_embedding, descriptor_vector)
	var effective_resonance: float = _get_effective_resonance(resonance)
	var effective_spell_aspect_scores: Array = SemanticScorer.scale_scores(spell_aspect_scores, effective_resonance)
	last_context_update = state.apply_spell(effective_spell_aspect_scores)

	var player_profile: Array = CombatStateResource.build_full_profile(effective_spell_aspect_scores)
	last_player_spell_name = text
	last_player_resonance = effective_resonance
	last_player_profile = player_profile

	var displayed_player_profile: Array = CombatStateResource.filter_display_profile(player_profile, prepared_enemy_spell.get("_intensity_profile", []))
	_log_line("You cast \"" + text + "\". Resonance " + str(snappedf(effective_resonance, 0.01)) + ". Pattern: " + CombatStateResource.format_profile(displayed_player_profile) + ".")

	if state.meets_conditions(current_enemy["player_victory_conditions"]):
		turn_label.text = "Turn: Victory"
		last_defense_summary = "Your spell completed the victory condition before the enemy attack could land."
		_refresh_fight_notes()
		_log_line("The context settles into a shape that breaks " + opponent.display_name + ". Victory.")
		_finish_battle(true)
		return

	_resolve_enemy_spell_collision(player_profile)
	_refresh_fight_notes()

	if player.health <= 0:
		turn_label.text = "Turn: Defeat"
		_log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return

	if state.meets_conditions(current_enemy["player_loss_conditions"]):
		turn_label.text = "Turn: Defeat"
		_log_line(opponent.display_name + " draws the context into its own design. Defeat.")
		_finish_battle(false)
		return

	turn_label.text = "Turn: Player"
	await _prepare_enemy_spell()
	_refresh_fight_notes()

func _get_effective_resonance(raw_resonance: float) -> float:
	var min_resonance: float = float(current_enemy.get("min_descriptor_resonance", 0.0))
	var max_resonance: float = float(current_enemy.get("max_descriptor_resonance", 1.0))
	var clamped_raw: float = clampf(raw_resonance, 0.0, 1.0)
	return lerpf(min_resonance, max_resonance, clamped_raw)

func _prepare_enemy_spell() -> void:
	prepared_enemy_spell = await enemy_library.prepare_enemy_spell(current_enemy, ollama_client, aspect_library)
	if prepared_enemy_spell.is_empty():
		return

	_log_line(opponent.display_name + " casts " + str(prepared_enemy_spell["name"]) + ". Pattern: " + CombatStateResource.format_profile(prepared_enemy_spell["_intensity_profile"]) + ".")

func _resolve_enemy_spell_collision(player_profile: Array) -> void:
	if prepared_enemy_spell.is_empty():
		return

	var enemy_profile: Array = prepared_enemy_spell["_intensity_profile"]
	var damage: int = int(prepared_enemy_spell["damage"])
	if CombatStateResource.player_nullifies_enemy_spell(enemy_profile, player_profile):
		last_defense_summary = "Your spell matched the enemy pattern and nullified the attack."
		_log_line("Your spell matches " + str(prepared_enemy_spell["name"]) + " strongly enough to nullify it.")
		return

	var player_died: bool = player.take_damage(damage)
	_update_health_ui()
	last_defense_summary = str(prepared_enemy_spell["name"]) + " broke through and dealt " + str(damage) + " damage."
	_log_line(str(prepared_enemy_spell["name"]) + " breaks through. You take " + str(damage) + " damage.")
	if player_died:
		_log_line("Your health is spent.")

func _update_health_ui() -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func _refresh_fight_notes() -> void:
	if not active:
		fight_notes.text = ""
		return

	fight_notes.clear()
	fight_notes.append_text(
		CombatStateResource.build_fight_notes(
			player,
			prepared_enemy_spell,
			last_player_spell_name,
			last_player_profile,
			last_player_resonance,
			last_context_update,
			state.get_scores(),
			last_defense_summary,
			progress_aspect_count,
			aspect_library.get_aspect_names()
		)
	)

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = {}
	descriptor_vector.clear()
	state.clear()
	prepared_enemy_spell = {}
	last_player_spell_name = ""
	last_player_resonance = 0.0
	last_player_profile = []
	last_context_update = {}
	last_defense_summary = ""
	fight_notes.text = ""
	_set_ui_visible(false)
	combat_finished.emit(player_won)

func _log_line(message: String) -> void:
	print(message)
	battle_log.append_animated(message + "\n")

func _set_ui_visible(value: bool) -> void:
	fight_notes_frame.visible = value
