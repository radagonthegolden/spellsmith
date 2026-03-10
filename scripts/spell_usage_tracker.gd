extends Node
class_name SpellUsageTracker

@export var usage_file_path: String = "user://spell_usage.json"
@export var repeated_spell_penalty: float = 0.30
@export var repeated_word_penalty: float = 0.10
@export var min_multiplier: float = 0.20

var spell_counts: Dictionary = {}
var word_counts: Dictionary = {}
var non_word_regex := RegEx.new()

func _ready() -> void:
	non_word_regex.compile("[^a-z0-9']+")
	_load_usage()

func compute_multiplier_and_register(spell_text: String) -> float:
	var normalized := _normalize_spell(spell_text)
	var words := _tokenize_words(normalized)
	var unique_words := _unique_words(words)

	var multiplier := 1.0
	var spell_uses := int(spell_counts.get(normalized, 0))
	multiplier -= repeated_spell_penalty * float(spell_uses)

	for word in unique_words:
		var word_uses := int(word_counts.get(word, 0))
		multiplier -= repeated_word_penalty * float(word_uses)

	multiplier = max(min_multiplier, multiplier)

	_register_cast(normalized, unique_words)
	_save_usage()
	return multiplier

func _register_cast(normalized_spell: String, unique_words: Array) -> void:
	spell_counts[normalized_spell] = int(spell_counts.get(normalized_spell, 0)) + 1
	for word in unique_words:
		word_counts[word] = int(word_counts.get(word, 0)) + 1

func _normalize_spell(text: String) -> String:
	return text.strip_edges().to_lower()

func _tokenize_words(normalized_text: String) -> Array:
	var parts := normalized_text.split(" ", false)
	var out := []
	for part in parts:
		var cleaned := non_word_regex.sub(part, "", true)
		if not cleaned.is_empty():
			out.append(cleaned)
	return out

func _unique_words(words: Array) -> Array:
	var seen := {}
	var unique := []
	for word in words:
		if not seen.has(word):
			seen[word] = true
			unique.append(word)
	return unique

func _load_usage() -> void:
	if not FileAccess.file_exists(usage_file_path):
		return

	var file := FileAccess.open(usage_file_path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(content)
	if parse_result != OK:
		push_error("Failed to parse spell usage file")
		return

	var data: Dictionary = json.data
	spell_counts = data.get("spells", {})
	word_counts = data.get("words", {})

func _save_usage() -> void:
	var payload := {
		"spells": spell_counts,
		"words": word_counts
	}

	var file := FileAccess.open(usage_file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func purge_usage() -> void:
	spell_counts.clear()
	word_counts.clear()

	if FileAccess.file_exists(usage_file_path):
		DirAccess.remove_absolute(usage_file_path)
