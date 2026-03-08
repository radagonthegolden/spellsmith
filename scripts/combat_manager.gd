extends Node
class_name CombatManager

@export var enemy_retaliation_damage: int = 10
@export var spell_base_damage: int = 5
@export var spell_scale_damage: int = 30

@onready var player: Battler = $PlayerBattler
@onready var opponent: Battler = $OpponentBattler

@onready var player_ui: BattlerUI = $"../OuterMargin/Panel/Content/CombatHUD/PlayerCard"
@onready var opponent_ui: BattlerUI = $"../OuterMargin/Panel/Content/CombatHUD/EnemyCard"
@onready var turn_label: Label = $"../OuterMargin/Panel/Content/TurnRow/TurnLabel"
@onready var battle_log: RichTextLabel = $"../OuterMargin/Panel/Content/LoreText"

func _ready() -> void:
	player.display_name = "You"
	opponent.display_name = "Enemy"
	player_ui.set_name_text(player.display_name)
	opponent_ui.set_name_text(opponent.display_name)
	_update_health_ui()
	turn_label.text = "Turn: Player"
	battle_log.text = ""
	_log_line("Battle begins.")

func damage_opponent(amount: int) -> bool:
	return opponent.take_damage(amount)

func damage_player(amount: int) -> bool:
	return player.take_damage(amount)

func _on_spell_scored(sorted_scores: Array, text: String) -> void:
	if sorted_scores.is_empty():
		push_error("Spell resolved without scored aspects")
		return

	turn_label.text = "Turn: Player"
	var damage := _compute_spell_damage(sorted_scores)
	_log_line("You cast \"" + text + "\" for " + str(damage) + " damage.")
	var opponent_died := damage_opponent(damage)
	_update_health_ui()
	if opponent_died:
		turn_label.text = "Turn: Victory"
		_log_line("Enemy falls. Victory.")
		return

	turn_label.text = "Turn: Opponent"
	_log_line("Enemy retaliates for " + str(enemy_retaliation_damage) + " damage.")
	var player_died := damage_player(enemy_retaliation_damage)
	_update_health_ui()
	if player_died:
		turn_label.text = "Turn: Defeat"
		_log_line("You were defeated.")
		return

	turn_label.text = "Turn: Player"
	_log_line("Your turn.")

func _compute_spell_damage(sorted_scores: Array) -> int:
	var top_entry: Dictionary = sorted_scores[0]
	var top_score := float(top_entry["score"])
	return maxi(1, spell_base_damage + int(round(top_score * float(spell_scale_damage))))

func _update_health_ui() -> void:
	player_ui.set_health(player.health, player.max_health)
	opponent_ui.set_health(opponent.health, opponent.max_health)

func _log_line(message: String) -> void:
	battle_log.text += message + "\n"
	battle_log.scroll_to_line(maxi(0, battle_log.get_line_count() - 1))
