extends Node
class_name Battler

@export var max_health: int = 100
@export var start_health: int = 100
@export var display_name: String = "Name"

var health: int = 0

func _ready() -> void:
	health = clampi(start_health, 0, max_health)

func take_damage(amount: int) -> bool:
	health -= amount
	if health <= 0:
		health = 0
	return health == 0
