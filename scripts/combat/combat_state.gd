extends RefCounted
class_name CombatState

const SemanticScorerResource = preload("res://scripts/core/semantic_scorer.gd")
const CombatResolutionResource = preload("res://scripts/combat/combat_resolution.gd")
const AspectLibraryResource = preload("res://scripts/core/aspects.gd")

var aspect_names: PackedStringArray = PackedStringArray()
var aspect_totals: Dictionary = {}
var current_scores: Array = []
var max_value: int = 6

func setup(next_aspect_names: PackedStringArray, next_max_value: int) -> void:
	aspect_names = next_aspect_names
	max_value = next_max_value
	aspect_totals.clear()
	for aspect_name in aspect_names:
		aspect_totals[str(aspect_name)] = 0
	_rebuild_scores()

func clear() -> void:
	aspect_names = PackedStringArray()
	aspect_totals.clear()
	current_scores.clear()

func apply_spell(effective_scores: Array) -> Dictionary:
	var delta_by_aspect: Dictionary = {}
	for aspect_name in aspect_names:
		var name_text: String = str(aspect_name)
		assert(aspect_totals.has(name_text), "Missing aspect total for: " + name_text)
		var current_value: int = int(aspect_totals[name_text])
		var update_value: int = _score_to_intensity_rank(_score_for_aspect(effective_scores, name_text))
		var next_value: int = _update_value(current_value, update_value)
		aspect_totals[name_text] = next_value
		delta_by_aspect[name_text] = next_value - current_value

	_rebuild_scores()
	return delta_by_aspect

func meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		if get_value(str(condition["aspect"])) < int(condition["intensity"]):
			return false
	return true

func get_value(aspect_name: String) -> int:
	for entry in current_scores:
		var aspect_data: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(entry)
		if aspect_data.name == aspect_name:
			return int(aspect_data.score)
	return 0

func get_scores() -> Array:
	return current_scores

static func build_fight_notes(
	player: Battler,
	prepared_enemy_spell: Enemies.PreparedEnemySpell,
	last_player_spell_name: String,
	last_player_profile: Array,
	last_player_resonance: float,
	last_context_update: Dictionary,
	current_scores: Array,
	last_defense_summary: String,
	progress_aspect_count: int,
	aspect_names: PackedStringArray
) -> String:
	var lines: Array[String] = [
		"[b]Fight Notes[/b]",
		"",
		"[b]Health[/b]",
		"You: %d/%d" % [player.health, player.max_health],
		"",
		"[b]Enemy Spell[/b]"
	]
	if prepared_enemy_spell == null:
		lines.append("None prepared.")
	else:
		assert(not prepared_enemy_spell.intensity_profile.is_empty(), "Prepared enemy spell is missing intensity_profile")
		lines.append(prepared_enemy_spell.name)
		lines.append("Pattern: " + CombatResolutionResource.format_profile(prepared_enemy_spell.intensity_profile))

	lines.append("")
	lines.append("[b]Your Last Spell[/b]")
	if last_player_spell_name.is_empty():
		lines.append("None yet.")
	else:
		lines.append(last_player_spell_name)
		var enemy_profile: Array = []
		if prepared_enemy_spell != null:
			assert(not prepared_enemy_spell.intensity_profile.is_empty(), "Prepared enemy spell is missing intensity_profile")
			enemy_profile = prepared_enemy_spell.intensity_profile
		lines.append("Pattern: " + CombatResolutionResource.format_profile(CombatResolutionResource.filter_display_profile(last_player_profile, enemy_profile)))
		lines.append("Resonance: " + str(snappedf(last_player_resonance, 0.01)))
		lines.append("Context Update: " + _format_context_update(last_context_update, aspect_names))

	lines.append("")
	lines.append("[b]Context[/b]")
	lines.append(_format_context_scores(current_scores, progress_aspect_count))
	lines.append("")
	lines.append("[b]Last Resolution[/b]")
	lines.append(last_defense_summary)
	return "\n".join(lines)

func _score_for_aspect(scores: Array, aspect_name: String) -> float:
	for entry in scores:
		var aspect_data: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(entry)
		if aspect_data.name == aspect_name:
			return aspect_data.score
	assert(false, "Missing score entry for aspect: " + aspect_name)
	return 0.0

func _update_value(current_value: int, update_value: int) -> int:
	var dampening: int = 0
	if current_value == 0:
		dampening = 0
	elif current_value <= 1:
		dampening = -1
	elif current_value <= 3:
		dampening = -2
	return clampi(current_value + update_value + dampening, 0, max_value)

func _rebuild_scores() -> void:
	current_scores.clear()
	for aspect_name in aspect_totals.keys():
		current_scores.append(AspectLibraryResource.make_actualized(str(aspect_name), float(aspect_totals[aspect_name])))
	current_scores.sort_custom(func(a, b): return (a as AspectLibrary.ActualizedAspect).score > (b as AspectLibrary.ActualizedAspect).score)

static func _format_context_scores(current_scores: Array, progress_aspect_count: int) -> String:
	var parts: Array = []
	var limit: int = mini(progress_aspect_count, current_scores.size())
	for i in range(limit):
		var entry: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(current_scores[i])
		parts.append(entry.name + " " + str(int(entry.score)))
	return ", ".join(parts)

static func _format_context_update(update: Dictionary, aspect_names: PackedStringArray) -> String:
	var parts: Array = []
	for aspect_name in aspect_names:
		var delta: int = int(update.get(str(aspect_name), 0))
		if delta <= 0:
			continue
		parts.append("%s +%d" % [str(aspect_name), delta])
	if parts.is_empty():
		return "No aspect gained pressure."
	return ", ".join(parts)

static func _score_to_intensity_rank(score: float) -> int:
	return SemanticScorerResource.score_to_intensity_rank(score)
