class_name LevelSystem
extends RefCounted

## Character leveling: XP thresholds and level-up. A RefCounted
## (not a Node): it is created with .new() and never added to the tree, so it is
## freed with its owning Character.

const XP_CHART = {
	1: {"xp_to_next": 1000, "cumulative": 0},
	2: {"xp_to_next": 1200, "cumulative": 1000},
	3: {"xp_to_next": 1400, "cumulative": 2200},
	4: {"xp_to_next": 1700, "cumulative": 3600},
	5: {"xp_to_next": 2100, "cumulative": 5300},
	6: {"xp_to_next": 2500, "cumulative": 7400},
	7: {"xp_to_next": 3000, "cumulative": 9900},
	8: {"xp_to_next": 3600, "cumulative": 12900},
	9: {"xp_to_next": 4300, "cumulative": 16500},
	10: {"xp_to_next": 5200, "cumulative": 20800},
	11: {"xp_to_next": 6200, "cumulative": 26000},
	12: {"xp_to_next": 7400, "cumulative": 32200},
	13: {"xp_to_next": 8900, "cumulative": 39600},
	14: {"xp_to_next": 10700, "cumulative": 48500},
	15: {"xp_to_next": 12800, "cumulative": 59200},
	16: {"xp_to_next": 15400, "cumulative": 72000},
	17: {"xp_to_next": 18500, "cumulative": 87400},
	18: {"xp_to_next": 22200, "cumulative": 105900},
	19: {"xp_to_next": 26600, "cumulative": 128100},
	20: {"xp_to_next": 0, "cumulative": 154700},  # Max level
}

signal level_up(old_level, new_level)
signal xp_gained(amount)

var current_level: int = 1
var current_xp: int = 0
var max_level: int = 20

func _init(starting_level: int = 1, starting_xp: int = 0) -> void:
	current_level = clamp(starting_level, 1, max_level)
	current_xp = starting_xp

	# If starting with XP, make sure the level matches.
	if starting_xp > 0:
		current_level = calculate_level_from_xp()

# Add XP and check for level up.
func add_xp(amount: int) -> void:
	if amount <= 0 or current_level >= max_level:
		return

	current_xp += amount
	xp_gained.emit(amount)

	check_level_up()

# Level up if current XP crossed a threshold.
func check_level_up() -> void:
	if current_level >= max_level:
		return

	var new_level = calculate_level_from_xp()

	if new_level > current_level:
		var old_level = current_level
		current_level = new_level
		level_up.emit(old_level, current_level)

# Calculate the level implied by the current total XP. Pure: it must NOT mutate
# current_level, or check_level_up's `new_level > current_level` comparison would
# always be false and no level-up signal would ever fire.
func calculate_level_from_xp() -> int:
	if current_xp >= XP_CHART[max_level]["cumulative"]:
		return max_level

	for level in range(max_level, 0, -1):
		if current_xp >= XP_CHART[level]["cumulative"]:
			return level

	return 1

# XP required to reach the next level.
func get_xp_for_next_level() -> int:
	if current_level >= max_level:
		return 0
	return XP_CHART[current_level + 1]["cumulative"] - current_xp

# Progress toward the next level (0-1).
func get_level_progress() -> float:
	if current_level >= max_level:
		return 1.0

	var current_level_xp = XP_CHART[current_level]["cumulative"]
	var next_level_xp = XP_CHART[current_level + 1]["cumulative"]
	var xp_needed = next_level_xp - current_level_xp
	var gained_xp = current_xp - current_level_xp

	return float(gained_xp) / float(xp_needed)
