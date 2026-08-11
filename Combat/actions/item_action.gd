class_name ItemAction
extends CombatAction

## Use a consumable (potion) on a target ally. Applies the potion's real effect
## from its type + amount, and -- when running inside the game -- consumes it from
## the shared backpack via the controller. In the logic core / tests the potion
## values are passed in directly and no inventory is touched.
##
## Potion types come from the existing Inventory enums (PotionTypes). HEALTH and
## ACTION_POINTS map to Character resources today; MANA / ENERGY have no matching
## pool yet and are no-ops until those systems exist.

var potion_type: int = PotionTypes.HEALTH
var amount: int = 0
var item = null   # optional InventoryItem, for consumption from the backpack

func _init(p_type: int = PotionTypes.HEALTH, p_amount: int = 0, p_item = null) -> void:
	display_name = "Item"
	potion_type = p_type
	amount = p_amount
	item = p_item

func ap_cost_for(_actor: Combatant) -> int:
	return CombatConstants.AP_COST_ITEM

func can_perform(actor: Combatant, target: Combatant, _encounter: Encounter) -> bool:
	if actor.action_points < ap_cost_for(actor):
		return false
	return target != null and target.is_ally   # v1: potions target allies

func execute(actor: Combatant, target: Combatant, _encounter: Encounter, controller) -> Dictionary:
	actor.spend_ap(ap_cost_for(actor))
	var effect := _apply_potion(target)

	# Consume from the shared backpack when wired to the game (no-op headless).
	if item != null:
		controller.consume_item(item)

	var result := {
		"action": "item",
		"actor": actor,
		"target": target,
		"potion_type": potion_type,
	}
	result.merge(effect)
	return result

func _apply_potion(target: Combatant) -> Dictionary:
	match potion_type:
		PotionTypes.HEALTH:
			var before := target.current_hp
			target.heal(amount)
			return {"healed": target.current_hp - before}
		PotionTypes.ACTION_POINTS:
			target.restore_ap(amount)
			return {"ap_restored": amount}
		_:
			# MANA / ENERGY: no matching resource on Character yet.
			return {"noop": true}
