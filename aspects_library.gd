extends Node
class_name AspectLibrary

@export var aspects_file_path: String = "res://data/aspects.json"
@export var ollama_client_path: NodePath = "../OllamaClient"

@onready var ollama_client: OllamaClient = get_node_or_null(ollama_client_path)

var aspect_vectors: Dictionary = {}
var is_ready: bool = false

func initialize() -> void:
	is_ready = false
	aspect_vectors.clear()

	if ollama_client == null:
		push_error("OllamaClient not found at path: " + str(ollama_client_path))
		return

	var raw_aspect_data := _load_aspect_descriptions(aspects_file_path)
	if raw_aspect_data.is_empty():
		return

	for aspect_name in raw_aspect_data.keys():
		var phrases = raw_aspect_data[aspect_name]

		if typeof(phrases) != TYPE_ARRAY or phrases.is_empty():
			continue

		var result: Dictionary = await ollama_client.embed(phrases)
		if not result.get("ok", false):
			continue

		var embeddings: Array = result.get("embeddings", [])
		if embeddings.is_empty():
			continue

		aspect_vectors[aspect_name] = _average_embeddings(embeddings)

	is_ready = not aspect_vectors.is_empty()

func score_embedding(spell_embedding: Array) -> Dictionary:
	var scores := {}

	for aspect_name in aspect_vectors.keys():
		var aspect_embedding: Array = aspect_vectors[aspect_name]
		scores[aspect_name] = _cosine_similarity(spell_embedding, aspect_embedding)

	return scores

func sort_scores_desc(scores: Dictionary) -> Array:
	var items := []

	for key in scores.keys():
		items.append({
			"name": key,
			"score": scores[key]
		})

	items.sort_custom(func(a, b): return a["score"] > b["score"])
	return items

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

	for i in range(dim):
		out.append(0.0)

	for vec in vectors:
		for i in range(dim):
			out[i] += float(vec[i])

	for i in range(dim):
		out[i] /= vectors.size()

	return out

func _cosine_similarity(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0

	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0

	for i in range(a.size()):
		var av = float(a[i])
		var bv = float(b[i])
		dot += av * bv
		norm_a += av * av
		norm_b += bv * bv

	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0

	return dot / (sqrt(norm_a) * sqrt(norm_b))
