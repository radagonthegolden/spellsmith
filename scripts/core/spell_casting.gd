extends Node
class_name SpellCasting

class Spell extends RefCounted:
	var name: String = ""
	var embedding: Array = []
	var profile: Aspects.ActualizedProfile = Aspects.ActualizedProfile.new()
	var resonance: float = 0.0

class EnemySpell extends Spell:
	var spell: Spell = null
	var damage: int = -1

signal spell_encoded(spell_name: String)
signal startup_finished(success: bool)

@onready var spell_input: LineEdit = get_node_or_null("../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit")
@onready var enemies_runtime: Enemies = get_node_or_null("../CombatManager/Enemies")

@onready var aspect_library: Aspects = $"AspectLibrary"
@onready var usage_tracker: SpellUsageTracker = $"SpellUsageTracker"
@onready var ollama_client: OllamaClient = $"OllamaClient"

var loading := true
var busy := false

func cast_spell_on_enemy(spell_name: String, enemy: Enemies.EnemyDefinition) -> Variant:
	assert(enemies_runtime != null, "SpellCasting requires CombatManager/Enemies for cast_spell_on_enemy")
	var spell_embedding: Array = await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var resonance: float = enemies_runtime.effective_resonance(enemy, spell_embedding)
	var penalty_factor: float = aspect_library.get_length_penalty_factor(spell_name)
	var profile := aspect_library.embedding_to_profile(spell_embedding, penalty_factor * resonance, true)
	return create_spell(spell_name, spell_embedding, profile, resonance)

func cast_spell(input: Variant, resonance: float = 1.0) -> Variant:
	if input is String:
		return await cast_spell_from_name(input, resonance)
	return await cast_spell_from_prepard(input, resonance)

func cast_spell_from_name(spell_name: String, resonance: float = 1.0) -> Variant:
	var spell_embedding := await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var penalty_factor := aspect_library.get_length_penalty_factor(spell_name)
	var profile := aspect_library.embedding_to_profile(spell_embedding, penalty_factor * resonance)
	return create_spell(spell_name, spell_embedding, profile, resonance)

func cast_spell_from_prepard(spell: Variant, resonance: float = 1.0) -> Variant:
	if spell is EnemySpell:
		spell.spell = await cast_spell_from_name(spell.spell.name, resonance)
		return spell
	return await cast_spell_from_name(spell.name, resonance)

func create_spell(
	spell_name: String,
	spell_embedding: Array = [],
	profile: Aspects.ActualizedProfile = null,
	resonance: float = 0.0
) -> Spell:
	var out: Spell = Spell.new()
	out.name = spell_name
	out.embedding = spell_embedding
	out.profile = profile if profile != null else Aspects.ActualizedProfile.new()
	out.resonance = resonance
	return out

func create_enemy_spell(
	damage: int,
	spell: Spell,
) -> EnemySpell:
	var out: EnemySpell = EnemySpell.new()
	out.name = spell.name
	out.embedding = spell.embedding
	out.profile = spell.profile
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
	loading = false
	startup_finished.emit(success)
