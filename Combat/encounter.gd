class_name Encounter
extends RefCounted

## The board state for one fight: the ally Combatants (from the party) and the
## enemy Combatants arranged in rows. Owns targeting / reachability queries and
## the WIN / LOSE / FLED status. Pure data + queries; the CombatController drives
## the turns.
##
## Rows: heroes have NO rows (the party is a flat list). Monsters do. Melee --
## from either side -- can only reach the frontmost living monster row; when that
## row is wiped, the next becomes the front. Ranged weapons and (later) spells can
## reach any monster row. Enemy melee always reaches heroes, since heroes have no
## rows to hide behind.

enum Status { ONGOING, WIN, LOSE, FLED }

var allies: Array = []      # Array[Combatant]
var enemies: Array = []     # Array[Combatant], each carrying a .row
var status: int = Status.ONGOING

func _init(ally_combatants: Array = [], enemy_combatants: Array = []) -> void:
	allies = ally_combatants
	enemies = enemy_combatants

#region Roster queries
func living_allies() -> Array:
	return allies.filter(func(c): return not c.is_downed)

func living_enemies() -> Array:
	return enemies.filter(func(c): return not c.is_downed and c.current_hp > 0)

func all_combatants() -> Array:
	return allies + enemies

func all_allies_down() -> bool:
	return living_allies().is_empty()

func all_enemies_dead() -> bool:
	return living_enemies().is_empty()
#endregion

#region Targeting / reach
# The frontmost enemy row that still has a living monster (0 when none remain).
func front_enemy_row() -> int:
	var front := -1
	for e in living_enemies():
		if front < 0 or e.row < front:
			front = e.row
	return front if front >= 0 else 0

# Can `actor` reach `target` for a basic (weapon) attack right now?
#  - Heroes have no rows: any living hero is reachable by enemy melee.
#  - Enemies: ranged attackers reach any row; melee reaches only the front row.
func can_reach(actor: Combatant, target: Combatant) -> bool:
	if target == null or target.is_downed:
		return false
	if target.is_ally:
		return true
	var profile := actor.get_attack_profile()
	if profile.get("is_ranged", false):
		return true
	return target.row == front_enemy_row()

# Living enemies `actor` may currently target with a basic attack.
func reachable_enemies(actor: Combatant) -> Array:
	return living_enemies().filter(func(e): return can_reach(actor, e))
#endregion

#region Status
# Recompute WIN/LOSE from the board. FLED is sticky (set by a successful Flee).
func refresh_status() -> void:
	if status == Status.FLED:
		return
	if all_enemies_dead():
		status = Status.WIN
	elif all_allies_down():
		status = Status.LOSE
	else:
		status = Status.ONGOING
#endregion
