extends StaticBody3D
class_name WallTorch

## A lit torch in a wall bracket. Clicking it takes the torch: into the first empty
## hand (top hero first), or the backpack when every hand is full. The wall plate
## stays behind.

## The parts of the model that are the torch itself: its fuel, its handle and its
## iron cage. (The one left over, torch_lp2, is the wall plate.)
const TORCH_PARTS := [
	"Model/Sketchfab_model/Collada visual scene group/torch_lp",
	"Model/Sketchfab_model/Collada visual scene group/torch_lp3",
	"Model/Sketchfab_model/Collada visual scene group/torch_lp4",
]

@export var torch: TorchData = preload("res://Wall_Torch/torch.tres")
@export var interaction_distance: float = 3.0

var _taken: bool = false
var _flicker := TorchFlicker.new()
var _steady_energy := 0.0
var _steady_range := 0.0
var _steady_color := Color.WHITE
var _light_at := Vector3.ZERO

@onready var _light: OmniLight3D = $Light

func _ready():
	_steady_energy = _light.light_energy
	_steady_range = _light.omni_range
	_steady_color = _light.light_color
	_light_at = _light.position
	add_to_group("interactable")
	add_to_group("persistent")      # WorldState saves/restores whether we were taken
	add_to_group("automap_ignore")  # the wall behind it is the wall, not this

func _process(delta: float) -> void:
	_flicker.advance(delta)
	_light.light_energy = _steady_energy * _flicker.level
	_light.omni_range = _steady_range * _flicker.reach
	_light.light_color = _flicker.tint(_steady_color)
	_light.position = _light_at + _flicker.drift

func interact():
	if _taken or torch == null:
		return

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var reach: float = interaction_distance * PlayerInteraction.PROXIMITY_MULTIPLIER
	if player and global_position.distance_to(player.global_position) > reach:
		ResourceManager.display_text("Too far away!")
		return

	var item: InventoryItem = InventoryManager.CreateItemFromData(torch)
	var holder := CharacterCard.hold_in_free_hand(get_tree(), item)
	if holder:
		ResourceManager.display_text("%s takes the torch from the wall." % holder.get_bound_character().character_name)
	elif InventoryManager.inventoryInstance.AddItem(item):
		ResourceManager.display_text("Every hand is full. The torch goes in your pack.")
	else:
		ResourceManager.display_text("Your hands and your pack are full.")
		return
	_set_taken()

func _set_taken() -> void:
	_taken = true
	for path in TORCH_PARTS:
		var part := get_node_or_null(path) as Node3D
		if part:
			part.visible = false
	$Flame.visible = false
	_light.visible = false
	set_process(false)
	collision_layer = 0
	set_meta("interaction_disabled", true)

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {"taken": _taken}

func apply_persistent_state(state: Dictionary) -> void:
	if state.get("taken", false):
		_set_taken()
#endregion
