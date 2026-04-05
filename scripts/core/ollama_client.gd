extends Node
class_name OllamaClient

signal startup_finished(ok: bool)

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

func embed(input_data: Variant) -> Array:
	var ok := await ensure_started()
	assert(ok, "Ollama not available")

	var http := HTTPRequest.new()
	add_child(http)

	var err := http.request(
		ollama_url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify({"model": ollama_model, "input": input_data})
	)
	if err != OK:
		http.queue_free()
	assert(err == OK, "Ollama request failed to start")

	var response = await http.request_completed
	http.queue_free()

	assert(response[0] == HTTPRequest.RESULT_SUCCESS, "Ollama transport error")
	assert(response[1] == 200, "Ollama HTTP error: " + str(response[1]))

	var json := JSON.new()
	assert(json.parse(response[3].get_string_from_utf8()) == OK, "Failed to parse Ollama JSON response")

	return json.data.get("embeddings", [])

func embed_many(input_data: Variant, context: String = "Embedding") -> Array:
	var embeddings: Array = await embed(input_data)
	assert(not embeddings.is_empty(), context + " produced no embeddings")
	return embeddings

func embed_one(input_data: Variant, context: String = "Embedding") -> Array:
	var embeddings: Array = await embed_many(input_data, context)
	return embeddings[0]

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

