extends Node
class_name SceneDirector

@export var scenes_file_path: String = "res://data/scenes.json"
@export var start_scene_id: String = "antechamber"
@export var exit_match_threshold: float = 0.28
@export var start_in_combat: bool = true
@export var combat_start_scene_id: String = "threshold"
@export var combat_start_enemy_name: String = "Bathhouse Admitter"

const DEFAULT_PROMPT: String = "Write the next line..."

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var manuscript = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"

@onready var combat_manager: CombatManager = $"../CombatManager"
@onready var spell: Spell = $"../spell"
@onready var ollama_client: OllamaClient = $"../spell/OllamaClient"

var scenes_by_id: Dictionary = {}
var current_scene_id: String = ""
var pending_victory_scene_id: String = ""
var pending_defeat_scene_id: String = ""

func _ready() -> void:
	combat_manager.combat_finished.connect(_on_combat_finished)
	_load_scenes()
	await ollama_client.ensure_started()
	if spell.loading:
		await spell.initialization_finished
	await _initialize_intent_embeddings()
	manuscript.clear_and_reset()
	if start_in_combat:
		_show_scene(combat_start_scene_id)
		_initialize_combat_start(combat_start_scene_id, combat_start_enemy_name)
		await combat_manager.start_battle(combat_start_enemy_name)
	else:
		_show_scene(start_scene_id)
	spell_input.grab_focus()

func _on_player_submitted(text = null) -> void:
	var submitted_text: String = _extract_text(text)
	if submitted_text.is_empty():
		return

	if combat_manager.active:
		await spell._on_spell_cast(submitted_text)
		return

	spell_input.text = ""
	await _resolve_scene_input(submitted_text)

func _resolve_scene_input(submitted_text: String) -> void:
	var player_embedding: Array = await ollama_client.embed_one(submitted_text, "Scene input embedding")
	if player_embedding.is_empty():
		return

	var scene: Dictionary = scenes_by_id[current_scene_id]
	_append_paragraph("You write: \"" + submitted_text + "\"")

	var scored_intents: Array = SemanticScorer.rank_embedding_against_vectors(player_embedding, scene["_intent_vectors"])
	if scored_intents.is_empty():
		push_error("Scene has no initialized intents: " + current_scene_id)
		_append_paragraph(str(scene["default_reply"]))
		return

	var best_intent_name: String = str(scored_intents[0]["name"])
	var best_intent_score: float = float(scored_intents[0]["score"])

	if best_intent_score < exit_match_threshold:
		_append_paragraph(str(scene["default_reply"]))
		return

	var best_intent: Dictionary = scene["_intent_lookup"][best_intent_name]
	_append_paragraph(str(best_intent["response"]))

	if bool(best_intent.get("start_combat", false)):
		pending_victory_scene_id = str(best_intent.get("victory_scene", ""))
		pending_defeat_scene_id = str(best_intent.get("defeat_scene", ""))
		await combat_manager.start_battle(str(best_intent.get("enemy_name", "Enemy")))
		return

	var next_scene_id: String = str(best_intent.get("next_scene", current_scene_id))
	_show_scene(next_scene_id)

func _on_combat_finished(player_won: bool) -> void:
	var next_scene_id: String = pending_victory_scene_id if player_won else pending_defeat_scene_id
	if next_scene_id.is_empty():
		return

	pending_victory_scene_id = ""
	pending_defeat_scene_id = ""
	_show_scene(next_scene_id)

func _show_scene(scene_id: String) -> void:
	current_scene_id = scene_id
	var scene: Dictionary = scenes_by_id[scene_id]
	spell_input.placeholder_text = str(scene.get("prompt", DEFAULT_PROMPT))
	_append_paragraph(str(scene["prose"]))

func _initialize_combat_start(scene_id: String, enemy_name: String) -> void:
	var scene: Dictionary = scenes_by_id[scene_id]
	for intent in scene["intents"]:
		if bool(intent.get("start_combat", false)) and str(intent.get("enemy_name", "")) == enemy_name:
			pending_victory_scene_id = str(intent.get("victory_scene", ""))
			pending_defeat_scene_id = str(intent.get("defeat_scene", ""))
			_append_paragraph(str(intent["response"]))
			return

func _append_paragraph(text: String) -> void:
	manuscript.append_animated(text + "\n\n")

func _load_scenes() -> void:
	var file := FileAccess.open(scenes_file_path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	json.parse(content)

	var scenes: Array = json.data
	for scene_entry in scenes:
		var scene: Dictionary = scene_entry
		scenes_by_id[str(scene["id"])] = scene

func _initialize_intent_embeddings() -> void:
	for scene_id in scenes_by_id.keys():
		var scene: Dictionary = scenes_by_id[scene_id]
		var intents: Array = scene["intents"]
		var intent_vectors: Dictionary = {}
		var intent_lookup: Dictionary = {}
		for intent in intents:
			var phrases: Array = intent["phrases"]
			var embeddings: Array = await ollama_client.embed_many(phrases, "Intent embedding")
			if embeddings.is_empty():
				continue
			var intent_name: String = str(intent.get("id", intent["response"]))
			intent_vectors[intent_name] = SemanticScorer.average_embeddings(embeddings)
			intent_lookup[intent_name] = intent

		scene["_intent_vectors"] = intent_vectors
		scene["_intent_lookup"] = intent_lookup

func _extract_text(text: Variant) -> String:
	if text == null:
		text = spell_input.text

	return str(text).strip_edges()
