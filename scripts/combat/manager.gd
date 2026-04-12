extends Node
class_name CombatManager

signal combat_finished(player_won: bool)


# Node references
@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler
@onready var ui: CombatUI = $UI

# Dependency references
@onready var spell_runtime: SpellCasting = $"../SpellCasting"
@onready var enemy_library: Enemies = $Enemies
@onready var vector_math: VectorMath = $"../SpellCasting/VectorMath"
@onready var aspect_library: Aspects = $"../SpellCasting/AspectLibrary"

const DICE_SIDES: int = 6
const CONTEXT_MAX_VALUE: int = 6
enum TurnResult { PLAYER_WON, ENEMY_WON, ONGOING }


var active: bool = false
var current_enemy: Enemies.EnemyDefinition = null
var prepared_enemy_spell: SpellCasting.Spell = null
var context_state: Dictionary = {}

var turn_summary: Dictionary = {
	"player_spell": null,
	"enemy_spell": null,
	"context_update": null,
	"defense_summary": "",
}

func _ready() -> void:
	ui.set_ui_visible(false)
	ui.clear_fight_notes()

func start_battle(enemy_id: String = "pedantic_admitter") -> void:
	var enemy: Enemies.EnemyDefinition = await enemy_library.get_enemy(enemy_id)

	active = true
	current_enemy = enemy
	ui.log_line("The duel has just begun.")

	player.reset_health()
	opponent.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy.name
	
	for aspect_name in aspect_library.get_aspect_names():
		context_state[aspect_name] = 0

	ui.set_names(player.display_name, opponent.display_name)
	ui._update_health_ui()

	ui.set_turn_text("Turn: Player")
	ui.set_ui_visible(true)

	ui.log_line("")
	ui.log_line("A hostile presence condenses into the manuscript.")

	prepared_enemy_spell = await _prepare_enemy_spell(enemy)
	_refresh_fight_notes()

func _on_player_spell_cast(spell_name: String) -> TurnResult:
	ui.set_turn_text("Turn: Player")

	var player_spell: SpellCasting.Spell = await spell_runtime.cast_spell_on_enemy(
		spell_name,
		current_enemy
	)

	var displayed_player_profile: Array = spell_runtime.filter_display_profile(
		player_spell.actualized,
		prepared_enemy_spell.actualized
	)

	ui.log_line(
		"You cast \"%s\". Resonance %s. Pattern: %s." % [
			spell_name,
			str(snappedf(player_spell.resonance, 0.01)),
			spell_runtime.format_profile(displayed_player_profile)
		]
	)

	var returned := _update_context(player_spell.actualized, context_state)
	context_state = returned["new_context"]
	var context_update : Dictionary = returned["updates"]
	var defense_summary: String = ""

	if _meets_conditions(current_enemy.player_victory_conditions): 
		ui.set_turn_text("Turn: Victory")
		defense_summary = "Your spell completed the victory condition before the enemy attack could land."
		_refresh_fight_notes()
		ui.log_line("The context settles into a shape that breaks %s. Victory." % opponent.display_name)
		_finish_battle(true)
		return TurnResult.PLAYER_WON

	var collision_result := _collide_spells(
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
			ui._update_health_ui()
			defense_summary = "%s found no matching aspect and dealt %d damage." % [spell_name, damage_to_apply]
			ui.log_line("%s casts %s and hits for %d damage." % [opponent.display_name, spell_name, damage_to_apply])
			if player_died:
				ui.log_line("Your health is spent.")
		else:
			defense_summary = "%s had no matching aspect and fizzled." % spell_name
			ui.log_line("%s casts %s but it fizzles with no matching aspects." % [opponent.display_name, spell_name])
		ui.log_line("%s casts %s targeting %s — %dd vs %dd. Player rolled %d, enemy rolled %d." \
		% [opponent.display_name, spell_name, prepared_enemy_spell.actualized[0].name, pd, ed, pr, er])
	else:
		defense_summary = "Your %s roll (%d) beat the enemy roll (%d) and nullified the attack." \
		% [prepared_enemy_spell.actualized[0].name, pr, er]
		ui.log_line("Your spell nullifies %s." % spell_name)

	_refresh_fight_notes()

	if player_died:
		ui.set_turn_text("Turn: Defeat")
		ui.log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	if _meets_conditions(current_enemy.player_loss_conditions):
		ui.set_turn_text("Turn: Defeat")
		ui.log_line("%s draws the context into its own design. Defeat." % opponent.display_name)
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	ui.set_turn_text("Turn: Player")
	_prepare_enemy_spell(current_enemy)
	_refresh_fight_notes()

	turn_summary = {
		"player_spell": player_spell,
		"enemy_spell": prepared_enemy_spell,
		"context_update": context_update,
		"defense_summary": defense_summary,
	}

	return TurnResult.ONGOING

func _collide_spells(
	enemy_aspect: Aspects.ActualizedAspect,
	player_profile: Array
	) -> Dictionary:

	var result: Dictionary = {
		"player_dice": 0,
		"player_roll": 0,
		"enemy_dice": 0,
		"enemy_roll": 0,
	}

	var primary_aspect : int = -1
	for i in range(player_profile.size()):
		var aspect_data: Aspects.ActualizedAspect = aspect_library.as_actualized(player_profile[i])
		if aspect_data.name == enemy_aspect.name:
			primary_aspect = i
			break
	var player_aspect : Aspects.ActualizedAspect = player_profile[primary_aspect]

	var player_dice: int = player_aspect.intensity_rank
	var enemy_dice: int = enemy_aspect.intensity_rank

	var player_roll: int = _roll_dice(player_dice)
	var enemy_roll: int = _roll_dice(enemy_dice)

	result["player_dice"] = player_dice
	result["player_roll"] = player_roll
	result["enemy_dice"] = enemy_dice
	result["enemy_roll"] = enemy_roll

	return result

func _meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if context_state[condition["aspect"]] >= int(condition["intensity"]):
			return true
	return false

func _prepare_enemy_spell(enemy: Enemies.EnemyDefinition) -> SpellCasting.EnemySpell:
	prepared_enemy_spell = await enemy_library.cast_random_spell(enemy)

	ui.log_line(
		"%s casts %s. Pattern: %s. Damage: %d." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			spell_runtime.format_profile(prepared_enemy_spell.actualized),
			prepared_enemy_spell.damage
		]
	)

	return prepared_enemy_spell

func _update_context(actualized: Array, context: Dictionary) -> Dictionary:
	var updateds := {}
	for aspect in actualized:
		var next_value: int = _dampen_update(
			context[aspect.name], 
			actualized[aspect.name].intensity_rank
		)
		updateds[aspect.name] = next_value
		context[aspect.name] += next_value
	return {"new_context": context, "updates": updateds}

func _dampen_update(current_value: int, update_value: int) -> int:
	var dampening: int = 0
	if current_value == 0:
		dampening = 0
	elif current_value <= 1:
		dampening = -1
	elif current_value <= 3:
		dampening = -2
	return clampi(current_value + update_value + dampening, 0, CONTEXT_MAX_VALUE)

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = null
	ui.clear_fight_notes()
	ui.set_ui_visible(false)
	combat_finished.emit(player_won)

func _roll_dice(dice_count: int) -> int:
	var total: int = 0
	for _i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total

func _refresh_fight_notes() -> void:
	ui.refresh_fight_notes(
		active,
		spell_runtime,
		player,
		turn_summary["player_spell"],
		turn_summary["enemy_spell"],
		context_state,
		turn_summary["context_update"],
		turn_summary["defense_summary"],
	)
