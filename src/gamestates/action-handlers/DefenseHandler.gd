extends ActionHandler


# Handles an attack from the current client on the target deck
master func handle_defense(defenser_id: int) -> void:
	var deck : Deck = NetworkManager.players[defenser_id].played_cards.get_ref()
	if deck.empty() or \
			turn.gobbit_handler.check_gobbit_active():
		return
	
	if check_defense_valid(defenser_id):
		turn.rpc("steal_cards", defenser_id, defenser_id)
	else:
		turn.rpc("lose_cards", defenser_id)


# Checks if a defense is justified
# TODO: Handle spirit defense (add a "lost" property in players)
func check_defense_valid(defenser_id: int) -> bool:
	var deck : Deck = NetworkManager.players[defenser_id].played_cards.get_ref()
	var self_card := deck.get_card_on_top()
	var all_cards := turn.get_all_top_cards()
	
	# If there is a possible spirit attack on the cards
	if turn.spirit_handler.check_spirit_attack_valid(deck):
		Debug.println("> SPIRIT PROTECTION !")
		return true
	
	# NOTE: can be refactored using is_valid_attack from AttackHandler
	for player_id in all_cards:
		if player_id == defenser_id or \
				all_cards[player_id] == null:
			continue
		if all_cards[player_id].eats(self_card):
			return true
	return false
