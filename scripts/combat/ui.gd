extends Node
class_name CombatUI


@onready var battle_log: RichTextLabel = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"
@onready var combat_notes_frame: PanelContainer = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame"
@onready var combat_notes_text: RichTextLabel = $"../../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame/FightNotesMargin/FightNotes"

class CombatNotes extends RefCounted:
	var player_health: int = 0
	var player_max_health: int = 0
	var enemy_name: String = ""
	var player_spell: SpellCasting.Spell = null
	var enemy_spell: SpellCasting.Spell = null
	var context: Dictionary = {}
	var context_update: Dictionary = {}
	var turn_summary: String = ""

	func _to_string() -> String:
		var lines: Array[String] = [
			"[b]Fight Notes[/b]",
			"",
			"[b]Health[/b]",
			"You: %d/%d" % [player_health, player_max_health],
			"",
			"[b]Enemy Spell[/b]",
		]

		if enemy_spell == null:
			lines.append("None prepared.")
		else:
			lines.append(enemy_spell.name)
			lines.append("Pattern: " + str(enemy_spell))

		lines.append("")
		lines.append("[b]Your Last Spell[/b]")
		if player_spell == null:
			lines.append("None yet.")
		else:
			lines.append(player_spell.name)
			lines.append("Pattern: " + str(player_spell))
			lines.append("Resonance: " + str(snappedf(player_spell.resonance, 0.01)))
			lines.append("Context Update: " + _format_cast(context_update))

		lines.append("")
		lines.append("[b]Context[/b]")
		lines.append(_format_cast(context))
		lines.append("")
		lines.append("[b]Last Resolution[/b]")
		lines.append(turn_summary if not turn_summary.is_empty() else "No resolution yet.")

		return "\n".join(lines)

	func _format_cast(aspects: Dictionary) -> String:
		if aspects == null or aspects.is_empty():
			return "None."

		var parts: Array = []
		for aspect in aspects:
			parts.append("%s: %d" % [aspect, aspects[aspect]])
		return ", ".join(parts)

func refresh_combat_notes(combat_notes: CombatNotes) -> void:
	combat_notes_text.clear()
	combat_notes_text.text = str(combat_notes)

func clear_fight_notes() -> void:
	combat_notes_text.text = ""

func set_ui_visible(value: bool) -> void:
	combat_notes_frame.visible = value

func log_line(message: String) -> void:
	print(message)
	battle_log.append_animated(message + "\n")
