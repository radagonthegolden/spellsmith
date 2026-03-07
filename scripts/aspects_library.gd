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

	var aspect_mean := _compute_aspect_mean(aspect_vectors)
	if aspect_mean.is_empty():
		return []

	var centered_spell := _subtract_vector(spell_embedding, aspect_mean)
	var scores := {}

	for aspect_name in aspect_vectors.keys():
		var aspect_embedding: Array = aspect_vectors[aspect_name]
		var centered_aspect := _subtract_vector(aspect_embedding, aspect_mean)
		scores[aspect_name] = _cosine_similarity(centered_spell, centered_aspect)

	var soft_maxxed_scores: Dictionary = _softmax_scores(scores)
	return _sort_scores(soft_maxxed_scores)

func _sort_scores(scores: Dictionary) -> Array:
	var items := []

	for key in scores.keys():
		items.append({
			"name": key,
			"score": scores[key]
		})

	items.sort_custom(func(a, b): return a["score"] > b["score"])
	return items

func _embed_aspect_phrases(aspect_name: String, phrases: Array) -> Array:
	var result: Dictionary = await ollama_client.embed(phrases)
	if not result.get("ok", false):
		_fail_initialize("Failed to embed aspect: " + aspect_name)
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		_fail_initialize("Empty embeddings for aspect: " + aspect_name)
		return []

	var averaged: Array = _average_embeddings(embeddings)
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

func _average_embeddings(vectors: Array) -> Array:
	if vectors.is_empty():
		return []

	var dim = vectors[0].size()
	var out := []

	out.resize(dim)
	out.fill(0.0)

	for vec in vectors:
		for i in range(dim):
			out[i] += float(vec[i])

	var inv_count := 1.0 / float(vectors.size())
	for i in range(dim):
		out[i] *= inv_count

	return out

func _cosine_similarity(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0

	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0

	for i in range(a.size()):
		var av := float(a[i])
		var bv := float(b[i])
		dot += av * bv
		norm_a += av * av
		norm_b += bv * bv

	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0

	return dot / (sqrt(norm_a) * sqrt(norm_b))

func _softmax_scores(scores: Dictionary) -> Dictionary:
	if scores.is_empty():
		return {}

	var max_score := -INF
	for value in scores.values():
		max_score = max(max_score, float(value))

	var exps := {}
	var total := 0.0

	for key in scores.keys():
		var e := exp(float(scores[key]) - max_score)
		exps[key] = e
		total += e

	if total <= 0.0:
		return exps

	for key in exps.keys():
		exps[key] /= total

	return exps

func _compute_aspect_mean(aspect_vectors: Dictionary) -> Array:
	if aspect_vectors.is_empty():
		return []

	var first_key = aspect_vectors.keys()[0]
	var dim = aspect_vectors[first_key].size()

	var mean := []
	mean.resize(dim)
	mean.fill(0.0)

	var count := 0

	for vec in aspect_vectors.values():
		for i in range(dim):
			mean[i] += float(vec[i])
		count += 1

	if count > 0:
		for i in range(dim):
			mean[i] /= float(count)

	return mean

func _subtract_vector(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return []

	var out := []
	out.resize(a.size())

	for i in range(a.size()):
		out[i] = float(a[i]) - float(b[i])

	return out
