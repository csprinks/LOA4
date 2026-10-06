extends Node

## Shared random number source (used by inventory generation). GetRandomNumber
## returns an int when both bounds are ints, otherwise a float.

@export var deterministic_seed: int = 0
@export var use_deterministic_seed: bool = false

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if use_deterministic_seed:
		_rng.seed = deterministic_seed
	else:
		_rng.randomize()

func GetRandomNumber(min_value, max_value):
	if typeof(min_value) == TYPE_INT and typeof(max_value) == TYPE_INT:
		return _rng.randi_range(min_value, max_value)
	return _rng.randf_range(min_value, max_value)
