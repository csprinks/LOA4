extends Node

## GDScript replacement for LOA2's C# RandomNumberManager. Same public API
## (GetRandomNumber) so the inventory generation code that calls it needs no
## changes. Returns an int when both bounds are ints, otherwise a float -
## matching the two C# overloads.

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
