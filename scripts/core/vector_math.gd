extends RefCounted
class_name VectorMath

static func average_embeddings(vectors: Array) -> Array:
	return weighted_average_embeddings(vectors, vectors.map(func(_entry): return 1.0))

static func weighted_average_embeddings(vectors: Array, weights: Array) -> Array:
	if vectors.is_empty() or vectors.size() != weights.size():
		return []

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

	if total_weight <= 0.0:
		return []

	for i in range(dim):
		out[i] /= total_weight
	return out

static func cosine_similarity(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0

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

static func compute_vector_mean(vectors: Dictionary) -> Array:
	if vectors.is_empty():
		return []

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

static func subtract_vector(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return []

	var out: Array = []
	out.resize(a.size())
	for i in range(a.size()):
		out[i] = float(a[i]) - float(b[i])
	return out

static func cosine_similarity_scores(source_embedding: Array, target_vectors: Dictionary) -> Dictionary:
	if target_vectors.is_empty():
		return {}

	var scores := {}
	for target_name in target_vectors:
		scores[target_name] = cosine_similarity(source_embedding, target_vectors[target_name])
	return scores

static func centered_cosine_similarity_scores(source_embedding: Array, target_vectors: Dictionary) -> Dictionary:
	if target_vectors.is_empty():
		return {}

	var target_mean: Array = compute_vector_mean(target_vectors)
	if target_mean.is_empty():
		return {}

	var centered_source: Array = subtract_vector(source_embedding, target_mean)
	if centered_source.is_empty():
		return {}

	var scores := {}
	for target_name in target_vectors:
		var centered_target: Array = subtract_vector(target_vectors[target_name], target_mean)
		scores[target_name] = cosine_similarity(centered_source, centered_target)
	return scores

static func softmax(scores: Dictionary, temperature: float = 1.0) -> Dictionary:
	if scores.is_empty():
		return {}

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

static func sort_named_scores(scores: Dictionary) -> Array:
	var items: Array = scores.keys().map(func(key):
		return {
			"name": key,
			"score": scores[key]
		}
	)

	items.sort_custom(func(a, b): return a["score"] > b["score"])
	return items