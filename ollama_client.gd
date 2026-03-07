extends Node
class_name OllamaClient

@export var ollama_model: String = "all-minilm"
@export var ollama_url: String = "http://127.0.0.1:11434/api/embed"

func embed(input_data: Variant) -> Dictionary:
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
		return {
			"ok": false,
			"embeddings": [],
			"error": "request_start_failed"
		}

	var response = await http.request_completed
	http.queue_free()

	var result = response[0]
	var response_code = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"embeddings": [],
			"error": "transport_error"
		}

	if response_code != 200:
		return {
			"ok": false,
			"embeddings": [],
			"error": "http_error"
		}

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return {
			"ok": false,
			"embeddings": [],
			"error": "json_parse_error"
		}

	var data = json.data
	var embeddings = data.get("embeddings", [])

	if typeof(embeddings) != TYPE_ARRAY:
		return {
			"ok": false,
			"embeddings": [],
			"error": "missing_embeddings"
		}

	return {
		"ok": true,
		"embeddings": embeddings,
		"error": ""
	}
