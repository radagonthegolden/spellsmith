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

var state_aspect_names: PackedStringArray = PackedStringArray()
var state_aspect_totals: Dictionary = {}
var state_current_scores: Array = []
var state_max_value: int = 6

var active: bool = false
var current_enemy: Enemies.EnemyDefinition = null
var descriptor_vector: Array = []
var prepared_enemy_spell: SpellCasting.Spell = null
var last_player_spell_name: String = ""
var last_player_resonance: float = 0.0
var last_player_profile: Array = []
var last_context_update: Dictionary = {}
var last_defense_summary: String = ""

func _ready() -> void:
	assert(spell_runtime != null, "CombatManager missing SpellCasting node")
	assert(enemy_library != null, "CombatManager missing Enemies node")
	_set_ui_visible(false)
	fight_notes.text = ""

func start_battle(enemy_id: String = "pedantic_admitter") -> void:
	var enemy: Enemies.EnemyDefinition = await enemy_library.get_enemy(enemy_id)
	assert(not enemy.descriptor.is_empty(), "Enemy descriptor cannot be empty: %s" % enemy_id)

	active = true
	current_enemy = enemy
	descriptor_vector = current_enemy.descriptor
	_reset_round_state("The duel has just begun.")

	player.reset_health()
	opponent.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy.name
	_state_setup(spell_runtime.get_aspect_names(), context_max_value)

	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()

	turn_label.text = "Turn: Player"
	_set_ui_visible(true)

	_log_line("")
	_log_line("A hostile presence condenses into the manuscript.")

	_prepare_enemy_spell()
	_refresh_fight_notes()

func _on_spell_encoded(spell_embedding: Array, text: String) -> void:
	if not active:
		return

	turn_label.text = "Turn: Player"

	var spell_aspect_scores: Array = spell_runtime.score_spell_embedding(spell_embedding, text)
	var effective_resonance: float = _get_effective_resonance(
		VectorMath.cosine_similarity(spell_embedding, descriptor_vector)
	)
	var effective_scores: Array = spell_runtime.scale_spell_scores(spell_aspect_scores, effective_resonance)

	last_context_update = _state_apply_spell(effective_scores)
	last_player_spell_name = text
	last_player_resonance = effective_resonance
	last_player_profile = spell_runtime.build_full_profile(effective_scores)
	_assert_prepared_enemy_spell_invariant()

	var displayed_player_profile: Array = spell_runtime.filter_display_profile(
		last_player_profile,
		prepared_enemy_spell.intensity_profile
	)

	_log_line(
		"You cast \"%s\". Resonance %s. Pattern: %s." % [
			text,
			str(snappedf(effective_resonance, 0.01)),
			spell_runtime.format_profile(displayed_player_profile)
		]
	)

	if _state_meets_conditions(current_enemy.player_victory_conditions):
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

	if _state_meets_conditions(current_enemy.player_loss_conditions):
		turn_label.text = "Turn: Defeat"
		_log_line("%s draws the context into its own design. Defeat." % opponent.display_name)
		_finish_battle(false)
		return

	turn_label.text = "Turn: Player"
	_prepare_enemy_spell()
	_refresh_fight_notes()

func _get_effective_resonance(raw_resonance: float) -> float:
	assert(current_enemy != null, "Current enemy is null")
	var min_resonance: float = current_enemy.min_descriptor_resonance
	var max_resonance: float = current_enemy.max_descriptor_resonance
	return lerpf(min_resonance, max_resonance, clampf(raw_resonance, 0.0, 1.0))

func _prepare_enemy_spell() -> void:
	assert(current_enemy != null, "Current enemy is null")
	assert(not current_enemy.spells.is_empty(), "Current enemy has no spells")

	var selected_index: int = randi_range(0, current_enemy.spells.size() - 1)
	prepared_enemy_spell = enemy_library.prepare_spell(current_enemy, selected_index)
	_assert_prepared_enemy_spell_invariant()

	_log_line(
		"%s casts %s. Pattern: %s. Damage: %d." % [
			opponent.display_name,
			prepared_enemy_spell.name,
			spell_runtime.format_profile(prepared_enemy_spell.intensity_profile),
			prepared_enemy_spell.damage
		]
	)

