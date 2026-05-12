extends Node
class_name SpellCasting

class Spell extends RefCounted:
	var name: String = ""
	var embedding: Array = []
	var profile: Array = []
	var actualized: Array = []
	var resonance: float = 0.0

	func _init(
		spell_name: String = "",
		spell_embedding: Array = [],
		spell_profile: Array = [],
		spell_resonance: float = 0.0,
		spell_actualized: Array = []
	) -> void:
		name = spell_name
		embedding = spell_embedding
		profile = spell_profile
		resonance = spell_resonance
		actualized = spell_actualized

	func _to_string() -> String:
		var parts: Array = []
		for aspect in profile:
			parts.append(str(aspect))
		return ", ".join(parts)

	func profile_to_rolls() -> Dictionary:
		var out := {}
		for aspect in profile:
			out[aspect.name] = aspect.roll()
		return out

	func rolls_to_string(rolls: Dictionary) -> String:
		var parts: Array = []
		for aspect_name in rolls.keys():
			parts.append(
				"%s: %dd -> %s" % [
					aspect_name,
					rolls[aspect_name]["results"].size(),
					"+".join(rolls[aspect_name]["results"].map(func(num): return str(num)))
				]
			)
		return ", ".join(parts)

	func roll_total_for(rolls: Dictionary, aspect_name: String) -> int:
		if not rolls.has(aspect_name):
			return 0
		return rolls[aspect_name]["total"]

	func primary_aspect_name() -> String:
		return profile[0].name

class EnemySpell extends Spell:
	var damage: int = -1

	func _init(spell_damage: int = -1, spell: Spell = null) -> void:
		if spell == null:
			super()
		else:
			super(
				spell.name,
				spell.embedding,
				[spell.profile[0]] if spell.profile.size() > 0 else [],
				spell.resonance,
				spell.actualized
			)
		damage = spell_damage

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
	var spell_embedding: Array = await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var resonance: float = enemies_runtime.effective_resonance(enemy, spell_embedding)
	var penalty_factor: float = aspect_library.get_length_penalty_factor(spell_name)
	var profile := aspect_library.embedding_to_profile(spell_embedding, penalty_factor * resonance)
	var actualized: Array = aspect_library.get_raw_scores(spell_embedding)
	return Spell.new(spell_name, spell_embedding, profile, resonance, actualized)

func cast_spell(input: Variant, resonance: float = 1.0) -> Variant:
	if input is String:
		return await cast_spell_from_name(input, resonance)
	return await cast_spell_from_prepard(input, resonance)

func cast_spell_from_name(spell_name: String, resonance: float = 1.0) -> Variant:
	var spell_embedding := await ollama_client.embed(spell_name, "Spell casting: " + spell_name)
	var penalty_factor := aspect_library.get_length_penalty_factor(spell_name)
	var profile := aspect_library.embedding_to_profile(spell_embedding, penalty_factor * resonance)
	var actualized: Array = aspect_library.get_raw_scores(spell_embedding)
	return Spell.new(spell_name, spell_embedding, profile, resonance, actualized)

func cast_spell_from_prepard(spell: Variant, resonance: float = 1.0) -> Variant:
	if spell is EnemySpell:
		return EnemySpell.new(spell.damage, await cast_spell_from_name(spell.name, resonance))
	return await cast_spell_from_name(spell.name, resonance)

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()

func _on_spell_cast(spell_name: String = "") -> void:
	if spell_name == "":
		spell_name = spell_input.text
	spell_encoded.emit(spell_name)

func _on_aspect_library_startup_finished(success: bool) -> void:
	loading = false
	startup_finished.emit(success)
