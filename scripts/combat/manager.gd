extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

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
@onready var spell_runtime: SpellCasting = $"../SpellCasting"
@onready var enemy_library: Enemies = $Enemies
@onready var vector_math: VectorMath = $"../SpellCasting/VectorMath"
@onready var collision_engine: CollisionEngine = $CollisionEngine
@onready var fight_notes_renderer: FightNotesRenderer = $FightNotesRenderer
@onready var aspect_library: Aspects = $"../SpellCasting/AspectLibrary"

const DICE_SIDES = 6
enum TurnResult { PLAYER_WON, ENEMY_WON, ONGOING }

var active: bool = false
var current_enemy: Enemies.EnemyDefinition = null
var prepared_enemy_spell: SpellCasting.Spell = null
var context_state := {}

var last_player_spell_name: String = ""
var last_player_resonance: float = 0.0
var last_player_profile: Array = []
var last_context_update: Dictionary = {}
var last_defense_summary: String = ""

func _ready() -> void:
	_set_ui_visible(false)
	fight_notes.text = ""

func start_battle(enemy_id: String = "pedantic_admitter") -> void:
	var enemy: Enemies.EnemyDefinition = await enemy_library.get_enemy(enemy_id)

	active = true
	current_enemy = enemy
	_reset_round_state("The duel has just begun.")

	player.reset_health()
	opponent.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy.name
	
	for aspect_name in aspect_library.get_aspect_names():
		context_state[aspect_name] = 0

	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()

	turn_label.text = "Turn: Player"
	_set_ui_visible(true)

	_log_line("")
	_log_line("A hostile presence condenses into the manuscript.")

	prepared_enemy_spell = await _prepare_enemy_spell(enemy)
	_refresh_fight_notes()

func _on_player_spell_cast(spell_name: String) -> TurnResult:
	turn_label.text = "Turn: Player"

	var player_spell: SpellCasting.Spell = await spell_runtime.cast_spell_on_enemy(
		spell_name,
		current_enemy
	)

	var displayed_player_profile: Array = spell_runtime.filter_display_profile(
		player_spell.actualized,
		prepared_enemy_spell.actualized
	)

	_log_line(
		"You cast \"%s\". Resonance %s. Pattern: %s." % [
			spell_name,
			str(snappedf(player_spell.resonance, 0.01)),
			spell_runtime.format_profile(displayed_player_profile)
		]
	)

	for aspect_name in context_state.keys():
		context_state[aspect_name] += player_spell.actualized[aspect_name].intensity_rank

	if _meets_conditions(current_enemy.player_victory_conditions):
		turn_label.text = "Turn: Victory"
		last_defense_summary = "Your spell completed the victory condition before the enemy attack could land."
		_refresh_fight_notes()
		_log_line("The context settles into a shape that breaks %s. Victory." % opponent.display_name)
		_finish_battle(true)
		return TurnResult.PLAYER_WON

	var collision_result := _resolve_spell_collision(
		prepared_enemy_spell.actualized[0], 
		prepared_enemy_spell.actualized
	)
	var pd := int(collision_result["player_dice"])
	var pr := int(collision_result["player_roll"])
	var ed := int(collision_result["enemy_dice"])
	var er := int(collision_result["enemy_roll"])
	var player_died := false
	if collision_result["player_roll"] < collision_result["enemy_roll"]:
		var damage_to_apply : int = prepared_enemy_spell.damage
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
		_log_line("%s casts %s targeting %s — %dd vs %dd. Player rolled %d, enemy rolled %d." \
		% [opponent.display_name, spell_name, prepared_enemy_spell.actualized[0].name, pd, ed, pr, er])
	else:
		last_defense_summary = "Your %s roll (%d) beat the enemy roll (%d) and nullified the attack." \
		% [prepared_enemy_spell.actualized[0].name, pr, er]
		_log_line("Your spell nullifies %s." % spell_name)

	_refresh_fight_notes()

	if player_died:
		turn_label.text = "Turn: Defeat"
		_log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	if _meets_conditions(current_enemy.player_loss_conditions):
		turn_label.text = "Turn: Defeat"
		_log_line("%s draws the context into its own design. Defeat." % opponent.display_name)
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	turn_label.text = "Turn: Player"
	_prepare_enemy_spell(current_enemy)
	_refresh_fight_notes()
	return TurnResult.ONGOING

func _meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if context_state[condition["aspect"]] >= int(condition["intensity"]):
			return true
	return false

func _prepare_enemy_spell(enemy: Enemies.EnemyDefinition) -> SpellCasting.EnemySpell:
	prepared_enemy_spell = await enemy_library.cast_random_spell(enemy)

	_log_line(
		"%s casts %s. Pattern: %s. Damage: %d." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			spell_runtime.format_profile(prepared_enemy_spell.actualized),
			prepared_enemy_spell.damage
		]
	)

	return prepared_enemy_spell


func _update_health_ui() -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func _refresh_fight_notes() -> void:
	if not active:
		fight_notes.text = ""
		return

	fight_notes.clear()
	fight_notes.append_text(
		fight_notes_renderer.build_fight_notes(
			spell_runtime,
			player,
			prepared_enemy_spell,
			last_player_spell_name,
			last_player_profile,
			last_player_resonance,
			last_context_update,
			_state_get_scores(),
			last_defense_summary,
			progress_aspect_count,
			spell_runtime.get_aspect_names()
		)
	)

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = null
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

static func _collide_spells(
	enemy_aspect: Aspects.ActualizedAspect,
	player_profile: Array
	) -> Dictionary:

	var result: Dictionary = {
		"player_dice": 0,
		"player_roll": 0,
		"enemy_dice": 0,
		"enemy_roll": 0,
	}

	var player_aspect : Aspects.ActualizedAspect = player_profile[enemy_aspect.name]
	var player_dice: int = player_aspect.intensity_rank
	var enemy_dice: int = enemy_aspect.intensity_rank

	var player_roll: int = _roll_dice(player_dice)
	var enemy_roll: int = _roll_dice(enemy_dice)

	result["player_dice"] = player_dice
	result["player_roll"] = player_roll
	result["enemy_dice"] = enemy_dice
	result["enemy_roll"] = enemy_roll

	return result

static func _roll_dice(dice_count: int) -> int:
	var total: int = 0
	for _i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total