extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

const CombatStateResource = preload("res://scripts/combat/combat_state.gd")
const CombatResolutionResource = preload("res://scripts/combat/combat_resolution.gd")

@export var enemies_file_path := "res://data/enemies.json"
@export var progress_aspect_count := 3
@export var context_max_value := 6

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler

@onready var player_ui: BattlerUI = $"../HiddenUi/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../HiddenUi/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../HiddenUi/TurnRow/TurnLabel"
@onready var battle_log = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"

@onready var fight_notes_frame: PanelContainer = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame"
@onready var fight_notes: RichTextLabel = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame/FightNotesMargin/FightNotes"
@onready var spell: Spell = $"../spell"
@onready var enemy_library: Enemies = $Enemies

var state: CombatState = CombatStateResource.new()

var active: bool = false
var current_enemy: Enemies.EnemyDefinition = null
var descriptor_vector: Array = []
var prepared_enemy_spell: Enemies.PreparedEnemySpell = null
var last_player_spell_name: String = ""
var last_player_resonance: float = 0.0
var last_player_profile: Array = []
var last_context_update: Dictionary = {}
var last_defense_summary: String = ""

func _ready() -> void:
	assert(spell != null, "CombatManager missing Spell node")
	assert(enemy_library != null, "CombatManager missing Enemies node")
	enemy_library.load_from_file(enemies_file_path)
	_set_ui_visible(false)
	fight_notes.text = ""

func start_battle(enemy_name: String = "Enemy") -> void:
	var enemy: Enemies.EnemyDefinition = enemy_library.get_enemy(enemy_name)

	var descriptor: Array = await enemy_library.build_descriptor_vector(enemy)
	assert(not descriptor.is_empty(), "Failed to build descriptor vector for enemy: %s" % enemy_name)

	active = true
	current_enemy = enemy
	descriptor_vector = descriptor
	_reset_round_state("The duel has just begun.")

	player.reset_health()
	opponent.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy_name
	state.setup(spell.get_aspect_names(), context_max_value)

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

	var spell_aspect_scores: Array = spell.score_spell_embedding(spell_embedding, text)
	var effective_resonance: float = _get_effective_resonance(
		VectorMath.cosine_similarity(spell_embedding, descriptor_vector)
	)
	var effective_scores: Array = SemanticScorer.scale_scores(spell_aspect_scores, effective_resonance)

	last_context_update = state.apply_spell(effective_scores)
	last_player_spell_name = text
	last_player_resonance = effective_resonance
	last_player_profile = CombatResolutionResource.build_full_profile(effective_scores)
	_assert_prepared_enemy_spell_invariant()

	var displayed_player_profile: Array = CombatResolutionResource.filter_display_profile(
		last_player_profile,
		prepared_enemy_spell.intensity_profile
	)

	_log_line(
		"You cast \"%s\". Resonance %s. Pattern: %s." % [
			text,
			str(snappedf(effective_resonance, 0.01)),
			CombatResolutionResource.format_profile(displayed_player_profile)
		]
	)

	if state.meets_conditions(current_enemy.player_victory_conditions):
		turn_label.text = "Turn: Victory"
		last_defense_summary = "Your spell completed the victory condition before the enemy attack could land."
		_refresh_fight_notes()
		_log_line("The context settles into a shape that breaks %s. Victory." % opponent.display_name)
		_finish_battle(true)
		return

	_resolve_enemy_spell_collision(last_player_profile)
	_refresh_fight_notes()

	if player.health <= 0:
		turn_label.text = "Turn: Defeat"
		_log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return

	if state.meets_conditions(current_enemy.player_loss_conditions):
		turn_label.text = "Turn: Defeat"
		_log_line("%s draws the context into its own design. Defeat." % opponent.display_name)
		_finish_battle(false)
		return

	turn_label.text = "Turn: Player"
	await _prepare_enemy_spell()
	_refresh_fight_notes()

func _get_effective_resonance(raw_resonance: float) -> float:
	assert(current_enemy != null, "Current enemy is null")
	var min_resonance: float = current_enemy.min_descriptor_resonance
	var max_resonance: float = current_enemy.max_descriptor_resonance
	return lerpf(min_resonance, max_resonance, clampf(raw_resonance, 0.0, 1.0))

