class_name AttackAction
extends CombatAction

## A basic weapon attack against one enemy. AP cost comes from the actor's attack
## profile (weapon or monster). Honors row reach (melee -> front enemy row only)
## and offers the ally Fortune-reroll seam on a miss.

func _init() -> void:
	display_name = "Attack"

func ap_cost_for(actor: Combatant) -> int:
	return int(actor.get_attack_profile().get("ap_cost", CombatConstants.AP_COST_ATTACK))

func can_perform(actor: Combatant, target: Combatant, encounter: Encounter) -> bool:
	if actor.action_points < ap_cost_for(actor):
		return false
	if target == null or target.is_downed:
		return false
	if target.is_ally == actor.is_ally:
		return false   # no friendly fire
	return encounter.can_reach(actor, target)

func execute(actor: Combatant, target: Combatant, encounter: Encounter, controller) -> Dictionary:
	actor.spend_ap(ap_cost_for(actor))
	var result: Dictionary = controller.resolver.resolve_attack(actor, target)

	# Fortune reroll seam: an ally who misses may spend a Fortune Point to reroll
	# the attack. The controller's reroll_decider decides (interactive in-game,
	# scripted/never in tests).
	if not result["hit"] and actor.is_ally and actor.fortune_points > 0:
		if controller.should_reroll(actor, target, result):
			actor.spend_fortune(1)
			result = controller.resolver.resolve_attack(actor, target)
			result["fortune_rerolled"] = true

	result["action"] = "attack"
	return result
