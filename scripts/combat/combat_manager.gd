extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

const INTENSITY_LOW_THRESHOLD: float = 0.12
const INTENSITY_MEDIUM_THRESHOLD: float = 0.18
const INTENSITY_HIGH_THRESHOLD: float = 0.21

@export var enemies_file_path: String = "res://data/enemies.json"
@export var progress_aspect_count: int = 3
@export var context_max_value: int = 6

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler

@onready var player_ui: BattlerUI = $"../HiddenUi/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../HiddenUi/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../HiddenUi/TurnRow/TurnLabel"
@onready var battle_log: RichTextLabel = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/LoreFrame/LoreMargin/LoreText"
@onready var fight_notes_frame: PanelContainer = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame"
@onready var fight_notes: RichTextLabel = $"../OuterMargin/ShadowPanel/Panel/Content/PageMargin/PageColumns/FightNotesFrame/FightNotesMargin/FightNotes"
@onready var combat_hud: HBoxContainer = $"../HiddenUi/CombatHUD"
@onready var turn_row: HBoxContainer = $"../HiddenUi/TurnRow"
@onready var ollama_client: OllamaClient = $"../spell/OllamaClient"
@onready var aspect_library: AspectLibrary = $"../spell/AspectLibrary"

var enemy_definitions_by_name: Dictionary = {}
var active: bool = false
var current_enemy: Dictionary = {}
var descriptor_vector: Array = []
var context_aspect_totals: Dictionary = {}
var current_aspect_scores: Array = []
var prepared_enemy_spell: Dictionary = {}
var last_player_spell_name: String = ""
var last_player_resonance: float = 0.0
var last_player_profile: Array = []
var last_context_update: Dictionary = {}
var last_defense_summary: String = ""

func _ready() -> void:
	enemy_definitions_by_name = _load_enemy_definitions()
	_set_ui_visible(false)
	fight_notes.text = ""

func start_battle(enemy_name: String = "Enemy") -> void:
	var enemy: Dictionary = enemy_definitions_by_name[enemy_name]
	var descriptor: Array = await _build_descriptor_vector(enemy)
	if descriptor.is_empty():
		push_error("Failed to build descriptor vector for enemy: " + enemy_name)
		return

	active = true
	player.reset_health()
	player.display_name = "You"
	opponent.display_name = enemy_name
	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()
	current_enemy = enemy
	descriptor_vector = descriptor
	_reset_context_aspect_totals()
	current_aspect_scores = []
	prepared_enemy_spell = {}
	last_player_spell_name = ""
	last_player_resonance = 0.0
	last_player_profile = []
	last_context_update = {}
	last_defense_summary = "The duel has just begun."
	turn_label.text = "Turn: Player"
	_set_ui_visible(true)
	_log_line("")
	_log_line("A hostile presence condenses into the manuscript.")
	_score_context()
	_log_progress()
	await _prepare_enemy_spell()
	_refresh_fight_notes()

func _on_spell_encoded(spell_embedding: Array, text: String) -> void:
	if not active:
		return

	turn_label.text = "Turn: Player"
	var spell_aspect_scores: Array = aspect_library.score_embedding(spell_embedding, text)
	var resonance: float = SemanticScorer.cosine_similarity(spell_embedding, descriptor_vector)
	var effective_resonance: float = _get_effective_resonance(resonance)
	last_context_update = _apply_spell_to_context(spell_aspect_scores, effective_resonance)

	var player_profile: Array = _build_full_intensity_profile(spell_aspect_scores)
	last_player_spell_name = text
	last_player_resonance = effective_resonance
	last_player_profile = player_profile
	var displayed_player_profile: Array = _filter_display_profile(player_profile, prepared_enemy_spell.get("_intensity_profile", []))
	_log_line("You cast \"" + text + "\". Resonance " + str(snappedf(effective_resonance, 0.01)) + ". Pattern: " + _format_intensity_profile(displayed_player_profile) + ".")

	if _meets_conditions(current_enemy["player_victory_conditions"]):
		turn_label.text = "Turn: Victory"
		last_defense_summary = "Your spell completed the victory condition before the enemy attack could land."
		_refresh_fight_notes()
		_log_line("The context settles into a shape that breaks " + opponent.display_name + ". Victory.")
		_finish_battle(true)
		return

	_resolve_enemy_spell_collision(player_profile)
	_log_progress()
	_refresh_fight_notes()

	if player.health <= 0:
		turn_label.text = "Turn: Defeat"
		_log_line("Your body gives out before the context yields. Defeat.")
		_finish_battle(false)
		return

	if _meets_conditions(current_enemy["player_loss_conditions"]):
		turn_label.text = "Turn: Defeat"
		_log_line(opponent.display_name + " draws the context into its own design. Defeat.")
		_finish_battle(false)
		return

	turn_label.text = "Turn: Player"
	await _prepare_enemy_spell()
	_refresh_fight_notes()

