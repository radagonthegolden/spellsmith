extends Node
class_name OllamaClient

signal startup_finished(ok: bool)

const ERROR_OLLAMA_NOT_AVAILABLE := "ollama_not_available"
const ERROR_REQUEST_START_FAILED := "request_start_failed"
const ERROR_TRANSPORT := "transport_error"
const ERROR_HTTP := "http_error"
const ERROR_JSON_PARSE := "json_parse_error"

@export var ollama_model: String = "all-minilm"
@export var ollama_url: String = "http://127.0.0.1:11434/api/embed"
@export var ollama_health_url: String = "http://127.0.0.1:11434/api/version"

# On Windows, "ollama" usually works if it's in PATH.
# If it doesn't, set this to the full path to ollama.exe in the inspector.
@export var ollama_executable: String = "ollama"
@export var ollama_arguments: PackedStringArray = ["serve"]
@export var startup_timeout_seconds: float = 15.0
@export var startup_poll_interval_seconds: float = 0.5
@export var open_console: bool = false

var is_starting := false
var is_ready := false
var ollama_pid := -1

func _ready() -> void:
	await ensure_started()

func ensure_started() -> bool:
	if is_ready:
		return true

	if is_starting:
		await startup_finished
		return is_ready

	is_starting = true

	var already_up := await _check_server_up()
	if already_up:
		is_ready = true
		is_starting = false
		startup_finished.emit(true)
		return true

	ollama_pid = OS.create_process(ollama_executable, ollama_arguments, open_console)

	# If create_process fails, Ollama may still already be launching elsewhere,
	# so we still try polling once before giving up.
	var ok := await _wait_until_server_up(startup_timeout_seconds)

	is_ready = ok
	is_starting = false
	startup_finished.emit(ok)
	return ok

func embed(input_data: Variant) -> Dictionary:
	var ok := await ensure_started()
	if not ok:
		return _response_error(ERROR_OLLAMA_NOT_AVAILABLE)

	var http := HTTPRequest.new()
	add_child(http)

	var payload := {
		"model": ollama_model,
		"input": input_data
	}

	var err := http.request(
		ollama_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)

	if err != OK:
		http.queue_free()
		return _response_error(ERROR_REQUEST_START_FAILED)

	var response = await http.request_completed
	http.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Ollama transport error")
		return _response_error(ERROR_TRANSPORT)

	if response_code != 200:
		push_error("Ollama HTTP error: " + str(response_code))
		return _response_error(ERROR_HTTP)

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("Failed to parse Ollama JSON response")
		return _response_error(ERROR_JSON_PARSE)

	var data: Dictionary = json.data
	var embeddings: Array = data.get("embeddings", [])
	return _response_ok(embeddings)

func _check_server_up() -> bool:
	var http := HTTPRequest.new()
	add_child(http)

	var err := http.request(ollama_health_url)
	if err != OK:
		http.queue_free()
		return false

	var response = await http.request_completed
	http.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]

	return result == HTTPRequest.RESULT_SUCCESS and response_code == 200

func _wait_until_server_up(timeout_seconds: float) -> bool:
	var elapsed := 0.0

	while elapsed < timeout_seconds:
		var ok := await _check_server_up()
		if ok:
			return true

		await get_tree().create_timer(startup_poll_interval_seconds).timeout
		elapsed += startup_poll_interval_seconds

	return false

func _response_ok(embeddings: Array) -> Dictionary:
	return {
		"ok": true,
		"embeddings": embeddings,
		"error": ""
	}

func _response_error(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"embeddings": [],
		"error": error_code
	}
