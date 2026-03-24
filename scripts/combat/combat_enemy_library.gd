extends RefCounted
class_name CombatEnemyLibrary

const CombatStateResource := preload("res://scripts/combat/combat_state.gd")

var enemies_by_name: Dictionary = {}

func load_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("Enemy file not found: " + file_path)
		enemies_by_name.clear()
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open enemy file: " + file_path)
		enemies_by_name.clear()
		return

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(content)
	if parse_result != OK:
		push_error("Failed to parse enemy file: " + file_path)
		enemies_by_name.clear()
		return

	enemies_by_name.clear()
	var enemies: Array = json.data
	for entry in enemies:
		var enemy: Dictionary = entry
		enemies_by_name[str(enemy["name"])] = enemy

func get_enemy(enemy_name: String) -> Dictionary:
	return enemies_by_name.get(enemy_name, {})

func build_descriptor_vector(enemy: Dictionary, ollama_client: OllamaClient) -> Array:
	var descriptions: Array = enemy["descriptor_sentences"]
	var embeddings: Array = await ollama_client.embed_many(descriptions, "Enemy descriptor")
	if embeddings.is_empty():
		return []

	return SemanticScorer.average_embeddings(embeddings)

func prepare_enemy_spell(enemy: Dictionary, ollama_client: OllamaClient, aspect_library: AspectLibrary) -> Dictionary:
	var spell_pool: Array = enemy.get("spells", [])
	if spell_pool.is_empty():
		push_error("Enemy has no local spells: " + str(enemy.get("name", "Unknown Enemy")))
		return {}

	var prepared_enemy_spell: Dictionary = spell_pool[randi() % spell_pool.size()]
	if not prepared_enemy_spell.has("_aspect_scores"):
		var enemy_spell_embedding: Array = await ollama_client.embed_one(str(prepared_enemy_spell["name"]), "Enemy spell embedding")
		if enemy_spell_embedding.is_empty():
			return {}
		prepared_enemy_spell["_aspect_scores"] = aspect_library.score_embedding(enemy_spell_embedding, str(prepared_enemy_spell["name"]))

	prepared_enemy_spell["_intensity_profile"] = CombatStateResource.build_primary_profile(prepared_enemy_spell["_aspect_scores"])
	return prepared_enemy_spell
