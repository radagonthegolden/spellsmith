extends Node
class_name SpellCasting

class Spell extends RefCounted:
	var name: String = ""
	var damage: int = 0
	var spell_embedding: Array = []
	var aspect_scores: Array = []
	var intensity_profile: Array = []

signal spell_encoded(spell_embedding: Array, text: String)
signal initialization_finished(success: bool)

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var ollama_client: OllamaClient = $OllamaClient
@onready var aspect_library: AspectLibrary = $AspectLibrary
@onready var usage_tracker: SpellUsageTracker = $SpellUsageTracker

var loading := true
var busy := false

func _ready() -> void:
	var initialized: bool = await aspect_library.initialize()
	assert(initialized, "AspectLibrary failed to initialize")

	loading = false
	initialization_finished.emit(true)

func _on_spell_cast(text = null) -> void:
	if loading or busy:
		return

	var cast_text := str(text if text != null else spell_input.text).strip_edges()
	if cast_text.is_empty():
		return

	busy = true
	var spell_embedding: Array = await ollama_client.embed_one(cast_text, "Spell embedding")
	busy = false

	assert(not spell_embedding.is_empty(), "Spell embedding cannot be empty for cast text")

	spell_encoded.emit(spell_embedding, cast_text)
	spell_input.text = ""
	print(spell_embedding)

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()

func score_spell_embedding(spell_embedding: Array, source_text: String) -> Array:
	return aspect_library.score_embedding(spell_embedding, source_text)

func scale_spell_scores(scores: Array, factor: float) -> Array:
	return AspectLibrary.scale_scores(scores, factor)

func build_primary_profile(scores: Array) -> Array:
	return _build_profile(scores, 1)

func build_full_profile(scores: Array) -> Array:
	return _build_profile(scores, -1)

func format_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		var data: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(entry)
		parts.append(data.name + " " + str(data.intensity_rank) + "d")
	return ", ".join(parts)

func filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	if player_profile.is_empty():
		return []
	var first_player: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(player_profile[0])

	var displayed: Array = [first_player]
	if enemy_profile.is_empty():
		return displayed

	var enemy_entry: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(enemy_profile[0])
	var enemy_aspect_name: String = enemy_entry.name
	var enemy_required_rank: int = enemy_entry.intensity_rank
	for player_entry in player_profile:
		var player_data: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(player_entry)
		if player_data.name != enemy_aspect_name:
			continue
		if player_data.intensity_rank < enemy_required_rank:
			continue
		if (displayed[0] as AspectLibrary.ActualizedAspect).name != enemy_aspect_name:
			displayed.append(player_data)
		return displayed

	return displayed

func _build_profile(scores: Array, max_intensity: int) -> Array:
	var profile: Array = []
	for entry in scores:
		var aspect_data: AspectLibrary.ActualizedAspect = AspectLibrary.as_actualized(entry)
		var intensity_rank: int = AspectLibrary.score_to_intensity_rank(aspect_data.score)
		if max_intensity != -1 and intensity_rank > max_intensity:
			intensity_rank = max_intensity
		profile.append(AspectLibrary.make_actualized(aspect_data.name, float(intensity_rank)))
	profile.sort_custom(func(a, b): return (a as AspectLibrary.ActualizedAspect).score > (b as AspectLibrary.ActualizedAspect).score)
	return profile

func create_spell(
	spell_name: String,
	damage: int,
	spell_embedding: Array,
	aspect_scores: Array,
	use_full_profile: bool = false
) -> Spell:
	var out: Spell = Spell.new()
	out.name = spell_name
	out.damage = damage
	out.spell_embedding = spell_embedding
	out.aspect_scores = aspect_scores
	out.intensity_profile = build_full_profile(aspect_scores) if use_full_profile else build_primary_profile(aspect_scores)
	return out

func build_spell_from_text(spell_name: String, damage: int = 0, use_full_profile: bool = false) -> Spell:
	var normalized_name: String = spell_name.strip_edges()
	assert(not normalized_name.is_empty(), "Spell name cannot be empty")

	var spell_embedding: Array = await ollama_client.embed_one(normalized_name, "Spell embedding")
	assert(not spell_embedding.is_empty(), "Spell embedding cannot be empty: %s" % normalized_name)

	var aspect_scores: Array = score_spell_embedding(spell_embedding, normalized_name)
	assert(not aspect_scores.is_empty(), "Spell aspect_scores cannot be empty: %s" % normalized_name)

	return create_spell(normalized_name, damage, spell_embedding, aspect_scores, use_full_profile)

func get_aspect_names() -> PackedStringArray:
	return aspect_library.get_aspect_names()
