extends RichTextLabel
class_name ManuscriptWriter

const CHAR_SPEED_MS: float = 15.0
const FADE_DURATION_MS: float = 200.0

var _segments: Array = []
var _next_start_time_msec: float = 0.0
var _last_rendered_bbcode: String = ""

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	_render_current_state()

func append_animated(content: String) -> void:
	if content.is_empty():
		return

	var now: float = float(Time.get_ticks_msec())
	var start_time: float = maxf(now, _next_start_time_msec)
	var end_time: float = start_time + maxf(0.0, float(content.length() - 1)) * CHAR_SPEED_MS + FADE_DURATION_MS

	_segments.append({
		"content": content,
		"start_time": start_time,
		"end_time": end_time
	})
	_next_start_time_msec = end_time
	set_process(true)
	_render_current_state()

func clear_and_reset() -> void:
	_segments.clear()
	_next_start_time_msec = 0.0
	_last_rendered_bbcode = ""
	set_process(false)
	clear()

func _render_current_state() -> void:
	var now: float = float(Time.get_ticks_msec())
	var rendered_bbcode: String = _build_rendered_bbcode(now)

	if rendered_bbcode != _last_rendered_bbcode:
		_last_rendered_bbcode = rendered_bbcode
		clear()
		append_text(rendered_bbcode)
		scroll_to_line(maxi(0, get_line_count() - 1))

	if not _has_pending_animation(now):
		set_process(false)

func _build_rendered_bbcode(now: float) -> String:
	var parts: Array[String] = []
	var base_color: Color = get_theme_color("default_color", "RichTextLabel")

	for segment in _segments:
		var start_time: float = float(segment["start_time"])
		var end_time: float = float(segment["end_time"])
		var content: String = str(segment["content"])

		if now <= start_time:
			continue

		if now >= end_time:
			parts.append(_escape_bbcode_text(content))
			continue

		parts.append(_build_partial_segment_bbcode(content, now - start_time, base_color))

	return "".join(parts)

func _build_partial_segment_bbcode(content: String, elapsed_msec: float, base_color: Color) -> String:
	var parts: Array[String] = []

	for i in range(content.length()):
		var reveal_at: float = float(i) * CHAR_SPEED_MS
		var alpha: float = clampf((elapsed_msec - reveal_at) / FADE_DURATION_MS, 0.0, 1.0)
		if alpha <= 0.0:
			break

		var ch: String = content.substr(i, 1)
		if ch == "\n":
			parts.append("\n")
			continue

		var escaped_char: String = _escape_bbcode_text(ch)
		if alpha >= 1.0:
			parts.append(escaped_char)
			continue

		var color_with_alpha := Color(base_color.r, base_color.g, base_color.b, alpha)
		parts.append("[color=#%s]%s[/color]" % [color_with_alpha.to_html(true), escaped_char])

	return "".join(parts)

func _has_pending_animation(now: float) -> bool:
	for segment in _segments:
		if float(segment["end_time"]) > now:
			return true
	return false

func _escape_bbcode_text(input_text: String) -> String:
	return input_text.replace("[", "[lb]").replace("]", "[rb]")
