extends Node
class_name AspectLibrary

@export var aspects_file_path: String = "res://data/aspects.json"
@export var ollama_client_path: NodePath = "../OllamaClient"

@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)

var aspect_vectors: Dictionary = {}
var is_ready: bool = false

func initialize() -> bool:
	is_ready = false
	aspect_vectors.clear()

	var raw_aspect_data := _load_aspect_descriptions(aspects_file_path)
	if raw_aspect_data.is_empty():
		push_error("Empty aspect desc file")
		return false

	for aspect_name in raw_aspect_data.keys():
		var aspect_name_text := str(aspect_name)
		var phrases: Array = raw_aspect_data[aspect_name]
		var aspect_embedding: Array = await _embed_aspect_phrases(aspect_name_text, phrases)
		if aspect_embedding.is_empty():
			return false

		aspect_vectors[aspect_name_text] = aspect_embedding

	is_ready = true
	return true

func score_embedding(spell_embedding: Array) -> Array:
	if not is_ready or aspect_vectors.is_empty():
		return []

	return SemanticScorer.score_embedding_against_vectors(spell_embedding, aspect_vectors)

func _embed_aspect_phrases(aspect_name: String, phrases: Array) -> Array:
	var result: Dictionary = await ollama_client.embed(phrases)
	if not result.get("ok", false):
		_fail_initialize("Failed to embed aspect: " + aspect_name)
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		_fail_initialize("Empty embeddings for aspect: " + aspect_name)
		return []

	var averaged: Array = SemanticScorer.average_embeddings(embeddings)
	if averaged.is_empty():
		_fail_initialize("Invalid averaged embedding for aspect: " + aspect_name)
		return []

	return averaged

func _fail_initialize(message: String) -> bool:
	push_error(message)
	is_ready = false
	aspect_vectors.clear()
	return false

func _load_aspect_descriptions(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("Aspect file not found: " + file_path)
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open aspect file: " + file_path)
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(content)

	if parse_result != OK:
		push_error("Failed to parse JSON in aspect file: " + file_path)
		return {}

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		push_error("Aspect file must contain a JSON object at the root")
		return {}

	return data
