extends Node
class_name Enemies

@onready var ollama_client: OllamaClient = $"../../spell/OllamaClient"
@onready var combat_resolution: CombatResolution = $"../../spell/OllamaClient"
@onready var spell_runtime: SpellCasting = $"../../SpellRuntime"

class EnemyDefinition extends RefCounted:
	var name: String = ""
	var descriptor_sentences: Array = []
	var spells: Array = []
	var min_descriptor_resonance: float = 0.0
	var max_descriptor_resonance: float = 1.0
	var player_victory_conditions: Array = []
	var player_loss_conditions: Array = []
	var descriptor: Array = []

class Spell extends RefCounted:
	var name: String = ""
	var damage: int = 0
	var aspect_scores: Array = []
	var intensity_profile: Array = []
	var spell_embedding: Array = []

var enemies: Dictionary = {}

func enemy_from_dictionary(source: Dictionary) -> EnemyDefinition:
	assert(source["spells"] is Array, "Enemy spells must be an Array: %s" % str(source["name"]))
	assert(not (source["spells"] as Array).is_empty(), "Enemy has no spells: %s" % str(source["name"]))

	var out: EnemyDefinition = EnemyDefinition.new()
	out.name = str(source["name"])
	out.descriptor_sentences = source["descriptor_sentences"]
	out.min_descriptor_resonance = float(source.get("min_descriptor_resonance", 0.0))
	out.max_descriptor_resonance = float(source.get("max_descriptor_resonance", 1.0))
	out.player_victory_conditions = source.get("player_victory_conditions", [])
	out.player_loss_conditions = source.get("player_loss_conditions", [])

	assert(not out.descriptor_sentences.is_empty(), "Enemy descriptor_sentences cannot be empty: %s" % out.name)
	var descriptions: Array = out.descriptor_sentences
	var embeddings: Array = await ollama_client.embed_many(descriptions, "Enemy descriptor")
	out.descriptor = VectorMath.average_embeddings(embeddings)

	var parsed_spells: Array = []
	for spell_entry in source["spells"]:
		var parsed_spell: Spell = Spell.new()
		parsed_spell.name = str(spell_entry["name"]).strip_edges()
		parsed_spell.damage = int(spell_entry["damage"])
		parsed_spell.spell_embedding = await ollama_client.embed_one(parsed_spell.name, "Enemy spell embedding")
		assert(not parsed_spell.spell_embedding.is_empty(), "Enemy spell embedding cannot be empty: %s (%s)" % [out.name, parsed_spell.name])
		parsed_spell.aspect_scores = spell_runtime.score_spell_embedding(parsed_spell.spell_embedding, parsed_spell.name)
		assert(not parsed_spell.aspect_scores.is_empty(), "Enemy spell aspect_scores cannot be empty: %s (%s)" % [out.name, parsed_spell.name])
		parsed_spell.aspect_scores = parsed_spell.aspect_scores

		parsed_spells.append(parsed_spell)
	out.spells = parsed_spells

	return out

func load_enemy(enemy_name: String) -> EnemyDefinition:
	var file: FileAccess = FileAccess.open("res://data/enemies", FileAccess.READ)
	assert(file != null, "Failed to open enemy file")
	var content: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()

	assert(json.parse(content) == OK, "Failed to parse enemy file")
	assert(typeof(json.data) == TYPE_DICTIONARY, "Enemy file must contain a JSON object keyed by enemy id")
	assert(json.data.has(enemy_name), "Enemy not found in file: %s" % enemy_name)

	return await enemy_from_dictionary(json.data[enemy_name])

func get_enemy(enemy_name: String) -> EnemyDefinition:
	if enemies.has(enemy_name):
		return enemies[enemy_name]
	var enemy: EnemyDefinition = await load_enemy(enemy_name)
	enemies[enemy_name] = enemy
	return enemy