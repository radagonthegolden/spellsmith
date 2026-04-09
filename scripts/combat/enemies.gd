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

func _ready() -> void:
	assert(ollama_client != null, "Enemies missing OllamaClient dependency")
	assert(spell_runtime != null, "Enemies missing SpellCasting dependency")

func _enemy_id_from_input(enemy_id_or_name: String) -> String:
	var trimmed: String = enemy_id_or_name.strip_edges()
	assert(not trimmed.is_empty(), "Enemy id or name cannot be empty")
	return trimmed.to_snake_case().to_lower()

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
	for spell_dict in source["spells"]:
		var spell_name: String = str(spell_dict["name"]).strip_edges()
		var damage: int = int(spell_dict["damage"])
		var built_spell: SpellCasting.Spell = await spell_runtime.build_spell_from_text(spell_name, damage, false)

		parsed_spells.append(built_spell)
	out.spells = parsed_spells

	return out

func load_enemy(enemy_id_or_name: String) -> EnemyDefinition:
	var enemy_id: String = _enemy_id_from_input(enemy_id_or_name)
	var file: FileAccess = FileAccess.open("res://data/enemies.json", FileAccess.READ)
	assert(file != null, "Failed to open enemy file")
	var content: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()

	assert(json.parse(content) == OK, "Failed to parse enemy file")
	assert(typeof(json.data) == TYPE_DICTIONARY, "Enemy file must contain a JSON object keyed by enemy id")
	assert(json.data.has(enemy_id), "Enemy not found in file: %s" % enemy_id)

	return await enemy_from_dictionary(json.data[enemy_id])

func get_enemy(enemy_id_or_name: String) -> EnemyDefinition:
	var enemy_id: String = _enemy_id_from_input(enemy_id_or_name)
	if enemies.has(enemy_id):
		return enemies[enemy_id]
	var enemy: EnemyDefinition = await load_enemy(enemy_id)
	enemies[enemy_id] = enemy
	return enemy

func prepare_spell(enemy_def: EnemyDefinition, spell_index: int) -> SpellCasting.Spell:
	assert(enemy_def != null, "Enemy definition is null")
	assert(spell_index >= 0 and spell_index < enemy_def.spells.size(), "Invalid spell index: %d" % spell_index)

	var source_spell: SpellCasting.Spell = enemy_def.spells[spell_index]
	var round_spell: SpellCasting.Spell = spell_runtime.create_spell(
		source_spell.name,
		source_spell.damage,
		source_spell.spell_embedding,
		source_spell.aspect_scores,
		false
	)

	return round_spell