func _prepare_enemy_spell() -> void:
	prepared_enemy_spell = await enemy_library.prepare_enemy_spell(current_enemy, spell)
	_assert_prepared_enemy_spell_invariant()

	_log_line(
		"%s casts %s. Pattern: %s. Damage: %d." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			CombatResolutionResource.format_profile(prepared_enemy_spell.intensity_profile),
			prepared_enemy_spell.damage
		]
	)

func _resolve_enemy_spell_collision(player_profile: Array) -> void:
	_assert_prepared_enemy_spell_invariant()

	var enemy_profile: Array = prepared_enemy_spell.intensity_profile
	var damage: int = prepared_enemy_spell.damage
	var spell_name: String = prepared_enemy_spell.name

	var player_died: bool = false

	var resolve: Dictionary = CombatResolutionResource.resolve_spell_collision(enemy_profile, player_profile, damage)
	if resolve["aspect_matched"] == "":
		var damage_to_apply := int(resolve["damage_dealt"])
		if damage_to_apply > 0:
			player_died = player.take_damage(damage_to_apply)
			_update_health_ui()
			last_defense_summary = "%s found no matching aspect and dealt %d damage." % [spell_name, damage_to_apply]
			_log_line("%s casts %s and hits for %d damage." % [opponent.display_name, spell_name, damage_to_apply])
			if player_died:
				_log_line("Your health is spent.")
		else:
			last_defense_summary = "%s had no matching aspect and fizzled." % spell_name
			_log_line("%s casts %s but it fizzles with no matching aspects." % [opponent.display_name, spell_name])
		return

	var pd := int(resolve["player_dice"])
	var pr := int(resolve["player_roll"])
	var ed := int(resolve["enemy_dice"])
	var er := int(resolve["enemy_roll"])
	var aspect := str(resolve["aspect_matched"])
	_log_line("%s casts %s targeting %s — %dd vs %dd. Player rolled %d, enemy rolled %d." % [opponent.display_name, spell_name, aspect, pd, ed, pr, er])

	if resolve["nullified"]:
		last_defense_summary = "Your %s roll (%d) beat the enemy roll (%d) and nullified the attack." % [aspect, pr, er]
		_log_line("Your spell nullifies %s." % spell_name)
		return

	# Enemy won the roll
	player_died = player.take_damage(int(resolve["damage_dealt"]))
	_update_health_ui()

	last_defense_summary = "%s broke through (roll lost %d vs %d) and dealt %d damage." % [spell_name, pr, er, resolve["damage_dealt"]]
	_log_line("%s breaks through. You take %d damage." % [spell_name, resolve["damage_dealt"]])

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
			spell.get_aspect_names()
		)
	)

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = null
	descriptor_vector.clear()
	state.clear()
	_reset_round_state()
	fight_notes.text = ""
	_set_ui_visible(false)
	combat_finished.emit(player_won)

func _reset_round_state(defense_summary: String = "") -> void:
	prepared_enemy_spell = null
	last_player_spell_name = ""
	last_player_resonance = 0.0
	last_player_profile = []
	last_context_update = {}
	last_defense_summary = defense_summary

func _log_line(message: String) -> void:
	print(message)
	battle_log.append_animated(message + "\n")

func _set_ui_visible(value: bool) -> void:
	fight_notes_frame.visible = value

func _assert_prepared_enemy_spell_invariant() -> void:
	assert(prepared_enemy_spell != null, "Prepared enemy spell is missing")
	assert(not prepared_enemy_spell.name.is_empty(), "Prepared enemy spell missing name")
	assert(prepared_enemy_spell.damage >= 0, "Prepared enemy spell missing or invalid damage")
	assert(not prepared_enemy_spell.aspect_scores.is_empty(), "Prepared enemy spell aspect_scores cannot be empty")
	assert(not prepared_enemy_spell.intensity_profile.is_empty(), "Prepared enemy spell intensity_profile cannot be empty")
