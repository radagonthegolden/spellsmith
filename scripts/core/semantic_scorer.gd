extends RefCounted
class_name SemanticScorer

static func average_embeddings(vectors: Array) -> Array:
	if vectors.is_empty():
		return []

	var dim: int = vectors[0].size()
	var out: Array = []
	out.resize(dim)
	out.fill(0.0)

	for vec in vectors:
		for i in range(dim):
			out[i] += float(vec[i])

	var inv_count: float = 1.0 / float(vectors.size())
	for i in range(dim):
		out[i] *= inv_count

	return out

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

static func score_embedding_against_vectors(source_embedding: Array, target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var target_mean: Array = _compute_vector_mean(target_vectors)
	if target_mean.is_empty():
		return []

	var centered_source: Array = _subtract_vector(source_embedding, target_mean)
	var scores: Dictionary = {}

	for target_name in target_vectors.keys():
		var target_embedding: Array = target_vectors[target_name]
		var centered_target: Array = _subtract_vector(target_embedding, target_mean)
		scores[target_name] = _cosine_similarity(centered_source, centered_target)

	return _sort_scores(_softmax_scores(scores))

static func rank_embedding_against_vectors(source_embedding: Array, target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var ranked_scores: Dictionary = {}
	for target_name in target_vectors.keys():
		var target_embedding: Array = target_vectors[target_name]
		ranked_scores[target_name] = _cosine_similarity(source_embedding, target_embedding)

	return _sort_scores(ranked_scores)

static func cosine_similarity(a: Array, b: Array) -> float:
	return _cosine_similarity(a, b)

static func scale_vector(vector: Array, factor: float) -> Array:
	var out: Array = []
	out.resize(vector.size())

	for i in range(vector.size()):
		out[i] = float(vector[i]) * factor

	return out

static func add_vectors(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return []

	var out: Array = []
	out.resize(a.size())

	for i in range(a.size()):
		out[i] = float(a[i]) + float(b[i])

	return out

static func normalize_vector(vector: Array) -> Array:
	if vector.is_empty():
		return []

	var norm: float = 0.0
	for value in vector:
		var scalar: float = float(value)
		norm += scalar * scalar

	if norm <= 0.0:
		return zero_vector(vector.size())

	var inv_norm: float = 1.0 / sqrt(norm)
	var out: Array = []
	out.resize(vector.size())

	for i in range(vector.size()):
		out[i] = float(vector[i]) * inv_norm

	return out

static func zero_vector(size: int) -> Array:
	var out: Array = []
	out.resize(size)
	out.fill(0.0)
	return out

static func _sort_scores(scores: Dictionary) -> Array:
	var items: Array = []

	for key in scores.keys():
		items.append({
			"name": key,
			"score": scores[key]
		})

	items.sort_custom(func(a, b): return a["score"] > b["score"])
	return items

static func _cosine_similarity(a: Array, b: Array) -> float:
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

static func _softmax_scores(scores: Dictionary) -> Dictionary:
	if scores.is_empty():
		return {}

	var max_score: float = -INF
	for value in scores.values():
		max_score = max(max_score, float(value))

	var exps: Dictionary = {}
	var total: float = 0.0

	for key in scores.keys():
		var e: float = exp(float(scores[key]) - max_score)
		exps[key] = e
		total += e

	if total <= 0.0:
		return exps

	for key in exps.keys():
		exps[key] /= total

	return exps

static func _compute_vector_mean(target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var first_key: Variant = target_vectors.keys()[0]
	var dim: int = target_vectors[first_key].size()

	var mean: Array = []
	mean.resize(dim)
	mean.fill(0.0)

	var count: int = 0
	for vec in target_vectors.values():
		for i in range(dim):
			mean[i] += float(vec[i])
		count += 1

	if count > 0:
		for i in range(dim):
			mean[i] /= float(count)

	return mean

static func _subtract_vector(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return []

	var out: Array = []
	out.resize(a.size())

	for i in range(a.size()):
		out[i] = float(a[i]) - float(b[i])

	return out
