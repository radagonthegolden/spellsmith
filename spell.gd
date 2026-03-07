extends Node
class_name Spell

signal spell_scored(scores: Dictionary, sorted_scores: Array)

@export var line_edit_path: NodePath = "../LineEdit"
@export var ollama_client_path: NodePath = "OllamaClient"
@export var aspect_library_path: NodePath = "AspectLibrary"

@onready var spell_input: LineEdit = get_node_or_null(line_edit_path)
@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)
@onready var aspect_library: AspectLibrary = get_node_or_null(aspect_library_path)

var loading := true
var busy := false

func _ready() -> void:
	if spell_input == null:
		push_error("LineEdit not found at path: " + str(line_edit_path))
		return

	if ollama_client == null:
		push_error("OllamaClient not found at path: " + str(ollama_client_path))
		return

	if aspect_library == null:
		push_error("AspectLibrary not found at path: " + str(aspect_library_path))
		return

	await aspect_library.initialize()
	loading = false

func _on_button_pressed() -> void:
	if loading or busy or spell_input == null:
		return

	var text := spell_input.text.strip_edges()
	if text.is_empty():
		return

	busy = true

	var result: Dictionary = await ollama_client.embed(text)
	if not result.get("ok", false):
		busy = false
		return

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		busy = false
		return

	var spell_embedding = embeddings[0]
	var scores = aspect_library.score_embedding(spell_embedding)
	var sorted_scores = aspect_library.sort_scores_desc(scores)

	busy = false
	spell_scored.emit(scores, sorted_scores)

	print(sorted_scores)
