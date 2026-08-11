extends Node

## Lightweight global state bag. Carried over from LOA2 as-is; fields fill in
## as their systems are ported (save slots, party, level tracking).

# Number of save slots the UI offers (Load Game screen builds one card per slot).
const SLOT_COUNT: int = 6

var current_save_slot: int = 0
var current_level: String = ""
var player_position: Vector3 = Vector3.ZERO

# Set true by "Start New Game" so the party is created fresh instead of loading
# the existing slot save. Consumed (cleared) by PartyManager.initialize_party.
var new_game_requested: bool = false
