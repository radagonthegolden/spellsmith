extends RefCounted
class_name SemanticScorer

## Intensity thresholds for scoring -> dice conversion
const INTENSITY_LOW_THRESHOLD: float = 0.30
const INTENSITY_MEDIUM_THRESHOLD: float = 0.60
const INTENSITY_HIGH_THRESHOLD: float = 0.90

static func average_embeddings(vectors: Array) -> Array:
	return weighted_average_embeddings(vectors, vectors.map(func(_v): return 1.0))

static func weighted_average_embeddings(vectors: Array, weights: Array) -> Array:
	if vectors.is_empty() or vectors.size() != weights.size():
		return []

	var dim : int = vectors[0].size()
	var out: Array = []
	out.resize(dim)
	out.fill(0.0)

	var total_weight := 0.0

	for i in vectors.size():
		var vec: Array = vectors[i]
		var weight := float(weights[i])
		total_weight += weight

		for j in dim:
			out[j] += float(vec[j]) * weight

	if total_weight <= 0.0:
		return []

	for i in dim:
		out[i] /= total_weight

	return out

static func scale_scores(scores: Array, factor: float) -> Array:
	return scores.map(func(entry):
		return {
			"name": str(entry["name"]),
			"score": float(entry["score"]) * factor
		}
	)

static func score_embedding_against_vectors(source_embedding: Array, target_vectors: Dictionary, softmax_temperature: float = 1.0) -> Array:
	if target_vectors.is_empty():
		return []

	var target_mean := _compute_vector_mean(target_vectors)
	if target_mean.is_empty():
		return []

	var centered_source := _subtract_vector(source_embedding, target_mean)
	if centered_source.is_empty():
		return []

	var scores := {}
	for target_name in target_vectors:
		var centered_target := _subtract_vector(target_vectors[target_name], target_mean)
		scores[target_name] = _cosine_similarity(centered_source, centered_target)

	return _sort_scores(_softmax_scores(scores, softmax_temperature))

static func rank_embedding_against_vectors(source_embedding: Array, target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var scores := {}
	for target_name in target_vectors:
		scores[target_name] = _cosine_similarity(source_embedding, target_vectors[target_name])

	return _sort_scores(scores)

static func cosine_similarity(a: Array, b: Array) -> float:
	return _cosine_similarity(a, b)

static func score_to_intensity_rank(score: float) -> int:
	"""Convert a score (0-1) to an intensity rank (0-3) for dice allocation."""
	if score >= INTENSITY_HIGH_THRESHOLD:
		return 3
	if score >= INTENSITY_MEDIUM_THRESHOLD:
		return 2
	if score >= INTENSITY_LOW_THRESHOLD:
		return 1
	return 0

static func score_to_intensity_label(score: float) -> String:
	"""Convert a score to a human-readable intensity label."""
	var intensity_rank: int = score_to_intensity_rank(score)
	match intensity_rank:
		3: return "high"
		2: return "medium"
		1: return "low"
		_: return "faint"

static func _sort_scores(scores: Dictionary) -> Array:
	var items: Array = scores.keys().map(func(key):
		return {
			"name": key,
			"score": scores[key]
		}
	)

	items.sort_custom(func(a, b): return a["score"] > b["score"])
	return items

static func _cosine_similarity(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0

	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0

	for i in a.size():
		var av := float(a[i])
		var bv := float(b[i])
		dot += av * bv
		norm_a += av * av
		norm_b += bv * bv

	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0

	return dot / (sqrt(norm_a) * sqrt(norm_b))

static func _softmax_scores(scores: Dictionary, temperature: float = 1.0) -> Dictionary:
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

static func _compute_vector_mean(target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var first_vec: Array = target_vectors.values()[0]
	var dim := first_vec.size()

	var mean: Array = []
	mean.resize(dim)
	mean.fill(0.0)

	var count := 0
	for vec in target_vectors.values():
		for i in dim:
			mean[i] += float(vec[i])
		count += 1

	for i in dim:
		mean[i] /= float(count)

	return mean

static func _subtract_vector(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return []

	var out: Array = []
	out.resize(a.size())

	for i in a.size():
		out[i] = float(a[i]) - float(b[i])

	return out