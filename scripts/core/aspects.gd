extends Node
class_name Aspects

signal startup_finished(success: bool)

class AspectDefinition extends RefCounted:
	var name: String = ""
	var phrases: Array = []
	var embedding: Array = []

class ActualizedAspect extends RefCounted:
	var name: String = ""
	var score: float = 0.0
	var intensity_rank: int = 0
	var intensity_label: String = "faint"

const INTENSITY_LOW_THRESHOLD: float = 0.10
const INTENSITY_MEDIUM_THRESHOLD: float = 0.25
const INTENSITY_HIGH_THRESHOLD: float = 0.35

const DICE_SIDES: int = 6

@export var aspects_file_path: String = "res://data/aspects.json"

@export var DEFAULT_PENALTY_LENGTH: int = 4
@export var DEFAULT_PENALTY_FACTOR: float = 0.7
@export var DEFAULT_PENALTY_FLOOR: float = 0.5

@export var softmax_temperature: float = 0.2

@onready var ollama_client: OllamaClient = $"../OllamaClient"
@onready var vector_math: VectorMath = $"../VectorMath"

var is_ready: bool = false
var DEFINITIONS : Dictionary = {}

func embedding_to_profile(embedding: Array, factor: float = 1.0, keep_top: bool = false) -> Array:
	var scores := vector_math.get_sorted_scores(embedding, DEFINITIONS)

	scores = [scores[0]] if keep_top else scores

	var scaled_data := scores.map(func(entry): return {
		"name": entry["name"],
		"score": entry["score"] * factor
	})
	var profile: Array = []
	for entry in scaled_data:
		var actualized := _make_actualized(entry["name"], entry["score"])
		if actualized.intensity_rank > 0:
			profile.append(actualized)
	return profile

func get_raw_scores(embedding: Array) -> Array:
	return vector_math.get_sorted_scores(embedding, DEFINITIONS)

func get_aspect_names() -> PackedStringArray:
	var names := []
	for definition in DEFINITIONS.values():
		names.append(definition.name)
	return names

func profile_to_string(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		parts.append(entry.name + " " + str(entry.intensity_rank) + "d")
	return ", ".join(parts)

func profile_to_rolls(profile: Array) -> Dictionary:
	var out := {}
	for definition in DEFINITIONS.values():
		out[definition.name] = {"results": [], "total": 0}

	for aspect in profile:
		var results: Array = []
		for _i in range(aspect.intensity_rank):
			results.append(_roll_dice())
		out[aspect.name] = {
			"results": results,
			"total": results.reduce(func(accum, number): return accum + number, 0)
		}

	for aspect_name in out.keys():
		if out[aspect_name]["total"] == 0:
			out.erase(aspect_name)

	return out

func rolls_to_string(rolls: Dictionary) -> String:
	var parts: Array = []
	for aspect_name in rolls.keys().filter(func(name): return rolls[name]["results"].size() > 0):
		parts.append(
			"%s: %dd -> %s" % [
				aspect_name,
				rolls[aspect_name]["results"].size(),
				"+".join(rolls[aspect_name]["results"].map(func(num): return str(num)))
			]
		)
	return ", ".join(parts)

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
	var embeddings: Array = await ollama_client.embed(phrases, "Aspect embedding: " + aspect_name)
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

func _make_definition(aspect_name: String, aspect_phrases: Array, aspect_embedding: Array) -> AspectDefinition:
	var out: AspectDefinition = AspectDefinition.new()
	out.name = aspect_name
	out.phrases = aspect_phrases
	out.embedding = aspect_embedding
	return out

func _on_ollama_client_startup_finished(ok: bool) -> void:
	assert(ok, "OllamaClient failed to start, which is required for AspectLibrary")
	is_ready = false
	DEFINITIONS = {}

	var raw_aspect_data: Dictionary = _load_aspect_data(aspects_file_path)
	assert(not raw_aspect_data.is_empty(), "Empty aspect desc file")

	for aspect_name_variant in raw_aspect_data.keys():
		var aspect_name: String = str(aspect_name_variant)
		var phrases: Array = raw_aspect_data[aspect_name]
		var aspect_embedding: Array = await _embed_aspect(aspect_name, phrases)
		assert(not aspect_embedding.is_empty(), "Aspect embedding cannot be empty for aspect: " + aspect_name)
		DEFINITIONS[aspect_name] = _make_definition(aspect_name, phrases, aspect_embedding)

	is_ready = true
	startup_finished.emit(true)

func _roll_dice(dice_count: int = 1) -> int:
	var total := 0
	for _i in range(dice_count):
		total += randi_range(1, DICE_SIDES)
	return total
