extends StaticBody3D
class_name ItemPickup

## An item lying in the level. Clicking it (or pressing interact beside it) puts it
## in the party's backpack.

@export var item: InventoryData
@export var interaction_distance: float = 3.0

var _taken: bool = false

func _ready():
	add_to_group("interactable")
	add_to_group("persistent")      # WorldState saves/restores whether we were taken
	add_to_group("automap_ignore")  # a thing on the floor is not a wall
	ItemHighlight.apply(self)

func interact():
	if _taken or item == null:
		return

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var reach: float = interaction_distance * PlayerInteraction.PROXIMITY_MULTIPLIER
	if player and global_position.distance_to(player.global_position) > reach:
		ResourceManager.display_text("Too far away!")
		return

	if InventoryManager.AddItem(item) == 0:
		ResourceManager.display_text("Your inventory is full.")
		return

	ResourceManager.display_text("You picked up the %s." % item.itemName)
	_set_taken()

# The node stays in the level (hidden and unclickable) rather than being freed, so
# WorldState still finds it and remembers that it is gone.
func _set_taken() -> void:
	_taken = true
	visible = false
	collision_layer = 0
	set_meta("interaction_disabled", true)

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {"taken": _taken}

func apply_persistent_state(state: Dictionary) -> void:
	if state.get("taken", false):
		_set_taken()
#endregion
