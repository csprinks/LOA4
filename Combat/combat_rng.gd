class_name CombatRNG
extends RefCounted

## Thin wrapper around RandomNumberGenerator so every random decision in combat
## flows through one injectable, seedable source. Tests construct it with a fixed
## seed for perfectly reproducible fights; the game constructs it unseeded.

var _rng := RandomNumberGenerator.new()

# Pass a non-negative seed for deterministic output; -1 randomizes.
func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

# Inclusive integer in [from, to].
func randi_range(from: int, to: int) -> int:
	if to < from:
		return from
	return _rng.randi_range(from, to)

# True with the given percent chance (clamped to 0..100).
func chance_percent(percent: int) -> bool:
	if percent <= 0:
		return false
	if percent >= 100:
		return true
	return _rng.randi_range(1, 100) <= percent

# Uniformly pick one element, or null for an empty array.
func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[_rng.randi_range(0, array.size() - 1)]
