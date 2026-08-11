class_name CombatConstants
extends RefCounted

## Central, tunable numbers for the whole combat system. Everything the resolver
## and turn engine would otherwise treat as a "magic number" lives here, so
## balancing never means hunting through logic. Every value is a starting point
## meant to be tuned.

# --- Hit chance (percentage model) ------------------------------------------
# hit% = HIT_BASE_PERCENT + (accuracy - evasion) * HIT_PER_POINT, clamped to
# [HIT_MIN_PERCENT, HIT_MAX_PERCENT]. accuracy = Might + Finesse,
# evasion = Finesse + Awareness (see Combatant).
const HIT_BASE_PERCENT := 75
const HIT_PER_POINT := 3
const HIT_MIN_PERCENT := 5
const HIT_MAX_PERCENT := 95

# --- Damage -----------------------------------------------------------------
# damage = weapon_roll + floor(might * MIGHT_DAMAGE_SCALE) - target_armor,
# floored at MIN_DAMAGE so a landed hit always stings a little.
const MIGHT_DAMAGE_SCALE := 0.5
const MIN_DAMAGE := 1
# Fallback weapon damage when a combatant has no weapon profile (an unarmed hero
# with nothing in the primary slot).
const UNARMED_MIN_DAMAGE := 2
const UNARMED_MAX_DAMAGE := 5

# --- Critical hits ----------------------------------------------------------
# crit% = round(Fate * CRIT_PER_FATE), clamped to [0, CRIT_MAX_PERCENT]. A crit
# multiplies pre-armor damage by CRIT_MULTIPLIER.
const CRIT_PER_FATE := 0.5
const CRIT_MAX_PERCENT := 50
const CRIT_MULTIPLIER := 2.0

# --- Action point economy ---------------------------------------------------
# AP refreshes toward max at the start of each of a combatant's turns, but
# unspent AP banks (overflow) up to AP_BANK_CAP_MULT x the combatant's max AP.
const AP_BANK_CAP_MULT := 2.0
# Default AP costs. A weapon (hero) or MonsterDefinition may override attack cost
# via its own attack profile.
const AP_COST_ATTACK := 3
const AP_COST_DEFEND := 1
const AP_COST_ITEM := 2
const AP_COST_FLEE := 2

# --- Defend -----------------------------------------------------------------
# Defending reduces incoming damage by DEFEND_DAMAGE_REDUCTION (a fraction) until
# the start of the defender's next turn.
const DEFEND_DAMAGE_REDUCTION := 0.5
const DEFEND_DURATION_TURNS := 1

# --- Flee -------------------------------------------------------------------
# Base chance for an ally to successfully flee the encounter, before modifiers.
const FLEE_BASE_PERCENT := 50

# --- Initiative -------------------------------------------------------------
# Rebuilt every round: initiative = Finesse + Awareness + randi_range(0, ROLL_MAX).
const INITIATIVE_ROLL_MAX := 20
