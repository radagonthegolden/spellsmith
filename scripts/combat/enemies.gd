extends Node
class_name Enemies

@onready var ollama_client: OllamaClient = $"../../SpellCasting/OllamaClient"
@onready var spell_runtime: SpellCasting = $"../../SpellCasting"

class EnemyDefinition extends RefCounted:
	var name: String = ""
	var descriptor_sentences: Array = []
	var spells: Array = []
	var min_descriptor_resonance: float = 0.0
	var max_descriptor_resonance: float = 1.0
	var player_victory_conditions: Array = []
	var player_loss_conditions: Array = []
	var descriptor: Array = []

var enemies: Dictionary = {}

static func load_enemy(enemy_name: String) -> EnemyDefinition:
	var enemy_id: String = enemy_name.strip_edges().to_snake_case().to_lower()
	var file: FileAccess = FileAccess.open("res://data/enemies.json", FileAccess.READ)
	assert(file != null, "Failed to open enemy file")
	var content: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()

	assert(json.parse(content) == OK, "Failed to parse enemy file")
	assert(typeof(json.data) == TYPE_DICTIONARY, "Enemy file must contain a JSON object keyed by enemy id")
	assert(json.data.has(enemy_id), "Enemy not found in file: %s" % enemy_id)

	var source : Dictionary = json.data[enemy_id]

	var out: EnemyDefinition = EnemyDefinition.new()
	out.name = str(source["name"])
	out.descriptor_sentences = source["descriptor_sentences"]
	out.min_descriptor_resonance = float(source.get("min_descriptor_resonance", 0.0))
	out.max_descriptor_resonance = float(source.get("max_descriptor_resonance", 1.0))
	out.player_victory_conditions = source.get("player_victory_conditions", [])
	out.player_loss_conditions = source.get("player_loss_conditions", [])

	var descriptions: Array = out.descriptor_sentences
	var embeddings: Array = await ollama_client.embed(descriptions, "Enemy descriptor")
	out.descriptor = VectorMath.average_embeddings(embeddings)

	var parsed_spells: Array = []
	for spell_dict in source["spells"]:
		var spell = spell_runtime.create_enemy_spell(
			int(spell_dict["damage"]),
			spell_runtime.create_spell(str(spell_dict["name"]), [], [])
		)
		parsed_spells.append(spell)
	out.spells = parsed_spells

	return out

static func get_enemy(enemy_name: String) -> EnemyDefinition:
	var enemy_id: String = enemy_name.strip_edges().to_snake_case().to_lower()
	if enemies.has(enemy_id):
		return enemies[enemy_id]
	var enemy: EnemyDefinition = await load_enemy(enemy_name)
	enemies[enemy_id] = enemy
	return enemy

static func get_random_spell(enemy_def: EnemyDefinition) -> SpellCasting.Spell:
	return enemy_def.spells[randi_range(0, enemy_def.spells.size() - 1)]

static func cast_random_spell(enemy_def: EnemyDefinition) -> SpellCasting.Spell:
	var spell_def: SpellCasting.EnemySpell = get_random_spell(enemy_def)
	return await spell_runtime.cast_spell(spell_def)

static func effective_resonance(enemy: EnemyDefinition, embedding: Array) -> float:
	return VectorMath.resonance(
		embedding, 
		enemy.descriptor, 
		enemy.min_descriptor_resonance,
		 enemy.max_descriptor_resonance
	)
