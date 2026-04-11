extends RefCounted
class_name FightNotesRenderer
@onready var aspect_library: AspectLibrary = $"../../SpellCasting/AspectLibrary"

static func build_fight_notes(
	spell_runtime: SpellCasting,
	player: Battler,
	prepared_enemy_spell: SpellCasting.Spell,
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
		lines.append("Pattern: " + spell_runtime.format_profile(prepared_enemy_spell.intensity_profile))

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
		lines.append("Pattern: " + spell_runtime.format_profile(spell_runtime.filter_display_profile(last_player_profile, enemy_profile)))
		lines.append("Resonance: " + str(snappedf(last_player_resonance, 0.01)))
		lines.append("Context Update: " + _format_context_update(last_context_update, aspect_names))

	lines.append("")
	lines.append("[b]Context[/b]")
	lines.append(_format_context_scores(current_scores, progress_aspect_count))
	lines.append("")
	lines.append("[b]Last Resolution[/b]")
	lines.append(last_defense_summary)
	return "\n".join(lines)

static func _format_context_scores(current_scores: Array, progress_aspect_count: int) -> String:
	var parts: Array = []
	var limit: int = mini(progress_aspect_count, current_scores.size())
	for i in range(limit):
		var entry: AspectLibrary.ActualizedAspect = aspect_library.as_actualized(current_scores[i])
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
