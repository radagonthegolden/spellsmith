extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler
@onready var ui: CombatUI = $UI

@onready var spell_casting: SpellCasting = $"../SpellCasting"
@onready var enemy_library: Enemies = $Enemies
@onready var aspect_library: Aspects = $"../SpellCasting/AspectLibrary"

const DICE_SIDES: int = 6
const CONTEXT_MAX_VALUE: int = 6
enum TurnResult { PLAYER_WON, ENEMY_WON, ONGOING }

var active := false
var current_enemy: Enemies.EnemyDefinition = null
var prepared_enemy_spell: SpellCasting.EnemySpell = null
var context_state: Dictionary = {}

var combat_notes: CombatUI.CombatNotes = CombatUI.CombatNotes.new()

func _ready() -> void:
	ui.set_ui_visible(false)
	ui.clear_fight_notes()

func start_battle(enemy_id: String = "pedantic_admitter") -> void:
	var enemy: Enemies.EnemyDefinition = await enemy_library.get_enemy(enemy_id)

	active = true
	current_enemy = enemy
	prepared_enemy_spell = null
	context_state.clear()

	player.display_name = "You"
	opponent.display_name = enemy.name

	for aspect_name in aspect_library.get_aspect_names():
		context_state[aspect_name] = 0

	ui.set_ui_visible(true)

	ui.log_line("The duel has just begun.")
	ui.log_line("")
	ui.log_line("A hostile presence condenses into the manuscript.")

	prepared_enemy_spell = await _prepare_enemy_spell(enemy)
	print(prepared_enemy_spell.profile.profile)

	combat_notes = CombatUI.CombatNotes.new()

	combat_notes.enemy_name = enemy.name
	combat_notes.enemy_spell = prepared_enemy_spell
	combat_notes.context = context_state.duplicate()
	combat_notes.player_health = player.health
	combat_notes.player_max_health = player.max_health

	ui.refresh_combat_notes(combat_notes)

func submit_spell(spell_name: String) -> TurnResult:
	if not active:
		return TurnResult.ONGOING

	var player_spell: SpellCasting.Spell = await spell_casting.cast_spell_on_enemy(
		spell_name,
		current_enemy
	)

	var context_update: Dictionary = _update_context(player_spell.profile)
	var turn_summary: String = ""

	ui.log_line(
		"You cast \"%s\". Resonance %s. Pattern: %s." % [
			spell_name,
			str(snappedf(player_spell.resonance, 0.01)),
			spell_casting.aspect_library.profile_to_string(player_spell.profile)
		]
	)

	if _meets_conditions(current_enemy.player_victory_conditions):
		combat_notes.turn_summary = "Your spell completed the victory condition before the enemy attack could land."
		ui.refresh_combat_notes(combat_notes)
		ui.log_line("The context settles into a shape that breaks %s. Victory." % opponent.display_name)
		_finish_battle(true)
		return TurnResult.PLAYER_WON

	var enemy_aspect: Aspects.ActualizedAspect = prepared_enemy_spell.spell.profile.profile[0]
	var collision_result := _collide_spells(enemy_aspect, player_spell.profile)
	var player_roll := int(collision_result["player_roll"])
	var enemy_roll := int(collision_result["enemy_roll"])
	var player_died := false

	if player_roll < enemy_roll:
		var damage_to_apply := prepared_enemy_spell.damage

		player_died = player.take_damage(damage_to_apply)
		turn_summary = "%s broke through for %d damage." % [prepared_enemy_spell.name, damage_to_apply]
		ui.log_line("%s casts %s and hits for %d damage." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			damage_to_apply
		])
		if player_died:
			ui.log_line("Your health is spent.")

		ui.log_line("%s casts %s targeting %s - %dd vs %dd. Player rolled %d, enemy rolled %d." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			enemy_aspect.name,
			int(collision_result["player_dice"]),
			int(collision_result["enemy_dice"]),
			player_roll,
			enemy_roll
		])
	else:
		turn_summary = "Your %s roll (%d) matched or beat the enemy roll (%d) and nullified the attack." % [
			enemy_aspect.name,
			player_roll,
			enemy_roll
		]
		ui.log_line("Your spell nullifies %s." % prepared_enemy_spell.name)

	combat_notes.player_spell = player_spell
	combat_notes.enemy_spell = prepared_enemy_spell
	combat_notes.context_update = context_update
	combat_notes.turn_summary = turn_summary
	combat_notes.player_health = player.health

	ui.refresh_combat_notes(combat_notes)

	if player_died:
		ui.log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	if _meets_conditions(current_enemy.player_loss_conditions):
		ui.log_line("%s draws the context into its own design. Defeat." % opponent.display_name)
		_finish_battle(false)
		return TurnResult.ENEMY_WON

	prepared_enemy_spell = await _prepare_enemy_spell(current_enemy)
	combat_notes.enemy_spell = prepared_enemy_spell
	ui.refresh_combat_notes(combat_notes)
	return TurnResult.ONGOING

func _collide_spells(
	enemy_aspect: Aspects.ActualizedAspect, 
	player_profile: Aspects.ActualizedProfile
	) -> Dictionary:
	var player_dice := 0
	for aspect in player_profile.profile:
		var aspect_data: Aspects.ActualizedAspect = aspect
		if aspect_data.name == enemy_aspect.name:
			player_dice = aspect_data.intensity_rank
			break

	var enemy_dice: int = enemy_aspect.intensity_rank
	return {
		"player_dice": player_dice,
		"player_roll": _roll_dice(player_dice),
		"enemy_dice": enemy_dice,
		"enemy_roll": _roll_dice(enemy_dice),
	}

func _meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if context_state[condition["aspect"]] >= int(condition["intensity"]):
			return true
	return false

func _prepare_enemy_spell(enemy: Enemies.EnemyDefinition) -> SpellCasting.EnemySpell:
	var next_enemy_spell := await enemy_library.cast_random_spell(enemy)
	ui.log_line(
		"%s casts %s. Pattern: %s. Damage: %d." % [
			opponent.display_name,
			next_enemy_spell.spell.name,
			spell_casting.aspect_library.profile_to_string(next_enemy_spell.spell.profile),
			next_enemy_spell.damage
		]
	)
	return next_enemy_spell

func _update_context(profile: Aspects.ActualizedProfile) -> Dictionary:
	var updates := {}
	for aspect in profile.profile:
		var current_value: int = int(context_state.get(aspect.name, 0))
		var next_value: int = _dampen_update(current_value, aspect.intensity_rank)
		updates[aspect.name] = next_value
		context_state[aspect.name] = clampi(current_value + next_value, 0, CONTEXT_MAX_VALUE)
	return updates

func _dampen_update(current_value: int, update_value: int) -> int:
	var dampening := 0
	if current_value <= 1 and current_value > 0:
		dampening = -1
	elif current_value <= 3 and current_value > 1:
		dampening = -2
	return clampi(update_value + dampening, 0, CONTEXT_MAX_VALUE - current_value)

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = null
	prepared_enemy_spell = null
	ui.clear_fight_notes()
	ui.set_ui_visible(false)
	combat_finished.emit(player_won)

func _roll_dice(dice_count: int) -> int:
	var total := 0
	for _i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total
