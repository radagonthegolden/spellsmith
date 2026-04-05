extends RefCounted
class_name CombatState

const SemanticScorerResource := preload("res://scripts/core/semantic_scorer.gd")

## Combat state system for Spellsmith.
## 
## Each aspect intensity_rank (0-3) represents the number of dice to roll in conflicts:
## - 0 (faint): No dice - spell is completely nullified
## - 1 (low): 1d6
## - 2 (medium): 2d6
## - 3 (high): 3d6
##
## When player and enemy spells clash on the same aspect, both roll their dice and
## the higher total wins. This adds meaningful randomness while still rewarding
## higher aspect accumulation.

# Dice system constants
const DICE_SIDES: int = 6  # d6

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
		var current_value: int = int(aspect_totals.get(name_text, 0))
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
		if str(entry["name"]) == aspect_name:
			return int(entry["score"])
	return 0

func get_scores() -> Array:
	return current_scores

static func build_primary_profile(scores: Array) -> Array:
	return _build_profile(scores, 1)

static func build_full_profile(scores: Array) -> Array:
	return _build_profile(scores, -1)

static func format_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		parts.append(str(entry["name"]) + " " + str(entry["intensity_rank"]) + "d")
	return ", ".join(parts)

static func filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	if player_profile.is_empty():
		return []

	var displayed: Array = [player_profile[0]]
	if enemy_profile.is_empty():
		return displayed

	var enemy_entry: Dictionary = enemy_profile[0]
	var enemy_aspect_name: String = str(enemy_entry["name"])
	var enemy_required_rank: int = int(enemy_entry["intensity_rank"])
	for player_entry in player_profile:
		if str(player_entry["name"]) != enemy_aspect_name:
			continue
		if int(player_entry["intensity_rank"]) < enemy_required_rank:
			continue
		if str(displayed[0]["name"]) != enemy_aspect_name:
			displayed.append(player_entry)
		return displayed

	return displayed

## Resolves a spell collision using the dice system.
## 
## Returns a Dictionary with:
## - "nullified" (bool): true if player's roll beat enemy's roll
## - "player_dice" (int): number of dice player rolled
## - "player_roll" (int): player's total dice roll
## - "enemy_dice" (int): number of dice enemy rolled
## - "enemy_roll" (int): enemy's total dice roll
## - "aspect_matched" (string): which aspect the dice roll was for (empty if no match)
##
## If the player and enemy have a matching aspect, both roll dice equal to their
## intensity_rank for that aspect. Highest roll wins. If no matching aspect exists,
## returns with "aspect_matched" empty.
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

	var enemy_entry: Dictionary = enemy_profile[0]
	for player_entry in player_profile:
		if str(player_entry["name"]) != str(enemy_entry["name"]):
			continue

		var player_dice: int = int(player_entry["intensity_rank"])
		var enemy_dice: int = int(enemy_entry["intensity_rank"])
		var player_roll: int = _roll_dice(player_dice)
		var enemy_roll: int = _roll_dice(enemy_dice)

		result["player_dice"] = player_dice
		result["player_roll"] = player_roll
		result["enemy_dice"] = enemy_dice
		result["enemy_roll"] = enemy_roll
		result["aspect_matched"] = str(player_entry["name"])
		result["nullified"] = player_roll >= enemy_roll

		return result

	return result

static func build_fight_notes(
	player: Battler,
	prepared_enemy_spell: Dictionary,
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
	if prepared_enemy_spell.is_empty():
		lines.append("None prepared.")
	else:
		lines.append(str(prepared_enemy_spell["name"]))
		lines.append("Pattern: " + format_profile(prepared_enemy_spell["_intensity_profile"]))

	lines.append("")
	lines.append("[b]Your Last Spell[/b]")
	if last_player_spell_name.is_empty():
		lines.append("None yet.")
	else:
		lines.append(last_player_spell_name)
		lines.append("Pattern: " + format_profile(filter_display_profile(last_player_profile, prepared_enemy_spell.get("_intensity_profile", []))))
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
		if str(entry["name"]) == aspect_name:
			return float(entry["score"])
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
		current_scores.append({
			"name": aspect_name,
			"score": int(aspect_totals[aspect_name])
		})
	current_scores.sort_custom(func(a, b): return a["score"] > b["score"])

static func _build_profile(scores: Array, max_entries: int) -> Array:
	var profile: Array = []
	var limit: int = scores.size() if max_entries < 0 else mini(max_entries, scores.size())
	for i in range(limit):
		var entry: Dictionary = scores[i]
		var score: float = float(entry["score"])
		profile.append({
			"name": str(entry["name"]),
			"score": score,
					"intensity_rank": SemanticScorerResource.score_to_intensity_rank(score),
					"intensity_label": SemanticScorerResource.score_to_intensity_label(score)

static func _roll_dice(dice_count: int) -> int:
	## Rolls dice_count d6s and returns the sum.
	##
	## Each die is a standard d6 (1-6). With 0 dice, returns 0.
	## With 1 die, returns 1-6. With N dice, returns N to 6*N.
	if dice_count <= 0:
		return 0

	var total: int = 0
	for i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total

static func _format_context_scores(current_scores: Array, progress_aspect_count: int) -> String:
	var parts: Array = []
	var limit: int = mini(progress_aspect_count, current_scores.size())
	for i in range(limit):
		var entry: Dictionary = current_scores[i]
		parts.append(str(entry["name"]) + " " + str(int(entry["score"])))
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

static func _score_to_intensity_label(score: float) -> String:
	return SemanticScorerResource.score_to_intensity_label(score)
