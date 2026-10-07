class_name SkillBook
extends RefCounted

## Everything one hero has bought with Attribute Points: a rank per skill id, raw
## attribute points, the free picks still owed from creation, and the total sunk
## so far. Holds all the purchase
## rules, so the character sheet can run them against a draft copy and only write
## the result back to the Character on confirm.
##
## Rules: skills in a line are bought left to right. The first FREE_PICKS skills
## are free; after that a new skill costs its position plus 1 per
## OWNED_PER_SURCHARGE skills already owned. Upgrading costs the rank being
## bought (rank 2 costs 2, rank 3 costs 3). Every rank adds the skill's position
## to its line's attribute. A raw +1 to any attribute, with no skill attached,
## costs a flat ATTRIBUTE_POINT_COST.

var ranks: Dictionary = {}   # skill id -> rank (1..SkillTree.MAX_RANK); absent = not owned
var raw_points: Dictionary = {}   # attribute -> raw +1s bought; absent = none
var free_picks_left: int = SkillTree.FREE_PICKS
var points_spent: int = 0


func rank_of(skill: SkillDefinition) -> int:
	return int(ranks.get(skill.id, 0))


func owned_count() -> int:
	return ranks.size()


# True when `skill` is unowned and next in its line.
func is_reachable(skill: SkillDefinition) -> bool:
	if rank_of(skill) > 0:
		return false
	var required := SkillTree.prerequisite(skill)
	return required == null or rank_of(required) > 0


# Attribute Points the next step on `skill` costs (buying it, or its next rank).
# -1 when there is no next step: maxed, or not yet reachable.
func next_cost(skill: SkillDefinition) -> int:
	var rank := rank_of(skill)
	if rank >= SkillTree.MAX_RANK:
		return -1
	if rank > 0:
		return rank + 1
	if not is_reachable(skill):
		return -1
	if free_picks_left > 0:
		return 0
	return skill.position + owned_count() / SkillTree.OWNED_PER_SURCHARGE


func can_advance(skill: SkillDefinition, available_points: int) -> bool:
	var cost := next_cost(skill)
	return cost >= 0 and cost <= available_points


# Buy `skill` or its next rank. Returns false (changing nothing) if not allowed.
func advance(skill: SkillDefinition, available_points: int) -> bool:
	if not can_advance(skill, available_points):
		return false
	var cost := next_cost(skill)
	if rank_of(skill) == 0 and free_picks_left > 0:
		free_picks_left -= 1
	points_spent += cost
	ranks[skill.id] = rank_of(skill) + 1
	return true


func raw_points_in(attribute: String) -> int:
	return int(raw_points.get(attribute, 0))


func can_buy_attribute(available_points: int) -> bool:
	return available_points >= SkillTree.ATTRIBUTE_POINT_COST


# Buy a raw +1 to `attribute`. Returns false (changing nothing) if not allowed.
func buy_attribute(attribute: String, available_points: int) -> bool:
	if not can_buy_attribute(available_points) or not Character.STAT_NAMES.has(attribute):
		return false
	points_spent += SkillTree.ATTRIBUTE_POINT_COST
	raw_points[attribute] = raw_points_in(attribute) + 1
	return true


# True when nothing at all has been bought or picked.
func is_blank() -> bool:
	return ranks.is_empty() and raw_points.is_empty()


# Total bonus the owned skills and raw points give `attribute`.
func stat_bonus(attribute: String) -> int:
	var bonus := raw_points_in(attribute)
	for skill in SkillTree.line(attribute):
		bonus += skill.position * rank_of(skill)
	return bonus


# Full respec: forget every skill and raw point, refunding all points and the
# free picks.
func reset() -> void:
	ranks = {}
	raw_points = {}
	free_picks_left = SkillTree.FREE_PICKS
	points_spent = 0


func copy_from(other: SkillBook) -> void:
	ranks = other.ranks.duplicate()
	raw_points = other.raw_points.duplicate()
	free_picks_left = other.free_picks_left
	points_spent = other.points_spent


func duplicate_book() -> SkillBook:
	var book := SkillBook.new()
	book.copy_from(self)
	return book


func equals(other: SkillBook) -> bool:
	if free_picks_left != other.free_picks_left or points_spent != other.points_spent:
		return false
	if ranks.size() != other.ranks.size():
		return false
	for attribute in Character.STAT_NAMES:
		if raw_points_in(attribute) != other.raw_points_in(attribute):
			return false
	for id in ranks:
		if int(other.ranks.get(id, 0)) != int(ranks[id]):
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"ranks": ranks.duplicate(),
		"raw_points": raw_points.duplicate(),
		"free_picks_left": free_picks_left,
		"points_spent": points_spent,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	free_picks_left = int(data.get("free_picks_left", SkillTree.FREE_PICKS))
	points_spent = int(data.get("points_spent", 0))
	var saved_raw = data.get("raw_points", {})
	if typeof(saved_raw) == TYPE_DICTIONARY:
		for attribute in Character.STAT_NAMES:
			if int(saved_raw.get(attribute, 0)) > 0:
				raw_points[attribute] = int(saved_raw[attribute])
	var saved = data.get("ranks", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return
	# Drop ids that no longer exist so a renamed skill can't leave a ghost rank.
	for id in saved:
		if SkillTree.get_skill(str(id)) != null:
			ranks[str(id)] = clampi(int(saved[id]), 1, SkillTree.MAX_RANK)
