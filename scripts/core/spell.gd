extends Node
class_name Spell

signal spell_scored(sorted_scores: Array, text: String, cast_multiplier: float)

@onready var spell_input: LineEdit = $"../OuterMargin/ShadowPanel/Panel/Content/InputRow/InputMargin/LineEdit"
@onready var ollama_client: OllamaClient = $OllamaClient
@onready var aspect_library: AspectLibrary = $AspectLibrary
@onready var usage_tracker: SpellUsageTracker = $SpellUsageTracker

var loading := true
var busy := false

func _ready() -> void:
	var initialized: bool = await aspect_library.initialize()
	if not initialized:
		push_error("AspectLibrary failed to initialize")
		return

	loading = false

func _on_spell_cast(text = null) -> void:
	if loading or busy:
		return

	var cast_text := _extract_cast_text(text)
	if cast_text.is_empty():
		return

	busy = true
	var sorted_scores: Array = await _compute_sorted_scores(cast_text)
	busy = false

	if sorted_scores.is_empty():
		return

	var cast_multiplier := usage_tracker.compute_multiplier_and_register(cast_text)
	spell_scored.emit(sorted_scores, cast_text, cast_multiplier)
	spell_input.text = ""
	print(sorted_scores)

func _extract_cast_text(text: Variant) -> String:
	# Button presses call without args; text_submitted provides the string.
	if text == null:
		text = spell_input.text

	var cast_text := str(text).strip_edges()
	return cast_text

func _compute_sorted_scores(cast_text: String) -> Array:
	var result: Dictionary = await ollama_client.embed(cast_text)
	if not result.get("ok", false):
		push_error("Embedding request failed")
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		push_error("Empty embeddings")
		return []

	var spell_embedding: Array = embeddings[0]
	var sorted_scores: Array = aspect_library.score_embedding(spell_embedding)
	if sorted_scores.is_empty():
		push_error("No aspect scores were produced")
		return []

	return sorted_scores

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()
