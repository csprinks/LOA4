class_name MonsterDefinition
extends Resource

## Authorable data for one monster TYPE. Create these as .tres files under
## Combat/Monsters/ (or build them in code via MonsterLibrary). A Combatant wraps
## an instance of this to fight, and several Combatants can share one definition
## (a group of identical Kobolds). Deliberately lighter than the hero Character:
## no equipment slots, no XP chart, no favor points -- just the numbers combat
## reads, plus the rewards granted when the monster dies.

@export var display_name: String = "Monster"
@export var max_hp: int = 200
@export var max_action_points: int = 5

# Combat stats -- the subset of the hero six-stat model that combat actually
# uses. Accuracy = Might + Finesse; Evasion = Finesse + Awareness; crit scales
# off Fate (see Combatant / CombatResolver).
@export var might: int = 10
@export var finesse: int = 10
@export var awareness: int = 10
@export var fate: int = 10
@export var armor: int = 0

# Attack profile.
@export var damage_min: int = 2
@export var damage_max: int = 5
@export var is_ranged: bool = false            # ranged monsters can hit any hero
@export var attack_ap_cost: int = 3

# --- Placement --------------------------------------------------------------
# Default row for this monster in an encounter (0 = front). The encounter can
# override per-spawn; this is just the authoring default.
@export var default_row: int = 0

# --- Rewards (granted to the party on death) --------------------------------
@export var xp_reward: int = 25
@export var crowns_reward: int = 5
# Optional loot: InventoryData resources dropped on death, added to the shared
# backpack by the controller's reward step.
@export var loot: Array[InventoryData] = []

# --- Presentation (used later by the battle scene; ignored by the logic core) -
# Full battler art, shown on the enemy card during a fight.
@export var sprite: Texture2D
# Small square portrait (~84x84) for the turn-order strip. Falls back to `sprite`
# if left unset.
@export var portrait: Texture2D
