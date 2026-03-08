extends VBoxContainer
class_name BattlerUI

@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_text: Label = $HealthText

func set_name_text(value: String) -> void:
	name_label.text = value

func set_health(current: int, max_value: int) -> void:
	health_bar.max_value = float(max_value)
	health_bar.value = float(current)
	health_text.text = "HP: %d / %d" % [current, max_value]
