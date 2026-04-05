extends Node
class_name SceneDirector

@export var combat_enemy_name: String = "Pedantic Admitter"

# Story mode disabled for now - scene director focuses on combat startup
# To re-enable story mode, add back: scenes_file_path, start_scene_id, exit_match_threshold
var _scenes_file_path: String = "res://data/scenes.json"

const DEFAULT_PROMPT: String = "Write the next line..."

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var manuscript = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"

@onready var combat_manager: CombatManager = $"../CombatManager"
@onready var spell: Spell = $"../spell"
@onready var ollama_client: OllamaClient = $"../spell/OllamaClient"

func _ready() -> void:
	combat_manager.combat_finished.connect(_on_combat_finished)
	await ollama_client.ensure_started()
	if spell.loading:
		await spell.initialization_finished
	manuscript.clear_and_reset()
	manuscript.append_animated("The duel begins...\n")
	spell_input.grab_focus()
	await combat_manager.start_battle(combat_enemy_name)

func _on_player_submitted(text = null) -> void:
	var submitted_text: String = _extract_text(text)
	if submitted_text.is_empty():
		return

	# Combat is always active at startup
	if combat_manager.active:
		await spell._on_spell_cast(submitted_text)

func _on_combat_finished(player_won: bool) -> void:
	# Combat finished - can add post-battle logic here
	pass

func _extract_text(text: Variant) -> String:
	if text == null:
		text = spell_input.text

	return str(text).strip_edges()
