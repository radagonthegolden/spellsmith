extends Node
class_name VectorMath

func get_scores(source_embedding: Array, target_definitions: Dictionary) -> Array:
	var target_vectors: Dictionary = {}
	for key in target_definitions:
		target_vectors[key] = target_definitions[key].embedding
	return _centered_scores(source_embedding, target_vectors)

func get_sorted_scores(source_embedding: Array, target_definitions: Dictionary) -> Array:
	var scores: Array = get_scores(source_embedding, target_definitions)
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

func _mean(vectors: Dictionary) -> Array:
	var first_vec: Array = vectors.values()[0]
	var dim: int = first_vec.size()
	var mean: Array = []
	mean.resize(dim)
	mean.fill(0.0)

	var count: int = 0
	for vec in vectors.values():
		for i in range(dim):
			mean[i] += float(vec[i])
		count += 1

	for i in range(dim):
		mean[i] /= float(count)
	return mean

func _centered_scores(source_embedding: Array, target_vectors: Dictionary) -> Array:
	var target_mean: Array = _mean(target_vectors)
	var centered_source: Array = _subtract(source_embedding, target_mean)
	var scores := []
	for target_name in target_vectors:
		var centered_target: Array = _subtract(target_vectors[target_name], target_mean)
		scores.append({"name": target_name, "score": _cosine_similarity(centered_source, centered_target)})
	return scores

func _subtract(a: Array, b: Array) -> Array:
	var out: Array = []
	out.resize(a.size())
	for i in range(a.size()):
		out[i] = float(a[i]) - float(b[i])
	return out

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

func _softmax(scores: Dictionary, temperature: float = 1.0) -> Dictionary:
	var temp := maxf(temperature, 0.001)
	var max_score := -INF

	for value in scores.values():
		max_score = max(max_score, float(value))

	var exps := {}
	var total := 0.0

	for key in scores:
		var e := exp((float(scores[key]) - max_score) / temp)
		exps[key] = e
		total += e

	if total <= 0.0:
		return exps

	for key in exps:
		exps[key] /= total

	return exps