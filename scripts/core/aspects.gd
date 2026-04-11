extends Node
class_name Aspects

class AspectDefinition extends RefCounted:
	var name: String = ""
	var phrases: Array = []
	var embedding: Array = []

class ActualizedAspect extends RefCounted:
	var name: String = ""
	var score: float = 0.0
	var intensity_rank: int = 0
	var intensity_label: String = "faint"

const INTENSITY_LOW_THRESHOLD: float = 0.30
const INTENSITY_MEDIUM_THRESHOLD: float = 0.60
const INTENSITY_HIGH_THRESHOLD: float = 0.90

@export var aspects_file_path: String = "res://data/aspects.json"
@export var ollama_client_path: NodePath = "../OllamaClient"
@export var vector_math_path: NodePath = "../VectorMath"
@export var length_penalty_reference_words: float = 4.0
@export var length_penalty_sqrt_scale: float = 1.0
@export var length_penalty_min_factor: float = 0.5
@export var softmax_temperature: float = 0.2

@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)
@onready var vector_math: VectorMath = get_node_or_null(vector_math_path)

var is_ready: bool = false
var DEFINITIONS : Dictionary = {}

func text_to_actualized(text: String, return_embedding: bool = false, factor: float = 1.0) -> Variant:
	assert(is_ready, "AspectLibrary is not initialized")
	var embedding: Array = await ollama_client.embed(text, "Scoring text: " + text)
	var penalty_factor: float = _get_length_penalty_factor(text)
	var scores := vector_math.get_sorted_scores(embedding, DEFINITIONS)
	var scaled_data := scores.map(func(number): return number * factor * penalty_factor) 
	var out: Array = []
	for raw_entry in scaled_data:
		var score_entry: Dictionary = raw_entry
		out.append(
			_make_actualized(score_entry["name"], score_entry["score"])
		)

	return {"actualized": out, "embedding": embedding} if return_embedding else out

func initialize() -> bool:
	is_ready = false
	DEFINITIONS = {}
	assert(ollama_client != null, "AspectLibrary missing OllamaClient dependency")

	var raw_aspect_data: Dictionary = _load_aspect_data(aspects_file_path)
	assert(not raw_aspect_data.is_empty(), "Empty aspect desc file")

	for aspect_name_variant in raw_aspect_data.keys():
		var aspect_name: String = str(aspect_name_variant)
		var phrases: Array = raw_aspect_data[aspect_name]
		var aspect_embedding: Array = await _embed_aspect(aspect_name, phrases)
		assert(not aspect_embedding.is_empty(), "Aspect embedding cannot be empty for aspect: " + aspect_name)
		DEFINITIONS[aspect_name] = _make_definition(aspect_name, phrases, aspect_embedding)

	is_ready = true
	
	return true

func scale_actualized(aspects: Array, factor: float) -> Array:
	var out: Array = []
	for entry in aspects:
		var actualized: ActualizedAspect = _make_actualized(str(entry["name"]), float(entry["score"]))
		out.append(_make_actualized(actualized.name, actualized.score * factor))
	return out

func get_aspect_names() -> PackedStringArray:
	var names := []
	for definition in DEFINITIONS.values():
		names.append(definition.name)
	return names

func _make_actualized(aspect_name: String, aspect_score: float) -> ActualizedAspect:
	var out: ActualizedAspect = ActualizedAspect.new()
	out.name = aspect_name
	out.score = aspect_score
	if aspect_score >= INTENSITY_HIGH_THRESHOLD:
		out.intensity_rank = 3
	elif aspect_score >= INTENSITY_MEDIUM_THRESHOLD:
		out.intensity_rank = 2
	elif aspect_score >= INTENSITY_LOW_THRESHOLD:
		out.intensity_rank = 1
	else:
		out.intensity_rank = 0
	if out.intensity_rank == 3:
		out.intensity_label = "high"
	elif out.intensity_rank == 2:
		out.intensity_label = "medium"
	elif out.intensity_rank == 1:
		out.intensity_label = "low"
	else:
		out.intensity_label = "faint"
	return out

func _load_aspect_data(file_path: String) -> Dictionary:
	assert(FileAccess.file_exists(file_path), "Aspect file not found: " + file_path)

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	assert(file != null, "Failed to open aspect file: " + file_path)

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	assert(json.parse(content) == OK, "Failed to parse JSON in aspect file: " + file_path)
	assert(typeof(json.data) == TYPE_DICTIONARY, "Aspect file must contain a JSON object at the root")

	return json.data

func _embed_aspect(aspect_name: String, phrases: Array) -> Array:
	var embeddings: Array = await ollama_client.embed_many(phrases, "Aspect embedding: " + aspect_name)
	assert(not embeddings.is_empty(), "Empty embeddings for aspect: " + aspect_name)

	var weights: Array = []
	for phrase in phrases:
		weights.append(_get_length_penalty_factor(str(phrase)))

	var averaged: Array = vector_math.weighted_average_embeddings(embeddings, weights)
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

func _make_definition(aspect_name: String, aspect_phrases: Array, aspect_embedding: Array) -> AspectDefinition:
	var out: AspectDefinition = AspectDefinition.new()
	out.name = aspect_name
	out.phrases = aspect_phrases
	out.embedding = aspect_embedding
	return out

func format_actualized(aspects: Array) -> String:
	var lines: Array = []
	for entry in aspects:
		lines.append("%s: %.2f (%s)" % [entry.name, entry.score, entry.intensity_label])
	return "\n".join(lines)
