extends Node
class_name Spell

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
	if not initialized:
		push_error("AspectLibrary failed to initialize")
		initialization_finished.emit(false)
		return

	loading = false
	initialization_finished.emit(true)

func _on_spell_cast(text = null) -> void:
	if loading or busy:
		return

	var cast_text := _extract_cast_text(text)
	if cast_text.is_empty():
		return

	busy = true
	var spell_embedding: Array = await _compute_spell_embedding(cast_text)
	busy = false

	if spell_embedding.is_empty():
		return

	spell_encoded.emit(spell_embedding, cast_text)
	spell_input.text = ""
	print(spell_embedding)

func _extract_cast_text(text: Variant) -> String:
	# Button presses call without args; text_submitted provides the string.
	if text == null:
		text = spell_input.text

	var cast_text := str(text).strip_edges()
	return cast_text

func _compute_spell_embedding(cast_text: String) -> Array:
	var result: Dictionary = await ollama_client.embed(cast_text)
	if not result.get("ok", false):
		push_error("Embedding request failed")
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		push_error("Empty embeddings")
		return []

	return embeddings[0]

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()
