extends Node

var state_aspect_names: PackedStringArray = PackedStringArray()
var state_aspect_totals: Dictionary = {}
var state_current_scores: Array = []
var state_max_value: int = 6

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
