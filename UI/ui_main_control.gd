extends Control

## HUD root controller. Collects the hero cards and keeps them bound to the
## active party, updating whenever PartyManager reports a change.

var _cards: Array = []

func _ready() -> void:
	var cards_container := get_node_or_null("%Cards")
	if cards_container:
		for child in cards_container.get_children():
			if child is CharacterCard:
				_cards.append(child)

	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager:
		if not party_manager.party_updated.is_connected(_on_party_updated):
			party_manager.party_updated.connect(_on_party_updated)
		_on_party_updated()

func _on_party_updated() -> void:
	var party_manager := get_node_or_null("/root/PartyManager")
	if not party_manager:
		return

	for i in _cards.size():
		_cards[i].set_character(party_manager.get_character(i))
