extends Node
class_name CombatResolution

const AspectLibraryResource = preload("res://scripts/core/aspects.gd")
const DICE_SIDES: int = 6

static func build_primary_profile(scores: Array) -> Array:
	return _build_profile(scores, 1)

static func build_full_profile(scores: Array) -> Array:
	return _build_profile(scores, -1)

static func format_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		var data: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(entry)
		parts.append(data.name + " " + str(data.intensity_rank) + "d")
	return ", ".join(parts)

static func filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	if player_profile.is_empty():
		return []
	var first_player: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(player_profile[0])

	var displayed: Array = [first_player]
	if enemy_profile.is_empty():
		return displayed

	var enemy_entry: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(enemy_profile[0])
	var enemy_aspect_name: String = enemy_entry.name
	var enemy_required_rank: int = enemy_entry.intensity_rank
	for player_entry in player_profile:
		var player_data: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(player_entry)
		if player_data.name != enemy_aspect_name:
			continue
		if player_data.intensity_rank < enemy_required_rank:
			continue
		if (displayed[0] as AspectLibrary.ActualizedAspect).name != enemy_aspect_name:
			displayed.append(player_data)
		return displayed

	return displayed

static func player_nullifies_enemy_spell(enemy_profile: Array, player_profile: Array) -> Dictionary:
	var result: Dictionary = {
		"nullified": false,
		"player_dice": 0,
		"player_roll": 0,
		"enemy_dice": 0,
		"enemy_roll": 0,
		"aspect_matched": ""
	}

	if enemy_profile.is_empty() or player_profile.is_empty():
		return result

	var enemy_entry: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(enemy_profile[0])
	for player_entry in player_profile:
		var player_data: AspectLibrary.ActualizedAspect = AspectLibraryResource.as_actualized(player_entry)
		if player_data.name != enemy_entry.name:
			continue

		var player_dice: int = player_data.intensity_rank
		var enemy_dice: int = enemy_entry.intensity_rank
		var player_roll: int = _roll_dice(player_dice)
		var enemy_roll: int = _roll_dice(enemy_dice)

		result["player_dice"] = player_dice
		result["player_roll"] = player_roll
		result["enemy_dice"] = enemy_dice
		result["enemy_roll"] = enemy_roll
		result["aspect_matched"] = player_data.name
		result["nullified"] = player_roll >= enemy_roll
		return result

	return result

static func resolve_spell_collision(enemy_profile: Array, player_profile: Array, damage: int) -> Dictionary:
	var res: Dictionary = player_nullifies_enemy_spell(enemy_profile, player_profile)
	assert(res.has("nullified"), "Collision result missing nullified flag")
	res["damage_dealt"] = 0 if bool(res["nullified"]) else int(damage)
	return res

static func _build_profile(scores: Array, max_entries: int) -> Array:
	var profile: Array = []
	var limit: int = scores.size() if max_entries < 0 else mini(max_entries, scores.size())
	for i in range(limit):
		profile.append(AspectLibraryResource.as_actualized(scores[i]))
	return profile

static func _roll_dice(dice_count: int) -> int:
	if dice_count <= 0:
		return 0

	var total: int = 0
	for _i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total