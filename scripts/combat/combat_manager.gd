extends Node
class_name CombatManager

signal combat_finished(player_won: bool)

@export var spell_base_damage: int = 15
@export var matching_aspect_bonus_damage: int = 10
@export var spells_file_path: String = "res://data/spells.json"
@export var score_tier_1_threshold: float = 0.40
@export var score_tier_1_bonus: int = 2
@export var score_tier_2_threshold: float = 0.55
@export var score_tier_2_bonus: int = 5
@export var score_tier_3_threshold: float = 0.70
@export var score_tier_3_bonus: int = 8
@export var score_tier_4_threshold: float = 0.85
@export var score_tier_4_bonus: int = 12

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler

@onready var player_ui: BattlerUI = $"../OuterMargin/Panel/Content/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../OuterMargin/Panel/Content/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../OuterMargin/Panel/Content/TurnRow/TurnLabel"
@onready var battle_log: RichTextLabel = $"../OuterMargin/Panel/Content/LoreText"
@onready var combat_hud: HBoxContainer = $"../OuterMargin/Panel/Content/CombatHUD"
@onready var turn_row: HBoxContainer = $"../OuterMargin/Panel/Content/TurnRow"

var enemy_spell_pool: Array[Dictionary] = []
var enemy_current_aspect: String = ""
var active := false

func _ready() -> void:
	enemy_spell_pool = _load_enemy_spells()
	_set_ui_visible(false)

func damage_opponent(amount: int) -> bool:
	return opponent.take_damage(amount)

func damage_player(amount: int) -> bool:
	return player.take_damage(amount)

func start_battle(enemy_name: String = "Enemy") -> void:
	active = true
	player.health = player.max_health
	opponent.health = opponent.max_health
	player.display_name = "You"
	opponent.display_name = enemy_name
	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()
	turn_label.text = "Turn: Player"
	_set_ui_visible(true)
	_log_line("")
	_log_line("A hostile presence condenses into the manuscript.")
	_enemy_attune_without_cast()

func _on_spell_scored(sorted_scores: Array, text: String, cast_multiplier: float) -> void:
	if not active:
		return

	turn_label.text = "Turn: Player"
	var top_entry: Dictionary = sorted_scores[0]
	var top_aspect: String = str(top_entry["name"])
	var top_score: float = float(top_entry["score"])
	var tier_bonus := _compute_score_tier_bonus(top_score)
	var damage := spell_base_damage + tier_bonus
	if tier_bonus > 0:
		_log_line("Strong alignment: +" + str(tier_bonus) + " damage (score " + str(snappedf(top_score, 0.01)) + ").")

	if top_aspect == enemy_current_aspect:
		damage += matching_aspect_bonus_damage
		_log_line("Aspect match: " + top_aspect + " (+" + str(matching_aspect_bonus_damage) + " damage).")

	var final_damage := maxi(1, int(round(float(damage) * cast_multiplier)))
	if cast_multiplier < 1.0:
		_log_line("Spell fatigue multiplier: x" + str(snappedf(cast_multiplier, 0.01)))

	_log_line("You cast \"" + text + "\" for " + str(final_damage) + " damage.")
	var opponent_died := damage_opponent(final_damage)
	_update_health_ui()
	if opponent_died:
		turn_label.text = "Turn: Victory"
		_log_line("Enemy falls. Victory.")
		_finish_battle(true)
		return

	turn_label.text = "Turn: Opponent"
	var enemy_spell := _enemy_select_spell()
	var enemy_damage := int(enemy_spell["damage"])
	_log_line("Enemy attunes to " + enemy_current_aspect + ", casting " + str(enemy_spell["name"]) + " and dealing " + str(enemy_damage) + " damage.")
	var player_died := damage_player(enemy_damage)
	_update_health_ui()
	if player_died:
		turn_label.text = "Turn: Defeat"
		_log_line("You were defeated.")
		_finish_battle(false)
		return

	turn_label.text = "Turn: Player"
	_log_line("Your turn.")

func _compute_score_tier_bonus(top_score: float) -> int:
	if top_score >= score_tier_4_threshold:
		return score_tier_4_bonus
	if top_score >= score_tier_3_threshold:
		return score_tier_3_bonus
	if top_score >= score_tier_2_threshold:
		return score_tier_2_bonus
	if top_score >= score_tier_1_threshold:
		return score_tier_1_bonus
	return 0


func _update_health_ui() -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func _log_line(message: String) -> void:
	print(message)
	battle_log.append_text(message + "\n")
	battle_log.scroll_to_line(maxi(0, battle_log.get_line_count() - 1))

func _enemy_select_spell() -> Dictionary:
	var enemy_spell: Dictionary = enemy_spell_pool[randi() % enemy_spell_pool.size()]
	enemy_current_aspect = str(enemy_spell["aspect"])
	return enemy_spell

func _enemy_attune_without_cast() -> void:
	var enemy_spell: Dictionary = enemy_spell_pool[randi() % enemy_spell_pool.size()]
	enemy_current_aspect = str(enemy_spell["aspect"])
	_log_line("Enemy starts attuned to " + enemy_current_aspect + ".")

func _load_enemy_spells() -> Array[Dictionary]:
	var file := FileAccess.open(spells_file_path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	json.parse(content)

	var out: Array[Dictionary] = []
	var spells: Array = json.data
	for entry in spells:
		var spell: Dictionary = entry
		out.append(spell)

	return out

func _finish_battle(player_won: bool) -> void:
	active = false
	_set_ui_visible(false)
	combat_finished.emit(player_won)

func _set_ui_visible(value: bool) -> void:
	combat_hud.visible = value
	turn_row.visible = value
