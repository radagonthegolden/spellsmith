extends Node
class_name SpellCasting

class Spell extends RefCounted:
	var name: String = ""
	var spell_embedding: Array = []
	var actualized: Array = []

class EnemySpell extends Spell:
	var spell: Spell = null
	var damage: int = -1

signal spell_encoded(spell_name: String)
signal initialization_finished(success: bool)

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var ollama_client: OllamaClient = $OllamaClient
@onready var aspect_library: AspectLibrary = $AspectLibrary
@onready var usage_tracker: SpellUsageTracker = $SpellUsageTracker

var loading := true
var busy := false

func cast_spell(spell: Variant) -> Spell:
	if spell is EnemySpell:
		spell.spell = await _text_to_spell(spell.spell.name)
		return spell
	return await _text_to_spell(spell.name)

func _text_to_spell(spell_name: String) -> Spell:
	var returned: Variant = await aspect_library.text_to_actualized(spell_name, true)
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
) -> Spell:
	var out: Spell = Spell.new()
	out.name = spell_name
	out.spell_embedding = spell_embedding
	out.actualized = actualized
	return out

func create_enemy_spell(
	damage: int,
	spell: Spell,
) -> EnemySpell:
	var out: EnemySpell = EnemySpell.new()
	out.name = spell.name
	out.spell_embedding = spell.spell_embedding
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