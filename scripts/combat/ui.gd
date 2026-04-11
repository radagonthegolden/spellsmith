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
    player_spell: SpellCasting.Spell,
	enemy_spell: SpellCasting.Spell,
    context: Dictionary,
    context_update: Dictionary,
	last_defense_summary: String,
) -> void:
	if not active:
		fight_notes.text = ""
		return

	fight_notes.clear()
	fight_notes.append_text(
		build_fight_notes(
            spell_runtime,
            player,
			enemy_spell,
            player_spell,
            context,
            context_update,
            last_defense_summary,
		)
	)

func build_fight_notes(
	spell_runtime: SpellCasting,
	player: Battler,
	enemy_spell: SpellCasting.Spell,
	player_spell: SpellCasting.Spell,
	context: Dictionary,
	context_update: Dictionary,
	last_defense_summary: String,
) -> String:
	var lines: Array[String] = [
		"[b]Fight Notes[/b]",
		"",
		"[b]Health[/b]",
		"You: %d/%d" % [player.health, player.max_health],
		"",
		"[b]Enemy Spell[/b]"
	]
	if enemy_spell == null:
		lines.append("None prepared.")
	else:
		lines.append(enemy_spell.name)
		lines.append("Pattern: " + spell_runtime.format_profile(enemy_spell.intensity_profile))

	lines.append("")
	lines.append("[b]Your Last Spell[/b]")
	if player_spell.name.is_empty():
		lines.append("None yet.")
	else:
		lines.append(player_spell.name)
		lines.append("Pattern: " + spell_runtime.format_profile(
            spell_runtime.filter_display_profile(
                player_spell.actualized, enemy_spell.actualized
            )
        ))
		lines.append("Resonance: " + str(snappedf(player_spell.resonance, 0.01)))
		lines.append("Context Update: " + _format_cast(context_update))

	lines.append("")
	lines.append("[b]Context[/b]")
	lines.append(_format_cast(context))
	lines.append("")
	lines.append("[b]Last Resolution[/b]")
	lines.append(last_defense_summary)
	return "\n".join(lines)

func _format_cast(aspects: Dictionary) -> String:
	var parts: Array = []
	for aspect in aspects:
		parts.append("%s: %d" % [aspect, aspects[aspect]])
	return ", ".join(parts)