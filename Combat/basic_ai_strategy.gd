class_name BasicAIStrategy
extends AIStrategy

## v1 enemy behavior: attack a random living hero. If it can't afford an attack,
## Defend to bank AP for next turn. Deliberately simple -- the seam exists so this
## can grow into threat/low-HP targeting or per-monster scripts later.

func choose_action(actor: Combatant, encounter: Encounter, controller) -> Dictionary:
	var attack := AttackAction.new()
	var targets := encounter.living_allies()
	if targets.is_empty():
		return {}

	if actor.action_points >= attack.ap_cost_for(actor):
		var target = controller.rng.pick(targets)
		return {"action": attack, "target": target}

	# Not enough AP to attack: defend (also banks AP toward next turn).
	var defend := DefendAction.new()
	if defend.can_perform(actor, null, encounter):
		return {"action": defend, "target": null}
	return {}
