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

	var cast_text := str(spell_input.text).strip_edges()
	if cast_text.is_empty():
		return

	busy = true
	var spell_embedding: Array = await ollama_client.embed_one(cast_text, "Spell embedding")
	busy = false

	if spell_embedding.is_empty():
		return

	spell_encoded.emit(spell_embedding, cast_text)
	spell_input.text = ""
	print(spell_embedding)

func _on_purge_spell_usage_pressed() -> void:
	usage_tracker.purge_usage()