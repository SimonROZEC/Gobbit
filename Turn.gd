extends GameState
class_name TurnGameState
# The state when a player can put a card on the top of his deck
# to play

# The states has different handler for all the actions the players can do
# - Place a card if it's the player's turn
# - Attack the deck of another player
# - Protect it's own deck
# - Play the "Gobbit !" by hitting the graveyard

var turn_offset := 0 # Defines which player starts the game

var turn_count : int = 0
var player_turn : int

onready var mouse_ray : RayCast = $MouseRay

onready var place_handler := $PlaceHandler
onready var attack_handler := $AttackHandler
onready var defense_handler := $DefenseHandler
onready var gobbit_handler := $GobbitHandler
onready var spirit_handler := $SpiritHandler

# The protected cards during the current turn (reset every turn)
var protections = []
	
# BUG: When 5 or more player, mouse tracking seems to be broken

func enter(params := {}) -> void:
	assert("turn" in params)
	
	# TODO: find a cleaner way to handle turn offset
	# BUG: skip turn if the player has no cards in it's deck 
	
	protections = []
	turn_count = params.turn
	var player_index : int = (turn_count) % NetworkManager.player_count
	player_turn = NetworkManager.turn_order[player_index].id
	
	if NetworkManager.peer_id == player_turn:
		var player : Player = NetworkManager.players[player_turn]
		if player.lost or \
				(player.deck != null and player.deck.get_ref().empty()):
			#TODO: Check if game end !
			next_turn()
			return
		
	place_handler.init()
	mouse_ray.enabled = true
	mouse_ray.global_transform.origin = (gm.get_node("Pivot/Camera") as Camera).global_transform.origin


func physics_process(delta: float) -> void:
	var position2D = get_viewport().get_mouse_position()
	var p3 = (gm.get_node("Pivot/Camera") as Camera).project_ray_normal(position2D)
	mouse_ray.cast_to = p3 * 100
	
	place_handler.update()


# Defines what action handler should handle the input depending on
# what player did the action and what deck he interacted with
func unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != BUTTON_LEFT:
		# Only interact with left button
		return
	
	var collider := mouse_ray.get_collider()
	
	# TODO: detect clics on graveyard for Gobbit! rule
	
	if event.pressed:
		if gm.decks_manager.is_played_cards(collider):
			var played_cards := collider as Deck
			if NetworkManager.me().lost: # If the player is a spirit
				spirit_handler.handle_spirit_attack(played_cards)
			elif NetworkManager.me().played_cards.get_ref() == played_cards: # Defensive action
				defense_handler.handle_defense()
			else: # Offensive action
				attack_handler.handle_attack(played_cards)
				pass
		elif gm.decks_manager.is_graveyard(collider):
			if not NetworkManager.me().lost:
				gobbit_handler.handle_gobbit()
	
	if NetworkManager.peer_id != player_turn or NetworkManager.me().lost:
		return
	
	# Placing action
	if event.pressed:
		if is_turn_deck(collider):
			place_handler.rpc("start_dragging")
	elif place_handler.dragging:
		print("dragging release from ", player_turn)
		if is_turn_played_cards(collider):
			var card : Card = place_handler.dragged_card.get_ref()
			place_handler.rpc("finalize_dragging")
			spirit_handler.rpc("reset") # Reset the protected cards
			# Play again if the placed card is a gorilla
			if card.front_type != CardFactory.CardFrontType.GORILLA:
				# BUG: Crash if the gorilla is the last card of the player
				next_turn()
			elif NetworkManager.me().deck.get_ref().empty():
				rpc("lose_cards", NetworkManager.peer_id)
				next_turn()
		else:
			place_handler.rpc("cancel_dragging")


func next_turn() -> void:
	gm.gamestate.rpc("transition_to", "Turn", {turn=(turn_count + 1)})


func exit() -> void:
	mouse_ray.enabled = false


# Returns the deck of the player whose turn it is.
func get_turn_deck() -> Deck:
	return NetworkManager.players[player_turn].deck.get_ref()


# Returns the played cards of the player whose turn it is.
func get_turn_played_cards() -> Deck:
	return NetworkManager.players[player_turn].played_cards.get_ref()


# Returns the top cards of the played cards for all players
func get_all_top_cards() -> Dictionary:
	var top_cards := {}
	for player_id in gm.get_playing_players():
		var played_cards : Deck = NetworkManager.players[player_id].played_cards.get_ref()
		if played_cards.empty():
			top_cards[player_id] = null
		else:
			top_cards[player_id] = played_cards.get_card_on_top()
	return top_cards


# Returns true if the deck is that of the player whose turn it is.
func is_turn_deck(deck : Deck) -> bool:
	return deck == NetworkManager.players[player_turn].deck.get_ref()


# Returns true if the played cards deck is that of the player whose turn it is.
func is_turn_played_cards(deck : Deck) -> bool:
	return deck == NetworkManager.players[player_turn].played_cards.get_ref()



# The played cards of "from" goes to the bottom of the "to" deck
# TODO: split steal & protect functions
sync func steal_cards(from_id: int, to_id: int) -> void:
	var to : Player = NetworkManager.players[to_id]
	var from : Player = NetworkManager.players[from_id]
	if to.deck == null or from.played_cards == null:
		return
	
	var deck : Deck = to.deck.get_ref()
	var cards : Deck = from.played_cards.get_ref()
	
	# If the steal is a protection
	if from_id == to_id:
		protections.push_back(cards.get_card_on_top())
	
	deck.merge_deck_on_bottom(cards)
	yield(deck, "deck_merged")
	
	# Check if the player loses the game
	if from.has_just_lost():
		from.loose()


# The target player loses it's played card (they go to the graveyard)
sync func lose_cards(target_id: int) -> void:
	var target : Player = NetworkManager.players[target_id]
	if target.played_cards == null:
		return
	var cards : Deck = target.played_cards.get_ref()
	gm.decks_manager.graveyard.merge_deck_on_top(cards)
	yield(gm.decks_manager.graveyard, "deck_merged")
	
	protections.push_back(cards.get_card_on_top())
	
	# Check if the player loses the game
	if target.has_just_lost():
		target.loose()
