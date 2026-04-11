extends Node
class_name CombatUI

@onready var player_ui: BattlerUI = $"../../HiddenUi/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../../HiddenUi/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../../HiddenUi/TurnRow/TurnLabel"
@onready var battle_log = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"
@onready var fight_notes_frame: PanelContainer = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame"
@onready var fight_notes: RichTextLabel = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame/FightNotesMargin/FightNotes"
@onready var aspect_library: AspectLibrary = $"../../SpellCasting/AspectLibrary"

func set_names(player_name: String, opponent_name: String) -> void:
	player_ui.set_name_text(player_name)
	opponent_ui.set_name_text(opponent_name)

func set_turn_text(text: String) -> void:
	turn_label.text = text

func update_health(player: Battler, opponent: Battler) -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func clear_fight_notes() -> void:
	fight_notes.text = ""

func set_ui_visible(value: bool) -> void:
	fight_notes_frame.visible = value

func log_line(message: String) -> void:
	print(message)
	battle_log.append_animated(message + "\n")

func refresh_fight_notes(
	active: bool,
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
) -> void:
	if not active:
		fight_notes.text = ""
		return

	fight_notes.clear()
	fight_notes.append_text(
		build_fight_notes(
			spell_runtime,
			player,
			prepared_enemy_spell,
			last_player_spell_name,
			last_player_profile,
			last_player_resonance,
			last_context_update,
			current_scores,
			last_defense_summary,
			progress_aspect_count,
			aspect_names
		)
	)

func build_fight_notes(
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

func _format_context_scores(current_scores: Array, progress_aspect_count: int) -> String:
	var parts: Array = []
	var limit: int = mini(progress_aspect_count, current_scores.size())
	for i in range(limit):
		var entry: AspectLibrary.ActualizedAspect = aspect_library.as_actualized(current_scores[i])
		parts.append(entry.name + " " + str(int(entry.score)))
	return ", ".join(parts)

func _format_context_update(update: Dictionary, aspect_names: PackedStringArray) -> String:
	var parts: Array = []
	for aspect_name in aspect_names:
		var delta: int = int(update.get(str(aspect_name), 0))
		if delta <= 0:
			continue
		parts.append("%s +%d" % [str(aspect_name), delta])
	if parts.is_empty():
		return "No aspect gained pressure."
	return ", ".join(parts)