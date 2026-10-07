class_name TorchFlicker
extends RefCounted

## The restless light of a burning torch. Three layers of noise - a slow sway, a
## quick flutter and a fine crackle - plus the odd gust that knocks the flame flat
## for a moment before it recovers. Call advance() every frame, then read:
##   level   brightness, as a multiple of the light's steady energy
##   reach   range, as a multiple of its steady range
##   drift   where the flame has wandered to, to add to the light's position
##   ember   0..1, how far the colour has sunk toward a deep ember red

const SWAY_SPEED := 1.3
const FLUTTER_SPEED := 8.0
const CRACKLE_SPEED := 21.0
const SWAY_DEPTH := 0.16
const FLUTTER_DEPTH := 0.24
const CRACKLE_DEPTH := 0.10
const GUST_DEPTH := 0.5        # how much of the light a full gust takes
const GUST_RECOVERY := 5.0     # how fast the flame comes back (per second)
const GUST_EVERY := Vector2(2.0, 7.0)   # seconds between gusts, least and most
const DRIFT := 0.07            # how far the light wanders, in world units
const EMBER_COLOR := Color(1.0, 0.42, 0.14)

var level := 1.0
var reach := 1.0
var drift := Vector3.ZERO
var ember := 0.0

var _noise := FastNoiseLite.new()
var _clock := 0.0
var _gust := 0.0
var _next_gust := 0.0

func _init() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.0
	_clock = randf() * 100.0   # so neighbouring torches don't pulse together
	_next_gust = randf_range(GUST_EVERY.x, GUST_EVERY.y)

## `unrest` scales the whole effect: 1 is a steady burn, 2 a guttering flame.
func advance(delta: float, unrest: float = 1.0) -> void:
	_clock += delta
	_next_gust -= delta * unrest
	if _next_gust <= 0.0:
		_gust = randf_range(0.5, 1.0)
		_next_gust = randf_range(GUST_EVERY.x, GUST_EVERY.y)
	_gust = move_toward(_gust, 0.0, delta * GUST_RECOVERY * maxf(_gust, 0.15))

	var sway := _noise.get_noise_1d(_clock * SWAY_SPEED)
	var flutter := _noise.get_noise_1d(_clock * FLUTTER_SPEED + 100.0)
	var crackle := _noise.get_noise_1d(_clock * CRACKLE_SPEED + 200.0)
	var wobble := (sway * SWAY_DEPTH + flutter * FLUTTER_DEPTH + crackle * CRACKLE_DEPTH) * unrest
	var dip := _gust * GUST_DEPTH * minf(unrest, 1.6)

	level = clampf(1.0 + wobble - dip, 0.12, 1.5)
	reach = clampf(1.0 + (sway * 0.05 + flutter * 0.04) * unrest - dip * 0.3, 0.6, 1.2)
	drift = Vector3(
		_noise.get_noise_1d(_clock * 2.1 + 300.0),
		_noise.get_noise_1d(_clock * 2.7 + 400.0),
		_noise.get_noise_1d(_clock * 1.9 + 500.0)) * DRIFT * unrest
	ember = clampf(_gust * 0.8 + maxf(0.0, -wobble) * 1.5, 0.0, 1.0)

## The light's colour right now: `base` when the flame is high, redder as it dips.
func tint(base: Color) -> Color:
	return base.lerp(EMBER_COLOR, ember * 0.6)
