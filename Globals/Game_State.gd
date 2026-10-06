extends Node

## Lightweight global state bag (save slots, party, level tracking).

# Number of save slots the UI offers (Load Game screen builds one card per slot).
const SLOT_COUNT: int = 6

var current_save_slot: int = 0
var current_level: String = ""
var player_position: Vector3 = Vector3.ZERO

# Set true by "Start New Game" so the party is created fresh instead of loading
# the existing slot save. Consumed (cleared) by PartyManager.initialize_party.
var new_game_requested: bool = false

# Level Editor hand-offs. `editor_test_module` is the id of the module being
# test-played from the editor ("" during a normal game); while it is set the
# system menu offers "Back to Level Editor". `editor_open_module` tells the editor
# which module to reopen when it loads (consumed by the editor).
var editor_test_module: String = ""
var editor_open_module: String = ""