func _log_line(message: String) -> void:
	print(message)
	battle_log.append_text(message + "\n")
	battle_log.scroll_to_line(maxi(0, battle_log.get_line_count() - 1))

func _load_enemy_definitions() -> Dictionary:
	var file := FileAccess.open(enemies_file_path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	json.parse(content)

	var out: Dictionary = {}
	var enemies: Array = json.data
	for entry in enemies:
		var enemy: Dictionary = entry
		out[str(enemy["name"])] = enemy

	return out

func _build_descriptor_vector(enemy: Dictionary) -> Array:
	var descriptions: Array = enemy["descriptor_sentences"]
	var result: Dictionary = await ollama_client.embed(descriptions)
	if not result.get("ok", false):
		push_error("Failed to embed enemy descriptor")
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		push_error("Enemy descriptor produced no embeddings")
		return []

	return SemanticScorer.average_embeddings(embeddings)

func _get_effective_resonance(raw_resonance: float) -> float:
	var min_resonance: float = float(current_enemy.get("min_descriptor_resonance", 0.0))
	var max_resonance: float = float(current_enemy.get("max_descriptor_resonance", 1.0))
	var clamped_raw: float = clampf(raw_resonance, 0.0, 1.0)
	return lerpf(min_resonance, max_resonance, clamped_raw)

func _reset_context_aspect_totals() -> void:
	context_aspect_totals.clear()
	for aspect_name in aspect_library.get_aspect_names():
		context_aspect_totals[str(aspect_name)] = 0

func _apply_spell_to_context(spell_aspect_scores: Array, resonance: float) -> Dictionary:
	var context_update: Dictionary = _build_context_update(spell_aspect_scores, resonance)
	for aspect_name in context_aspect_totals.keys():
		var current_value: int = int(context_aspect_totals[aspect_name])
		var update_value: int = int(context_update.get(aspect_name, 0))
		context_aspect_totals[aspect_name] = _update_context_aspect_value(current_value, update_value)

	_score_context()
	return context_update

func _score_context() -> void:
	var scores: Array = []
	for aspect_name in context_aspect_totals.keys():
		scores.append({
			"name": aspect_name,
			"score": int(context_aspect_totals[aspect_name])
		})

	scores.sort_custom(func(a, b): return a["score"] > b["score"])
	current_aspect_scores = scores

func _log_progress() -> void:
	return

func _meets_conditions(conditions: Array) -> bool:
	for condition in conditions:
		var aspect_name: String = str(condition["aspect"])
		var required_rank: int = _intensity_label_to_rank(str(condition["intensity"]))
		var current_rank: int = _get_context_intensity_rank(aspect_name)
		if current_rank < required_rank:
			return false
	return true

func _prepare_enemy_spell() -> void:
	var spell_pool: Array = _get_enemy_spell_pool()
	if spell_pool.is_empty():
		push_error("Enemy has no local spells: " + str(current_enemy.get("name", "Unknown Enemy")))
		return

	prepared_enemy_spell = spell_pool[randi() % spell_pool.size()]
	if not prepared_enemy_spell.has("_aspect_scores"):
		var enemy_spell_embedding: Array = await _embed_enemy_spell(prepared_enemy_spell)
		prepared_enemy_spell["_aspect_scores"] = aspect_library.score_embedding(enemy_spell_embedding, str(prepared_enemy_spell["name"]))
	prepared_enemy_spell["_intensity_profile"] = _build_primary_intensity_profile(prepared_enemy_spell["_aspect_scores"])
	_log_line(opponent.display_name + " casts " + str(prepared_enemy_spell["name"]) + ". Pattern: " + _format_intensity_profile(prepared_enemy_spell["_intensity_profile"]) + ".")

func _get_enemy_spell_pool() -> Array:
	if not current_enemy.has("spells"):
		return []

	return current_enemy["spells"]

func _resolve_enemy_spell_collision(player_profile: Array) -> void:
	if prepared_enemy_spell.is_empty():
		return

	var enemy_profile: Array = prepared_enemy_spell["_intensity_profile"]
	var damage: int = int(prepared_enemy_spell["damage"])
	if _player_nullifies_enemy_spell(enemy_profile, player_profile):
		last_defense_summary = "Your spell matched the enemy pattern and nullified the attack."
		_log_line("Your spell matches " + str(prepared_enemy_spell["name"]) + " strongly enough to nullify it.")
		return

	var player_died: bool = player.take_damage(damage)
	_update_health_ui()
	last_defense_summary = str(prepared_enemy_spell["name"]) + " broke through and dealt " + str(damage) + " damage."
	_log_line(str(prepared_enemy_spell["name"]) + " breaks through. You take " + str(damage) + " damage.")
	if player_died:
		_log_line("Your health is spent.")

func _update_health_ui() -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func _embed_enemy_spell(enemy_spell: Dictionary) -> Array:
	var result: Dictionary = await ollama_client.embed(str(enemy_spell["name"]))
	if not result.get("ok", false):
		push_error("Failed to embed enemy spell: " + str(enemy_spell["name"]))
		return []

	var embeddings: Array = result.get("embeddings", [])
	if embeddings.is_empty():
		push_error("Enemy spell produced no embedding: " + str(enemy_spell["name"]))
		return []

	return embeddings[0]

func _build_intensity_profile(scores: Array) -> Array:
	return _build_primary_intensity_profile(scores)

func _build_primary_intensity_profile(scores: Array) -> Array:
	var profile: Array = []
	var limit: int = mini(1, scores.size())
	for i in range(limit):
		var entry: Dictionary = scores[i]
		var score: float = float(entry["score"])
		profile.append({
			"name": str(entry["name"]),
			"score": score,
			"intensity_rank": _score_to_intensity_rank(score),
			"intensity_label": _score_to_intensity_label(score)
		})
	return profile

func _build_full_intensity_profile(scores: Array) -> Array:
	var profile: Array = []
	for entry in scores:
		var score: float = float(entry["score"])
		profile.append({
			"name": str(entry["name"]),
			"score": score,
			"intensity_rank": _score_to_intensity_rank(score),
			"intensity_label": _score_to_intensity_label(score)
		})
	return profile

func _score_to_intensity_rank(score: float) -> int:
	if score >= INTENSITY_HIGH_THRESHOLD:
		return 3
	if score >= INTENSITY_MEDIUM_THRESHOLD:
		return 2
	if score >= INTENSITY_LOW_THRESHOLD:
		return 1
	return 0

func _score_to_intensity_label(score: float) -> String:
	var intensity_rank: int = _score_to_intensity_rank(score)
	if intensity_rank == 3:
		return "high"
	if intensity_rank == 2:
		return "medium"
	if intensity_rank == 1:
		return "low"
	return "faint"

func _intensity_label_to_rank(label: String) -> int:
	if label == "high":
		return 3
	if label == "medium":
		return 2
	if label == "low":
		return 1
	return 0

func _format_intensity_profile(profile: Array) -> String:
	var parts: Array = []
	for entry in profile:
		parts.append(str(entry["name"]) + " " + str(entry["intensity_label"]))
	return ", ".join(parts)

func _format_context_profile() -> String:
	var parts: Array = []
	var limit: int = mini(progress_aspect_count, current_aspect_scores.size())
	for i in range(limit):
		var entry: Dictionary = current_aspect_scores[i]
		var aspect_name: String = str(entry["name"])
		var intensity_label: String = _context_value_to_intensity_label(int(entry["score"]))
		parts.append(aspect_name + " " + intensity_label)
	return ", ".join(parts)

func _get_context_intensity_rank(aspect_name: String) -> int:
	for entry in current_aspect_scores:
		if str(entry["name"]) == aspect_name:
			return _context_value_to_intensity_rank(int(entry["score"]))
	return 0

func _build_context_update(spell_aspect_scores: Array, resonance: float) -> Dictionary:
	var update: Dictionary = {}
	for aspect_name in aspect_library.get_aspect_names():
		update[str(aspect_name)] = 0

	for entry in spell_aspect_scores:
		var aspect_name: String = str(entry["name"])
		var effective_score: float = resonance * float(entry["score"])
		update[aspect_name] = _score_to_intensity_rank(effective_score)

	return update

func _update_context_aspect_value(current_value: int, update_value: int) -> int:
	var delta: int = 0
	if update_value == 0:
		if current_value <= 1:
			delta = 0
		elif current_value <= 3:
			delta = -1
		else:
			delta = -2
	elif update_value == 1:
		if current_value <= 3:
			delta = 1
		else:
			delta = 0
	else:
		if current_value <= 1:
			delta = 2
		else:
			delta = 1

	return clampi(current_value + delta, 0, context_max_value)

func _context_value_to_intensity_rank(value: int) -> int:
	if value >= 6:
		return 3
	if value >= 4:
		return 2
	if value >= 2:
		return 1
	return 0

func _context_value_to_intensity_label(value: int) -> String:
	var intensity_rank: int = _context_value_to_intensity_rank(value)
	if intensity_rank == 3:
		return "high"
	if intensity_rank == 2:
		return "medium"
	if intensity_rank == 1:
		return "low"
	return "faint"

func _format_context_update(update: Dictionary) -> String:
	var parts: Array = []
	for aspect_name in aspect_library.get_aspect_names():
		var update_value: int = int(update.get(str(aspect_name), 0))
		if update_value <= 0:
			continue
		parts.append("%s +%d" % [str(aspect_name), update_value])

	if parts.is_empty():
		return "No aspect gained pressure."

	return ", ".join(parts)

func _player_nullifies_enemy_spell(enemy_profile: Array, player_profile: Array) -> bool:
	if enemy_profile.is_empty() or player_profile.is_empty():
		return false

	var enemy_entry: Dictionary = enemy_profile[0]
	for player_entry in player_profile:
		if str(enemy_entry["name"]) != str(player_entry["name"]):
			continue
		return int(player_entry["intensity_rank"]) >= int(enemy_entry["intensity_rank"])

	return false

func _filter_display_profile(player_profile: Array, enemy_profile: Array) -> Array:
	if player_profile.is_empty():
		return []

	var displayed: Array = []
	var top_entry: Dictionary = player_profile[0]
	displayed.append(top_entry)

	if enemy_profile.is_empty():
		return displayed

	var enemy_entry: Dictionary = enemy_profile[0]
	var enemy_aspect_name: String = str(enemy_entry["name"])
	var enemy_required_rank: int = int(enemy_entry["intensity_rank"])

	for player_entry in player_profile:
		if str(player_entry["name"]) != enemy_aspect_name:
			continue
		if int(player_entry["intensity_rank"]) < enemy_required_rank:
			continue
		if str(top_entry["name"]) == enemy_aspect_name:
			return displayed
		displayed.append(player_entry)
		return displayed

	return displayed

func _refresh_fight_notes() -> void:
	if not active:
		fight_notes.text = ""
		return

	var lines: Array[String] = []
	lines.append("[b]Fight Notes[/b]")
	lines.append("")
	lines.append("[b]Health[/b]")
	lines.append("You: %d/%d" % [player.health, player.max_health])
	lines.append("")
	lines.append("[b]Enemy Spell[/b]")
	if prepared_enemy_spell.is_empty():
		lines.append("None prepared.")
	else:
		lines.append(str(prepared_enemy_spell["name"]))
		lines.append("Pattern: " + _format_intensity_profile(prepared_enemy_spell["_intensity_profile"]))
	lines.append("")
	lines.append("[b]Your Last Spell[/b]")
	if last_player_spell_name.is_empty():
		lines.append("None yet.")
	else:
		lines.append(last_player_spell_name)
		lines.append("Pattern: " + _format_intensity_profile(_filter_display_profile(last_player_profile, prepared_enemy_spell.get("_intensity_profile", []))))
		lines.append("Resonance: " + str(snappedf(last_player_resonance, 0.01)))
		lines.append("Context Update: " + _format_context_update(last_context_update))
	lines.append("")
	lines.append("[b]Context[/b]")
	lines.append(_format_context_profile())
	lines.append("")
	lines.append("[b]Last Resolution[/b]")
	lines.append(last_defense_summary)

	fight_notes.clear()
	fight_notes.append_text("\n".join(lines))

func _finish_battle(player_won: bool) -> void:
	active = false
	current_enemy = {}
	descriptor_vector.clear()
	context_aspect_totals.clear()
	current_aspect_scores.clear()
	prepared_enemy_spell = {}
	last_player_spell_name = ""
	last_player_resonance = 0.0
	last_player_profile = []
	last_context_update = {}
	last_defense_summary = ""
	fight_notes.text = ""
	_set_ui_visible(false)
	combat_finished.emit(player_won)

func _set_ui_visible(value: bool) -> void:
	combat_hud.visible = false
	turn_row.visible = false
	fight_notes_frame.visible = value
