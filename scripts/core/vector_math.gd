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