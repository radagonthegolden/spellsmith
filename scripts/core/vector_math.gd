extends Node
class_name VectorMath

const NEGATIVE_SENTENCE_WEIGHT: float = 0.5

func get_scores(source_embedding: Array, target_definitions: Dictionary) -> Array:
	var scores: Array = []
	for key in target_definitions:
		var definition = target_definitions[key]
		var positive_score := _cosine_similarity(source_embedding, definition.embedding)
		var negative_score := 0.0 if definition.negative_embedding.is_empty() else _cosine_similarity(source_embedding, definition.negative_embedding)
		scores.append({
			"name": key,
			"score": positive_score - negative_score * NEGATIVE_SENTENCE_WEIGHT
		})
	return scores

func get_sorted_scores(source_embedding: Array, target_definitions: Dictionary, temperature: float = 0.0) -> Array:
	var scores: Array = get_scores(source_embedding, target_definitions)
	if temperature > 0.0:
		scores = _softmax(scores, temperature)
	scores.sort_custom(func(a, b): return a["score"] > b["score"])
	return scores

func average_embeddings(vectors: Array) -> Array:
	return weighted_average_embeddings(vectors, vectors.map(func(_entry): return 1.0))

func weighted_average_embeddings(vectors: Array, weights: Array) -> Array:
	var dim: int = vectors[0].size()
	var out: Array = []
	out.resize(dim)
	out.fill(0.0)

	var total_weight: float = 0.0
	for i in range(vectors.size()):
		var vec: Array = vectors[i]
		var weight: float = float(weights[i])
		total_weight += weight
		for j in range(dim):
			out[j] += float(vec[j]) * weight

	for i in range(dim):
		out[i] /= total_weight
	return out

func resonance(embedding: Array, descriptor: Array, min_resonance: float, max_resonance: float) -> float:
	var raw_resonance: float = _cosine_similarity(embedding, descriptor)
	return lerpf(min_resonance, max_resonance, clampf(raw_resonance, 0.0, 1.0))

# Private helper functions

func _cosine_similarity(a: Array, b: Array) -> float:
	var dot: float = 0.0
	var norm_a: float = 0.0
	var norm_b: float = 0.0

	for i in range(a.size()):
		var av: float = float(a[i])
		var bv: float = float(b[i])
		dot += av * bv
		norm_a += av * av
		norm_b += bv * bv

	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0
	return dot / (sqrt(norm_a) * sqrt(norm_b))

func _softmax(scores: Array, temperature: float) -> Array:
	var max_score := -INF
	for entry in scores:
		max_score = max(max_score, float(entry["score"]))

	var exps: Array = []
	var total := 0.0
	for entry in scores:
		var value := exp((float(entry["score"]) - max_score) / temperature)
		exps.append(value)
		total += value

	var normalized: Array = []
	for i in range(scores.size()):
		normalized.append({
			"name": scores[i]["name"],
			"score": exps[i] / total
		})
	return normalized
