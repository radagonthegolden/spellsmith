extends Node
class_name AspectLibrary

class AspectDefinition extends RefCounted:
	var name: String = ""
	var phrases: Array = []
	var embedding: Array = []

class ActualizedAspect extends RefCounted:
	var name: String = ""
	var score: float = 0.0
	var intensity_rank: int = 0
	var intensity_label: String = "faint"

@export var aspects_file_path: String = "res://data/aspects.json"
@export var ollama_client_path: NodePath = "../OllamaClient"
@export var length_penalty_reference_words: float = 4.0
@export var length_penalty_sqrt_scale: float = 1.0
@export var length_penalty_min_factor: float = 0.5
@export var softmax_temperature: float = 0.2

@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)

var aspects: Array = []
var is_ready: bool = false

func _load_aspect_descriptions(file_path: String) -> Dictionary:
	assert(FileAccess.file_exists(file_path), "Aspect file not found: " + file_path)

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	assert(file != null, "Failed to open aspect file: " + file_path)

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	assert(json.parse(content) == OK, "Failed to parse JSON in aspect file: " + file_path)

	var data: Dictionary = json.data
	assert(typeof(data) == TYPE_DICTIONARY, "Aspect file must contain a JSON object at the root")

	return data

func initialize() -> bool:
	is_ready = false
	aspects.clear()

	var raw_aspect_data: Dictionary = _load_aspect_descriptions(aspects_file_path)
	assert(not raw_aspect_data.is_empty(), "Empty aspect desc file")

	for aspect_name in raw_aspect_data.keys():
		var aspect_embedding: Array = await _embed_aspect_phrases(aspect_name, raw_aspect_data[aspect_name])
		assert(not aspect_embedding.is_empty(), "Aspect embedding cannot be empty for aspect: " + aspect_name)
		aspects.append(make_definition(aspect_name, raw_aspect_data[aspect_name], aspect_embedding))

	aspects.sort_custom(func(a: AspectDefinition, b: AspectDefinition): return a.name < b.name)
	is_ready = true
	return true

func score_embedding(spell_embedding: Array, source_text: String = "") -> Array:
	assert(is_ready, "AspectLibrary is not initialized")
	assert(not aspects.is_empty(), "AspectLibrary has no aspect definitions")
	assert(not spell_embedding.is_empty(), "Spell embedding cannot be empty")

	var scores: Array = _to_actualized_aspects(SemanticScorer.score_embedding_against_vectors(spell_embedding, _definition_vectors(), softmax_temperature))
	if source_text.is_empty():
		return scores

	var penalty_factor: float = _get_length_penalty_factor(source_text)
	return scale_scores(scores, penalty_factor)

func scale_scores(scores: Array, factor: float) -> Array:
	var out: Array = []
	for entry in scores:
		out.append(actualized_scaled(as_actualized(entry), factor))
	return out

static func as_actualized(entry: Variant) -> ActualizedAspect:
	return actualized_from_variant(entry)

static func as_actualized_array(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(actualized_from_variant(entry))
	return out

func get_aspect_names() -> PackedStringArray:
	var names: Array = []
	for definition in aspects:
		var aspect_definition: AspectDefinition = definition
		names.append(aspect_definition.name)
	return PackedStringArray(names)

func _embed_aspect_phrases(aspect_name: String, phrases: Array) -> Array:
	var embeddings: Array = await ollama_client.embed_many(phrases, "Aspect embedding: " + aspect_name)
	assert(not embeddings.is_empty(), "Empty embeddings for aspect: " + aspect_name)

	var weights: Array = []
	for phrase in phrases:
		weights.append(_get_length_penalty_factor(str(phrase)))

	var averaged: Array = VectorMath.weighted_average_embeddings(embeddings, weights)
	assert(not averaged.is_empty(), "Invalid averaged embedding for aspect: " + aspect_name)

	return averaged

func _get_length_penalty_factor(text: String) -> float:
	var normalized: String = text.strip_edges()
	if normalized.is_empty():
		return 1.0

	var word_count: int = normalized.split(" ", false).size()
	var adjusted_word_count: float = maxf(1.0, float(word_count) / length_penalty_reference_words)
	var penalty: float = length_penalty_sqrt_scale / sqrt(adjusted_word_count)
	return clampf(penalty, length_penalty_min_factor, 1.0)

func _to_actualized_aspects(raw_scores: Array) -> Array:
	var out: Array = []
	for entry in raw_scores:
		out.append(actualized_from_variant(entry))
	return out

func _definition_vectors() -> Dictionary:
	var vectors: Dictionary = {}
	for definition in aspects:
		var aspect_definition: AspectDefinition = definition
		vectors[aspect_definition.name] = aspect_definition.embedding
	return vectors

static func make_definition(aspect_name: String, aspect_phrases: Array, aspect_embedding: Array) -> AspectDefinition:
	var out: AspectDefinition = AspectDefinition.new()
	out.name = aspect_name
	out.phrases = aspect_phrases
	out.embedding = aspect_embedding
	return out

static func make_actualized(aspect_name: String, aspect_score: float) -> ActualizedAspect:
	var out: ActualizedAspect = ActualizedAspect.new()
	out.name = aspect_name
	out.score = aspect_score
	out.intensity_rank = SemanticScorer.score_to_intensity_rank(aspect_score)
	out.intensity_label = SemanticScorer.score_to_intensity_label(aspect_score)
	return out

static func actualized_from_variant(entry: Variant) -> ActualizedAspect:
	if entry is ActualizedAspect:
		return entry
	assert(entry is Dictionary, "Aspect entry must be ActualizedAspect or Dictionary")
	var dict_entry: Dictionary = entry
	assert(dict_entry.has("name"), "Aspect dictionary entry is missing name")
	assert(dict_entry.has("score"), "Aspect dictionary entry is missing score")
	return make_actualized(str(dict_entry["name"]), float(dict_entry["score"]))

static func actualized_scaled(entry: ActualizedAspect, factor: float) -> ActualizedAspect:
	return make_actualized(entry.name, entry.score * factor)

static func actualized_to_dictionary(entry: ActualizedAspect) -> Dictionary:
	return {
		"name": entry.name,
		"score": entry.score,
		"intensity_rank": entry.intensity_rank,
		"intensity_label": entry.intensity_label
	}
