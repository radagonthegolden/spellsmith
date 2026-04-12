extends Node
class_name SpellCasting

class Spell extends RefCounted:
	var name: String = ""
	var embedding: Array = []
	var actualized: Array = []
	var resonance: float = 0.0

class EnemySpell extends Spell:
	var spell: Spell = null
	var damage: int = -1

signal spell_encoded(spell_name: String)
signal startup_finished(success: bool)

# External references
@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var enemies_runtime: Enemies = $"../CombatManager/Enemies"

# Child references
@onready var aspect_library: Aspects = $"AspectLibrary"
@onready var usage_tracker: SpellUsageTracker = $"SpellUsageTracker"
@onready var ollama_client: OllamaClient = $"OllamaClient"
@onready var vector_math: VectorMath = $"VectorMath"

var loading := true
var busy := false

func cast_spell_on_enemy(spell_name: String, enemy: Enemies.EnemyDefinition) -> Variant:
	var spell_embedding: Array = await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var resonance: float = vector_math.cosine_similarity(spell_embedding, enemy.descriptor)
	return await cast_spell(spell_name, resonance)

func cast_spell(input: Variant, resonance: float = 1.0) -> Variant:
	if input is String:
		return await cast_spell_from_name(input, resonance)
	return await cast_spell_from_prepard(input, resonance)

func cast_spell_from_name(spell_name: String, resonance: float = 1.0) -> Variant:
	var spell_embedding: Array = await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var penalty_factor: float = aspect_library.get_length_penalty_factor(spell_name)
	var actualized: Array = aspect_library.embedding_to_actualized(spell_embedding, penalty_factor * resonance)
	return create_spell(spell_name, spell_embedding, actualized, resonance)

func cast_spell_from_prepard(spell: Variant, resonance: float = 1.0) -> Variant:
	if spell is EnemySpell:
		spell.spell = await cast_spell_from_name(spell.spell.name, resonance)
		return spell
	return await cast_spell_from_name(spell.name, resonance)

func format_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		parts.append(entry.name + " " + str(entry.intensity_rank) + "d")
	return ", ".join(parts)

func filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	var first_player: Aspects.ActualizedAspect = player_profile[0]
	var displayed: Array = [first_player]

	var enemy_entry: Aspects.ActualizedAspect = enemy_profile[0]
	var enemy_aspect_name: String = enemy_entry.name
	var enemy_required_rank: int = enemy_entry.intensity_rank
	for player_entry in player_profile:
		var player_data: Aspects.ActualizedAspect = player_entry
		if player_data.name != enemy_aspect_name:
			continue
		if player_data.intensity_rank < enemy_required_rank:
			continue
		if displayed[0].name != enemy_aspect_name:
			displayed.append(player_data)
		return displayed

	return displayed

func create_spell(
	spell_name: String,
	spell_embedding: Array = [],
	actualized: Array = [],
	resonance: float = 0.0
) -> Spell:
	var out: Spell = Spell.new()
	out.name = spell_name
	out.embedding = spell_embedding
	out.actualized = actualized
	out.resonance = resonance
	return out

func create_enemy_spell(
	damage: int,
	spell: Spell,
) -> EnemySpell:
	var out: EnemySpell = EnemySpell.new()
	out.name = spell.name
	out.embedding = spell.embedding
	out.actualized = spell.actualized
	out.spell = spell
	out.damage = damage
	return out	

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()

func _on_spell_cast(spell_name: String = "") -> void:
	if spell_name == "":
		spell_name = spell_input.text
	spell_encoded.emit(spell_name)

func _on_aspect_library_startup_finished(success: bool) -> void:
	startup_finished.emit(success)
