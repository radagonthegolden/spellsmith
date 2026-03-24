extends Node
class_name AspectLibrary

@export var aspects_file_path: String = "res://data/aspects.json"
@export var ollama_client_path: NodePath = "../OllamaClient"
@export var length_penalty_reference_words: float = 4.0
@export var length_penalty_sqrt_scale: float = 1.0
@export var length_penalty_min_factor: float = 0.5
@export var softmax_temperature: float = 0.2

@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)

var aspect_vectors: Dictionary = {}
var aspect_names: PackedStringArray = PackedStringArray()
var is_ready: bool = false

func initialize() -> bool:
	is_ready = false
	aspect_vectors.clear()
	aspect_names = PackedStringArray()

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

	var sorted_names: Array = aspect_vectors.keys()
	sorted_names.sort()
	aspect_names = PackedStringArray(sorted_names)
	is_ready = true
	return true

func score_embedding(spell_embedding: Array, source_text: String = "") -> Array:
	if not is_ready or aspect_vectors.is_empty():
		return []

	var scores: Array = SemanticScorer.score_embedding_against_vectors(spell_embedding, aspect_vectors, softmax_temperature)
	if source_text.is_empty():
		return scores

	var penalty_factor: float = _get_length_penalty_factor(source_text)
	return SemanticScorer.scale_scores(scores, penalty_factor)

func get_aspect_names() -> PackedStringArray:
	return aspect_names

func _embed_aspect_phrases(aspect_name: String, phrases: Array) -> Array:
	var embeddings: Array = await ollama_client.embed_many(phrases, "Aspect embedding: " + aspect_name)
	if embeddings.is_empty():
		_fail_initialize("Empty embeddings for aspect: " + aspect_name)
		return []

	var weights: Array = []
	for phrase in phrases:
		weights.append(_get_length_penalty_factor(str(phrase)))

	var averaged: Array = SemanticScorer.weighted_average_embeddings(embeddings, weights)
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

func _get_length_penalty_factor(text: String) -> float:
	var normalized: String = text.strip_edges()
	if normalized.is_empty():
		return 1.0

	var word_count: int = normalized.split(" ", false).size()
	var adjusted_word_count: float = maxf(1.0, float(word_count) / length_penalty_reference_words)
	var penalty: float = length_penalty_sqrt_scale / sqrt(adjusted_word_count)
	return clampf(penalty, length_penalty_min_factor, 1.0)
