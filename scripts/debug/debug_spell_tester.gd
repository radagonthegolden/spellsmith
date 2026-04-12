
extends Control

const BAR_WIDTH: int = 20
const BAR_MAX: float = 0.35
const BATCH_FILE: String = "res://data/debug_spells.json"


@onready var spell_casting: SpellCasting = $SpellCasting
@onready var _status: Label = $MarginContainer/VBox/Status
@onready var _output: RichTextLabel = $MarginContainer/VBox/Output
@onready var _input: LineEdit = $MarginContainer/VBox/InputRow/Input
@onready var _button_test: Button = $MarginContainer/VBox/InputRow/TestButton
@onready var _button_batch: Button = $MarginContainer/VBox/InputRow/BatchButton
var _ready_for_input: bool = false

func _on_spell_casting_startup_finished(success: bool) -> void:
	_input.text_submitted.connect(_on_cast)
	_button_test.pressed.connect(func(): _on_cast(_input.text))
	_button_batch.pressed.connect(func(): _run_batch())
	_ready_for_input = true
	_run_batch()

func _lock_ui(status: String) -> void:
	_status.text = status
	_input.editable = false
	_button_test.disabled = true
	_button_batch.disabled = true

func _unlock_ui(status: String) -> void:
	_status.text = status
	_input.editable = true
	_button_test.disabled = false
	_button_batch.disabled = false
	_input.grab_focus()

# ── Manual test ──────────────────────────────────────────────────────────────

func _on_cast(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or not _ready_for_input:
		return
	_lock_ui("Embedding...")

	var result: Dictionary = await spell_casting.aspect_library.text_to_actualized(text, true)

	var final_scores: Array = result["actualized"]
	var penalty: float = 1.0
	# Penalty logic can be customized if needed

	_render_single(text, final_scores, penalty)
	_unlock_ui("Ready — enter a spell phrase to test")

func _render_single(spell: String, final_scores: Array, penalty: float) -> void:
	var lines: Array[String] = []
	lines.append('[b]"%s"[/b] %s' % spell % spell)
	lines.append("Penalty: [b]%.3f[/b]   entropy: [b]%.3f[/b]" % [
		penalty, _entropy(final_scores)
	])
	lines.append("")

	for e in final_scores:
		var data = e
		var aspect_name: String = data.name
		var fs: float = data.score
		var bar: String = _bar(fs)
		var color: String = _color(fs)
		var label: String = _label(fs)
		lines.append("[color=%s][b]%-6s[/b][/color]  %s  %.4f   [i]%s[/i]" % [
			color, label.to_upper(), bar, fs, aspect_name
		])

	lines.append("")
	lines.append("[color=#888]Thresholds: low ≥ %.2f   medium ≥ %.2f   high ≥ %.2f   max entropy (uniform): %.3f[/color]" % [
		spell_casting.aspect_library.INTENSITY_LOW_THRESHOLD, spell_casting.aspect_library.INTENSITY_MEDIUM_THRESHOLD, spell_casting.aspect_library.INTENSITY_HIGH_THRESHOLD, log(float(spell_casting.aspect_library.get_aspect_names().size()))
	])

	_output.clear()
	_output.append_text("\n".join(lines))

# ── Batch test ────────────────────────────────────────────────────────────────

func _run_batch() -> void:
	var spells: Array = _load_spell_file()
	if spells.is_empty():
		_output.clear()
		_output.append_text("No spells found at: %s" % BATCH_FILE)
		_unlock_ui("Ready")
		return

	_lock_ui("Embedding %d spells..." % spells.size())
	var results: Array = []
	for spell in spells:
		var result: Dictionary = await spell_casting.aspect_library.text_to_actualized(spell, true)
		var scores: Array = result["actualized"]
		results.append({
			"spell": spell,
			"scores": scores,
			"entropy": _entropy(scores)
		})

	results.sort_custom(func(a, b): return float(a["entropy"]) < float(b["entropy"]))
	_render_batch(results)
	_unlock_ui("Batch done — or enter a spell phrase to test manually")

func _load_spell_file() -> Array:
	if not FileAccess.file_exists(BATCH_FILE):
		return []
	var file := FileAccess.open(BATCH_FILE, FileAccess.READ)
	if file == null:
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return []
	file.close()
	var data = json.data
	if typeof(data) != TYPE_ARRAY:
		return []
	return data

func _render_batch(results: Array) -> void:
	var max_entropy: float = log(float(spell_casting.aspect_library.get_aspect_names().size()))
	var lines: Array[String] = []
	lines.append("[b]Batch results[/b] — sorted by entropy (most peaked first)")
	lines.append("[color=#888]Max entropy (uniform): %.3f[/color]" % max_entropy)
	lines.append("")

	for result in results:
		var spell: String = str(result["spell"])
		var scores: Array = result["scores"]
		var entropy: float = float(result["entropy"])
		var top = scores[0] if not scores.is_empty() else null
		var second = scores[1] if scores.size() > 1 else null

		var top_aspect: String = top.name if top != null else "?"
		var top_score: float = top.score if top != null else 0.0
		var second_aspect: String = second.name if second != null else "?"
		var second_score: float = second.score if second != null else 0.0
		var gap: float = top_score - second_score

		lines.append("entropy [b]%.3f[/b]  gap [b]+%.4f[/b]  [color=%s]%s %.4f[/color]  vs  [color=#888]%s %.4f[/color]" % [
			entropy, gap,
			_color(top_score), top_aspect, top_score,
			second_aspect, second_score
		])
		lines.append('  [i]"%s"[/i]' % spell)
		lines.append("")

	_output.clear()
	_output.append_text("\n".join(lines))

# ── Helpers ───────────────────────────────────────────────────────────────────

func _entropy(scores: Array) -> float:
	var h: float = 0.0
	for e in scores:
		var p: float = e.score
		if p > 0.0:
			h -= p * log(p)
	return h

func _bar(score: float) -> String:
	var filled: int = roundi(clampf(score / BAR_MAX, 0.0, 1.0) * BAR_WIDTH)
	return "█".repeat(filled).rpad(BAR_WIDTH, "░")

func _label(score: float) -> String:
	if score >= spell_casting.aspect_library.INTENSITY_HIGH_THRESHOLD:
		return "high"
	elif score >= spell_casting.aspect_library.INTENSITY_MEDIUM_THRESHOLD:
		return "medium"
	elif score >= spell_casting.aspect_library.INTENSITY_LOW_THRESHOLD:
		return "low"
	else:
		return "faint"

func _color(score: float) -> String:
	var rank: int = 0
	if score >= spell_casting.aspect_library.INTENSITY_HIGH_THRESHOLD:
		rank = 3
	elif score >= spell_casting.aspect_library.INTENSITY_MEDIUM_THRESHOLD:
		rank = 2
	elif score >= spell_casting.aspect_library.INTENSITY_LOW_THRESHOLD:
		rank = 1
	else:
		rank = 0
	match rank:
		3: return "#e05050"
		2: return "#d4b800"
		1: return "#50b050"
		_: return "#888888"
