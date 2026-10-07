extends Node3D
class_name PlayerTorchLight

## The light of the torches the party carries. Every lit torch held in a hero's
## hand burns down (the seconds it has left are the item's `charges`); the one with
## the most left lights the way, dimming as it burns, and a spent torch is swapped
## for its burnt-out husk. A torch in the backpack is stowed: no light, no burning.
## Time stands still for torches during combat and while the game is paused.

const ENERGY_FLOOR := 0.18     # share of its full brightness a torch gives at its last gasp
const RANGE_FLOOR := 0.45      # ... and of its full reach
const SPUTTER_BELOW := 0.1     # with this share of its life left, it starts to gutter
const SPUTTER_UNREST := 2.2    # how much wilder the flicker is at the very end
const RESPONSE := 4.0          # how quickly the light follows a torch being raised or stowed
# Held up and a little ahead, on the right, so walls in front catch the light.
const HELD_AT := Vector3(0.3, 1.0, -0.25)

var _light: OmniLight3D
var _second := 0.0             # burn time not yet taken off the torches' whole seconds
var _flicker := TorchFlicker.new()
var _steady := 0.0             # the light's energy before the flicker is laid over it

func _init():
	name = "TorchLight"

func _ready():
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = HELD_AT
	_light.light_energy = 0.0
	_light.light_specular = 0.0   # no hot spot on the wall the party is facing
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)

func _process(delta: float) -> void:
	var combat := get_node_or_null("/root/CombatManager")
	if not (combat and combat.has_method("is_active") and combat.is_active()):
		_second += delta
	var tick := _second >= 1.0
	if tick:
		_second -= 1.0

	var best: TorchData = null
	var best_left := 0.0
	for card in CharacterCard.party_cards(get_tree()):
		for slot in card.hand_slots():
			var item := slot.GetData()
			var torch := (item._resourceData as TorchData) if item else null
			if torch == null or item.charges <= 0:
				continue
			if tick:
				item.charges -= 1
				if item.charges <= 0:
					_burn_out(card, slot, torch)
					continue
				slot.slot_changed.emit()   # the card saves the new time left on its hero
			var left := clampf((item.charges - _second) / maxf(1.0, torch.burn_seconds), 0.0, 1.0)
			if best == null or left > best_left:
				best = torch
				best_left = left
	_shine(best, best_left, delta)

# Ease the light toward what the best torch gives - full strength when fresh,
# fading steadily to a dim glow as it burns down - then lay the flame's flicker
# over it (after the easing, which would otherwise smooth the flicker away).
func _shine(torch: TorchData, left: float, delta: float) -> void:
	var target := 0.0
	var unrest := 1.0
	if torch:
		target = torch.light_energy * lerpf(ENERGY_FLOOR, 1.0, left)
		if left < SPUTTER_BELOW:
			unrest = lerpf(SPUTTER_UNREST, 1.0, left / SPUTTER_BELOW)
	if torch:
		_steady = lerpf(_steady, target, minf(1.0, delta * RESPONSE))
	else:
		_steady = move_toward(_steady, 0.0, delta * RESPONSE)
	_flicker.advance(delta, unrest)
	_light.light_energy = _steady * _flicker.level
	_light.position = HELD_AT + _flicker.drift
	if torch:
		_light.light_color = _flicker.tint(torch.light_color)
		_light.omni_range = torch.light_range * lerpf(RANGE_FLOOR, 1.0, left) * _flicker.reach
	_light.visible = _steady > 0.005

func _burn_out(card: CharacterCard, slot: InventoryContainer, torch: TorchData) -> void:
	var husk: InventoryItem = InventoryManager.CreateItemFromData(torch.burnt_out)
	slot.SetData(husk if husk else slot.ClearData())
	GameTextBox.display_text("%s's torch gutters and goes out." % card.get_bound_character().character_name)
