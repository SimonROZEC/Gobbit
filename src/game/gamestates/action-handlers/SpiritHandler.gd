extends ActionHandler

# Handles an attack from the current client on the target deck
master func handle_spirit_attack(target_id: int) -> void:
	var target : Deck = NetworkManager.players[target_id].played_cards.get_ref()
	if target.empty():
		return
	
	if check_spirit_attack_valid(target):
		turn.gm.rpc("lose_cards", target_id)
		turn.gm.camera.rpc("shake")
	else: # If this is an error, the card, is protected
		turn.gm.rpc("steal_cards", target_id, target_id)


# Checks if an attack from deck to the target deck is valid
func check_spirit_attack_valid(target: Deck) -> bool:
	var top_target := target.get_card_on_top()
	var all_cards := turn.top_cards
	
	# If there is not spirit at the moment
	if NetworkManager.player_count == turn.gm.player_left_count():
		return false
	
	for pid in all_cards:
		var card : Card = all_cards[pid]
		if card == top_target or card == null:
			continue
		if card.colors == top_target.colors and \
				card.front_type == top_target.front_type:
			return true
	return false
