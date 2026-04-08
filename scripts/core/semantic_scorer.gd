extends RefCounted
class_name SemanticScorer

const INTENSITY_LOW_THRESHOLD: float = 0.30
const INTENSITY_MEDIUM_THRESHOLD: float = 0.60
const INTENSITY_HIGH_THRESHOLD: float = 0.90

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

	var target_mean: Array = VectorMath.compute_vector_mean(target_vectors)
	if target_mean.is_empty():
		return []

	var centered_source: Array = VectorMath.subtract_vector(source_embedding, target_mean)
	if centered_source.is_empty():
		return []

	var scores := {}
	for target_name in target_vectors:
		var centered_target: Array = VectorMath.subtract_vector(target_vectors[target_name], target_mean)
		scores[target_name] = VectorMath.cosine_similarity(centered_source, centered_target)

	return _sort_scores(_softmax_scores(scores, softmax_temperature))

static func rank_embedding_against_vectors(source_embedding: Array, target_vectors: Dictionary) -> Array:
	if target_vectors.is_empty():
		return []

	var scores := {}
	for target_name in target_vectors:
		scores[target_name] = VectorMath.cosine_similarity(source_embedding, target_vectors[target_name])

	return _sort_scores(scores)

static func cosine_similarity(a: Array, b: Array) -> float:
	return VectorMath.cosine_similarity(a, b)

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
