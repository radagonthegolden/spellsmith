extends Control

const _OllamaScript: GDScript = preload("res://scripts/core/ollama_client.gd")
const _AspectScript: GDScript = preload("res://scripts/world/aspects_library.gd")

const THRESHOLD_LOW: float = 0.12
const THRESHOLD_MEDIUM: float = 0.18
const THRESHOLD_HIGH: float = 0.21
const BAR_WIDTH: int = 20
const BAR_MAX: float = 0.35
const BATCH_FILE: String = "res://data/debug_spells.json"

var _ollama: OllamaClient
var _aspects: AspectLibrary
var _status: Label
var _output: RichTextLabel
var _input: LineEdit
var _button_test: Button
var _button_batch: Button
var _ready_for_input: bool = false

func _ready() -> void:
	_build_nodes()
	_build_ui()
	_initialize()

func _build_nodes() -> void:
	_ollama = _OllamaScript.new()
	_ollama.name = "OllamaClient"
	add_child(_ollama)

	_aspects = _AspectScript.new()
	_aspects.name = "AspectLibrary"
	_aspects.ollama_client_path = NodePath("../OllamaClient")
	add_child(_aspects)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for prop in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(prop, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Spell Aspect Debugger"
	vbox.add_child(title)

	_status = Label.new()
	_status.text = "Initializing..."
	vbox.add_child(_status)

	var row := HBoxContainer.new()
	vbox.add_child(row)

	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Type a spell phrase and press Enter or Test..."
	_input.editable = false
	_input.text_submitted.connect(_on_cast)
	row.add_child(_input)

	_button_test = Button.new()
	_button_test.text = "Test"
	_button_test.disabled = true
	_button_test.pressed.connect(func(): _on_cast(_input.text))
	row.add_child(_button_test)

	_button_batch = Button.new()
	_button_batch.text = "Reload Batch"
	_button_batch.disabled = true
	_button_batch.pressed.connect(func(): _run_batch())
	row.add_child(_button_batch)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.bbcode_enabled = true
	_output.scroll_active = true
	vbox.add_child(_output)

func _initialize() -> void:
	await _ollama.ensure_started()
	_status.text = "Embedding aspects, please wait..."
	var ok: bool = await _aspects.initialize()
	if not ok:
		_status.text = "ERROR: aspect initialization failed"
		return
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

	var embedding: Array = await _ollama.embed_one(text, "Debug spell")
	if embedding.is_empty():
		_unlock_ui("ERROR: embedding failed")
		return

	var raw_scores: Array = _aspects.score_embedding(embedding)
	var final_scores: Array = _aspects.score_embedding(embedding, text)

	var penalty: float = 1.0
	if not raw_scores.is_empty() and not final_scores.is_empty():
		var r: float = float(raw_scores[0]["score"])
		if r > 0.0:
			penalty = float(final_scores[0]["score"]) / r

	_render_single(text, raw_scores, final_scores, penalty)
	_unlock_ui("Ready — enter a spell phrase to test")

func _render_single(spell: String, raw_scores: Array, final_scores: Array, penalty: float) -> void:
	var raw_map: Dictionary = {}
	for e in raw_scores:
		raw_map[str(e["name"])] = float(e["score"])

	var lines: Array[String] = []
	lines.append('[b]"%s"[/b]' % spell)
	lines.append("Length penalty: [b]%.3f[/b]   entropy: [b]%.3f[/b]" % [
		penalty, _entropy(final_scores)
	])
	lines.append("")

	for e in final_scores:
		var name: String = str(e["name"])
		var fs: float = float(e["score"])
		var rs: float = raw_map.get(name, 0.0)
		var bar: String = _bar(fs)
		var color: String = _color(fs)
		var label: String = _label(fs)
		lines.append("[color=%s][b]%-6s[/b][/color]  %s  raw %.4f → final %.4f   [i]%s[/i]" % [
			color, label.to_upper(), bar, rs, fs, name
		])

	lines.append("")
	lines.append("[color=#888]Thresholds: low ≥ %.2f   medium ≥ %.2f   high ≥ %.2f   max entropy (uniform): %.3f[/color]" % [
		THRESHOLD_LOW, THRESHOLD_MEDIUM, THRESHOLD_HIGH, log(float(_aspects.get_aspect_names().size()))
	])

	_output.clear()
	_output.append_text("\n".join(lines))

# ── Batch test ────────────────────────────────────────────────────────────────

func _run_batch() -> void:
	if not _ready_for_input:
		return

	var spells: Array = _load_spell_file()
	if spells.is_empty():
		_output.clear()
		_output.append_text("No spells found at: %s" % BATCH_FILE)
		_unlock_ui("Ready")
		return

	_lock_ui("Embedding %d spells..." % spells.size())
	var embeddings: Array = await _ollama.embed_many(spells, "Batch debug")

	if embeddings.is_empty() or embeddings.size() != spells.size():
		_unlock_ui("ERROR: batch embedding failed")
		return

	_status.text = "Scoring..."
	var results: Array = []
	for i in range(spells.size()):
		var spell: String = str(spells[i])
		var scores: Array = _aspects.score_embedding(embeddings[i], spell)
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
	var max_entropy: float = log(float(_aspects.get_aspect_names().size()))
	var lines: Array[String] = []
	lines.append("[b]Batch results[/b] — sorted by entropy (most peaked first)")
	lines.append("[color=#888]Max entropy (uniform): %.3f[/color]" % max_entropy)
	lines.append("")

	for result in results:
		var spell: String = str(result["spell"])
		var scores: Array = result["scores"]
		var entropy: float = float(result["entropy"])
		var top: Dictionary = scores[0] if not scores.is_empty() else {}
		var second: Dictionary = scores[1] if scores.size() > 1 else {}

		var top_aspect: String = str(top.get("name", "?"))
		var top_score: float = float(top.get("score", 0.0))
		var second_aspect: String = str(second.get("name", "?"))
		var second_score: float = float(second.get("score", 0.0))
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
		var p: float = float(e["score"])
		if p > 0.0:
			h -= p * log(p)
	return h

func _bar(score: float) -> String:
	var filled: int = roundi(clampf(score / BAR_MAX, 0.0, 1.0) * BAR_WIDTH)
	return "█".repeat(filled).rpad(BAR_WIDTH, "░")

func _label(score: float) -> String:
	if score >= THRESHOLD_HIGH: return "high"
	if score >= THRESHOLD_MEDIUM: return "medium"
	if score >= THRESHOLD_LOW: return "low"
	return "faint"

func _color(score: float) -> String:
	if score >= THRESHOLD_HIGH: return "#e05050"
	if score >= THRESHOLD_MEDIUM: return "#d4b800"
	if score >= THRESHOLD_LOW: return "#50b050"
	return "#888888"
