extends Node
class_name Spell

signal spell_scored(sorted_scores: Array)

@export var line_edit_path: NodePath = "../LineEdit"
@export var ollama_client_path: NodePath = "OllamaClient"
@export var aspect_library_path: NodePath = "AspectLibrary"

@onready var spell_input: LineEdit = get_node_or_null(line_edit_path)
@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)
@onready var aspect_library: AspectLibrary = get_node_or_null(aspect_library_path)

var loading := true
var busy := false

func _ready() -> void:
	var initialized: bool = await aspect_library.initialize()
	if not initialized:
		push_error("AspectLibrary failed to initialize")
		return

	loading = false

func _on_spell_cast(text = null) -> void:
	if loading or busy:
		return

	var cast_text := _extract_cast_text(text)
	if cast_text.is_empty():
		return

	busy = true
	var sorted_scores: Array = await _compute_sorted_scores(cast_text)
	busy = false

	if sorted_scores.is_empty():
		return

	spell_scored.emit(sorted_scores)
	print(sorted_scores)

func _extract_cast_text(text: Variant) -> String:
	# Button presses call without args; text_submitted provides the string.
	if text == null:
		text = spell_input.text

	var cast_text := str(text).strip_edges()
	return cast_text

func _compute_sorted_scores(cast_text: String) -> Array:
	var result: Dictionary = await ollama_client.embed(cast_text)
	if not result.get("ok", false):
		push_error("Embedding request failed")
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		push_error("Empty embeddings")
		return []

	var spell_embedding: Array = embeddings[0]
	var sorted_scores: Array = aspect_library.score_embedding(spell_embedding)
	if sorted_scores.is_empty():
		push_error("No aspect scores were produced")
		return []

	return sorted_scores
