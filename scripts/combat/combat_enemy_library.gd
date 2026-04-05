extends RefCounted
class_name CombatEnemyLibrary

const CombatStateResource := preload("res://scripts/combat/combat_state.gd")

var enemies_by_name := {}

func load_from_file(file_path: String) -> void:
	enemies_by_name.clear()
	assert(FileAccess.file_exists(file_path), "Enemy file not found: %s" % file_path)

	var file := FileAccess.open(file_path, FileAccess.READ)
	assert(file != null, "Failed to open enemy file: %s" % file_path)

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	assert(json.parse(content) == OK, "Failed to parse enemy file: %s" % file_path)

	for entry in json.data:
		var enemy: Dictionary = entry
		enemies_by_name[str(enemy["name"])] = enemy

func get_enemy(enemy_name: String) -> Dictionary:
	return enemies_by_name.get(enemy_name, {})

func build_descriptor_vector(enemy: Dictionary, ollama_client: OllamaClient) -> Array:
	var descriptions: Array = enemy.get("descriptor_sentences", [])
	var embeddings: Array = await ollama_client.embed_many(descriptions, "Enemy descriptor")
	return SemanticScorer.average_embeddings(embeddings)

func prepare_enemy_spell(enemy: Dictionary, ollama_client: OllamaClient, aspect_library: AspectLibrary) -> Dictionary:
	var spell_pool: Array = enemy.get("spells", [])
	assert(not spell_pool.is_empty(), "Enemy has no local spells: %s" % enemy.get("name", "Unknown Enemy"))

	var spell: Dictionary = spell_pool.pick_random()
	var spell_name := str(spell.get("name", ""))

	if not spell.has("_aspect_scores"):
		var spell_embedding: Array = await ollama_client.embed_one(spell_name, "Enemy spell embedding")
		if spell_embedding.is_empty():
			return {}

		spell["_aspect_scores"] = aspect_library.score_embedding(spell_embedding, spell_name)

	spell["_intensity_profile"] = CombatStateResource.build_primary_profile(spell["_aspect_scores"])
	return spell