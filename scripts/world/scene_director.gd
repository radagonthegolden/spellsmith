extends Node
class_name SceneDirector

@export var combat_enemy_id: String = "pedantic_admitter"

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var manuscript = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"

@onready var combat_manager: CombatManager = $"../CombatManager"
@onready var spell_runtime: SpellCasting = $"../SpellCasting"
@onready var ollama_client: OllamaClient = $"../SpellCasting/OllamaClient"

func _ready() -> void:
	assert(spell_input != null, "SceneDirector missing spell input LineEdit")
	assert(manuscript != null, "SceneDirector missing manuscript writer")
	assert(combat_manager != null, "SceneDirector missing CombatManager")
	assert(spell_runtime != null, "SceneDirector missing SpellCasting node")
	assert(ollama_client != null, "SceneDirector missing OllamaClient")

	combat_manager.combat_finished.connect(_on_combat_finished)

	var startup_ok: bool = await ollama_client.ensure_started()
	assert(startup_ok, "Ollama failed to start before combat start")
	if not spell_runtime.aspect_library.is_ready:
		startup_ok = await spell_runtime.startup_finished
		assert(startup_ok, "Spell initialization failed before combat start")

	manuscript.clear_and_reset()
	spell_input.grab_focus()
	await combat_manager.start_battle(combat_enemy_id)

func _on_player_submitted(text: Variant = null) -> void:
	var submitted_text: String = _extract_text(text)
	if submitted_text.is_empty() or not combat_manager.active:
		return

	spell_input.clear()
	await combat_manager.submit_spell(submitted_text)

func _on_combat_finished(_player_won: bool) -> void:
	pass

func _extract_text(text: Variant) -> String:
	if text == null:
		text = spell_input.text
	return str(text).strip_edges()
