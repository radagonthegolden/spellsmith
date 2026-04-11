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
signal initialization_finished(success: bool)

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"

var loading := true
var busy := false

func cast_spell_on_enemy(spell: Spell, enemy: Enemies.EnemyDefinition) -> Spell:
	var effective_resonance: float = Enemies.effective_resonance(enemy, spell.embedding)
	return await cast_spell(spell, effective_resonance)

func cast_spell(spell: Variant, factor: float = 1.0) -> Spell:
	if spell is EnemySpell:
		spell.spell = await _text_to_spell(spell.spell.name, factor)
		return spell
	return await _text_to_spell(spell.name, factor)

func _text_to_spell(spell_name: String, factor: float = 1.0) -> Spell:
	var returned: Variant = await AspectLibrary.text_to_actualized(spell_name, true, factor)
	var actualized: Array = returned["actualized"]
	var embedding: Array = returned["embedding"]
	return create_spell(spell_name, embedding, actualized)

func format_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		parts.append(entry.name + " " + str(entry.intensity_rank) + "d")
	return ", ".join(parts)

func _ready() -> void:
	var initialized: bool = await aspect_library.initialize()
	assert(initialized, "AspectLibrary failed to initialize")
	loading = false
	initialization_finished.emit(true)

func filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	var first_player: AspectLibrary.ActualizedAspect = player_profile[0]
	var displayed: Array = [first_player]

	var enemy_entry: AspectLibrary.ActualizedAspect = enemy_profile[0]
	var enemy_aspect_name: String = enemy_entry.name
	var enemy_required_rank: int = enemy_entry.intensity_rank
	for player_entry in player_profile:
		var player_data: AspectLibrary.ActualizedAspect = player_entry
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