func _resolve_enemy_spell_collision(player_profile: Array) -> void:
	_assert_prepared_enemy_spell_invariant()

	var enemy_profile: Array = prepared_enemy_spell.intensity_profile
	var damage: int = prepared_enemy_spell.damage
	var spell_name: String = prepared_enemy_spell.name

	var player_died: bool = false

	var collision_result: Dictionary = CollisionEngine.resolve_spell_collision(enemy_profile, player_profile, damage)
	if collision_result["aspect_matched"] == "":
		var damage_to_apply := int(collision_result["damage_dealt"])
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

	var pd := int(collision_result["player_dice"])
	var pr := int(collision_result["player_roll"])
	var ed := int(collision_result["enemy_dice"])
	var er := int(collision_result["enemy_roll"])
	var aspect := str(collision_result["aspect_matched"])
	_log_line("%s casts %s targeting %s — %dd vs %dd. Player rolled %d, enemy rolled %d." % [opponent.display_name, spell_name, aspect, pd, ed, pr, er])

	if collision_result["nullified"]:
		last_defense_summary = "Your %s roll (%d) beat the enemy roll (%d) and nullified the attack." % [aspect, pr, er]
		_log_line("Your spell nullifies %s." % spell_name)
		return

	# Enemy won the roll
	player_died = player.take_damage(int(collision_result["damage_dealt"]))
	_update_health_ui()

	last_defense_summary = "%s broke through (roll lost %d vs %d) and dealt %d damage." % [spell_name, pr, er, collision_result["damage_dealt"]]
	_log_line("%s breaks through. You take %d damage." % [spell_name, collision_result["damage_dealt"]])

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
		FightNotesRenderer.build_fight_notes(
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
	descriptor_vector.clear()
	_state_clear()
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

# State management methods (moved from CombatState script)

func _state_setup(next_aspect_names: PackedStringArray, next_max_value: int) -> void:
	state_aspect_names = next_aspect_names
	state_max_value = next_max_value
	state_aspect_totals.clear()
	for aspect_name in state_aspect_names:
		state_aspect_totals[str(aspect_name)] = 0
	_state_rebuild_scores()

func _state_clear() -> void:
	state_aspect_names = PackedStringArray()
	state_aspect_totals.clear()
	state_current_scores.clear()

func _state_apply_spell(effective_scores: Array) -> Dictionary:
	var delta_by_aspect: Dictionary = {}
	for aspect_name in state_aspect_names:
		var name_text: String = str(aspect_name)
		assert(state_aspect_totals.has(name_text), "Missing aspect total for: " + name_text)
		var current_value: int = int(state_aspect_totals[name_text])
		var update_value: int = AspectLibrary.score_to_intensity_rank(_state_score_for_aspect(effective_scores, name_text))
		var next_value: int = _state_update_value(current_value, update_value)
		state_aspect_totals[name_text] = next_value
		delta_by_aspect[name_text] = next_value - current_value

	_state_rebuild_scores()
	return delta_by_aspect

func _state_meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if _state_get_value(str(condition["aspect"])) < int(condition["intensity"]):
			return false
	return true

func _state_get_value(aspect_name: String) -> int:
	for entry in state_current_scores:
		var aspect_data: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(entry)
		if aspect_data.name == aspect_name:
			return int(aspect_data.score)
	return 0

func _state_get_scores() -> Array:
	return state_current_scores

func _state_score_for_aspect(scores: Array, aspect_name: String) -> float:
	for entry in scores:
		var aspect_data: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(entry)
		if aspect_data.name == aspect_name:
			return aspect_data.score
	assert(false, "Missing score entry for aspect: " + aspect_name)
	return 0.0

func _state_update_value(current_value: int, update_value: int) -> int:
	var dampening: int = 0
	if current_value == 0:
		dampening = 0
	elif current_value <= 1:
		dampening = -1
	elif current_value <= 3:
		dampening = -2
	return clampi(current_value + update_value + dampening, 0, state_max_value)

func _state_rebuild_scores() -> void:
	state_current_scores.clear()
	for aspect_name in state_aspect_totals.keys():
		state_current_scores.append(AspectLibrary.make_actualized(str(aspect_name), float(state_aspect_totals[aspect_name])))
	state_current_scores.sort_custom(func(a, b): return (a as AspectLibrary.ActualizedAspect).score > (b as AspectLibrary.ActualizedAspect).score)
