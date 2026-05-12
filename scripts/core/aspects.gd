extends Node
class_name Aspects

signal startup_finished(success: bool)

class AspectDefinition extends RefCounted:
	var name: String = ""
	var positive_phrases: Array = []
	var negative_phrases: Array = []
	var embedding: Array = []
	var negative_embedding: Array = []

	func _init(
		aspect_name: String = "",
		aspect_positive_phrases: Array = [],
		aspect_embedding: Array = [],
		aspect_negative_phrases: Array = [],
		aspect_negative_embedding: Array = []
	) -> void:
		name = aspect_name
		positive_phrases = aspect_positive_phrases
		embedding = aspect_embedding
		negative_phrases = aspect_negative_phrases
		negative_embedding = aspect_negative_embedding

class ActualizedAspect extends RefCounted:
	var name: String = ""
	var score: float = 0.0
	var intensity_rank: int = 0
	var intensity_label: String = "faint"

	func _init(
		aspect_name: String = "",
		aspect_score: float = 0.0,
		low_threshold: float = 0.10,
		medium_threshold: float = 0.25,
		high_threshold: float = 0.35
	) -> void:
		name = aspect_name
		score = aspect_score

		if aspect_score >= high_threshold:
			intensity_rank = 3
		elif aspect_score >= medium_threshold:
			intensity_rank = 2
		elif aspect_score >= low_threshold:
			intensity_rank = 1
		else:
			intensity_rank = 0

		if intensity_rank == 3:
			intensity_label = "high"
		elif intensity_rank == 2:
			intensity_label = "medium"
		elif intensity_rank == 1:
			intensity_label = "low"
		else:
			intensity_label = "faint"

	func _to_string() -> String:
		return name + " " + str(intensity_rank) + "d"

	func roll(dice_sides: int = 6) -> Dictionary:
		var results: Array = []
		for _i in range(intensity_rank):
			results.append(randi_range(1, dice_sides))
		return {
			"results": results,
			"total": results.reduce(func(accum, number): return accum + number, 0)
		}

const INTENSITY_LOW_THRESHOLD: float = 0.15
const INTENSITY_MEDIUM_THRESHOLD: float = 0.25
const INTENSITY_HIGH_THRESHOLD: float = 0.35

@export var aspects_file_path: String = "res://data/aspects.json"

@export var DEFAULT_PENALTY_LENGTH: int = 4
@export var DEFAULT_PENALTY_FACTOR: float = 0.7
@export var DEFAULT_PENALTY_FLOOR: float = 0.5
@export var SOFTMAX_TEMPERATURE: float = 0.3

@onready var ollama_client: OllamaClient = $"../OllamaClient"
@onready var vector_math: VectorMath = $"../VectorMath"

var is_ready: bool = false
var DEFINITIONS : Dictionary = {}

func embedding_to_profile(embedding: Array, factor: float = 1.0, keep_top: bool = false) -> Array:
	var scores := vector_math.get_sorted_scores(embedding, DEFINITIONS, SOFTMAX_TEMPERATURE)

	scores = [scores[0]] if keep_top else scores

	var scaled_data := scores.map(func(entry): return {
		"name": entry["name"],
		"score": entry["score"] * factor
	})
	var profile: Array = []
	for entry in scaled_data:
		var actualized := ActualizedAspect.new(
			entry["name"],
			entry["score"],
			INTENSITY_LOW_THRESHOLD,
			INTENSITY_MEDIUM_THRESHOLD,
			INTENSITY_HIGH_THRESHOLD
		)
		if actualized.intensity_rank > 0:
			profile.append(actualized)
	return profile

func get_raw_scores(embedding: Array) -> Array:
	return vector_math.get_sorted_scores(embedding, DEFINITIONS, SOFTMAX_TEMPERATURE)

func get_aspect_names() -> PackedStringArray:
	var names := []
	for definition in DEFINITIONS.values():
		names.append(definition.name)
	return names

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

func _embed_aspect(aspect_name: String, phrases: Array, polarity: String) -> Array:
	if phrases.is_empty():
		return []

	var embeddings: Array = await ollama_client.embed(
		phrases,
		"Aspect %s embedding: %s" % [polarity, aspect_name]
	)
	assert(not embeddings.is_empty(), "Empty embeddings for aspect: " + aspect_name)

	var weights: Array = []
	for phrase in phrases:
		#weights.append(get_length_penalty_factor(str(phrase)))
		weights.append(1.0)

	var averaged: Array = vector_math.weighted_average_embeddings(embeddings, weights)
	assert(not averaged.is_empty(), "Invalid averaged embedding for aspect: " + aspect_name)

	return averaged

func get_length_penalty_factor(text: String) -> float:
	var normalized: String = text.strip_edges()
	if normalized.is_empty():
		return 1.0

	var length := normalized.split(" ").size()

	if length <= DEFAULT_PENALTY_LENGTH:
		return 1.0

	var penalization_factor := 1.0
	for i in range(length - DEFAULT_PENALTY_LENGTH):
		penalization_factor *= DEFAULT_PENALTY_FACTOR

	return max(penalization_factor, DEFAULT_PENALTY_FLOOR)

func _on_ollama_client_startup_finished(ok: bool) -> void:
	assert(ok, "OllamaClient failed to start, which is required for AspectLibrary")
	is_ready = false
	DEFINITIONS = {}

	var raw_aspect_data: Dictionary = _load_aspect_data(aspects_file_path)
	assert(not raw_aspect_data.is_empty(), "Empty aspect desc file")

	for aspect_name_variant in raw_aspect_data.keys():
		var aspect_name: String = str(aspect_name_variant)
		var aspect_data: Dictionary = raw_aspect_data[aspect_name]
		var positive_phrases: Array = aspect_data.get("positive", [])
		var negative_phrases: Array = aspect_data.get("negative", [])
		var aspect_embedding: Array = await _embed_aspect(aspect_name, positive_phrases, "positive")
		var negative_embedding: Array = await _embed_aspect(aspect_name, negative_phrases, "negative")
		assert(not aspect_embedding.is_empty(), "Aspect embedding cannot be empty for aspect: " + aspect_name)
		DEFINITIONS[aspect_name] = AspectDefinition.new(
			aspect_name,
			positive_phrases,
			aspect_embedding,
			negative_phrases,
			negative_embedding
		)

	is_ready = true
	startup_finished.emit(true)
