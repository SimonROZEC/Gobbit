extends Spatial
class_name GameManager

const player_colors = [Color.red,  Color.darkorange, 
		Color.dodgerblue, Color.blueviolet,
		Color.lawngreen, Color.darkorange, 
		Color.cyan, Color.deeppink]

var leaderboard_list := []

onready var decks_manager : DecksManager = $Decks
onready var player_pointers : PlayerPointerUI = $PlayerPointers
onready var graveyard : Deck = $Decks/Graveyard
onready var card_pool := $Cards
onready var leaderboard : Leaderboard = $GUI/Leaderboard

onready var gamestate := $GameStates
onready var camera := $Pivot
onready var mouse_ray : RayCast = $MouseRay

onready var turn_light := $TurnLight


# Initializes the board scene then notice the server when it's ready
func _ready() -> void:
	# Attribute colors to players and setups signals
	var i := 0
	for player in NetworkManager.turn_order:
		player.color = player_colors[i]
		player.lost = false
		player.connect("lost", self, "_on_player_lost")
		i += 1
	
	NetworkManager.game_started = true
	decks_manager.create_graveyard()
	decks_manager.create_decks()

	if NetworkManager.is_server:
		# We use DEFERRED to ensure the _ready function is finished when
		# the _on_everyone_ready is called
		NetworkManager.net_cp.connect("scene_ready", self, "_on_everyone_ready", [], CONNECT_DEFERRED)
	
	NetworkManager.net_cp.validate("scene_ready")
	
	# TODO: Start with a white overlay


# Executed when the scene is instanced for all the players
master func _on_everyone_ready() -> void:
	rpc("start")


# Executed when a player loses the games
# Adds the player to the leaderboard
func _on_player_lost(player) -> void:
	if NetworkManager.is_server:
		# We keep the leaderboard serverside until the game finishes
		leaderboard_list.push_front(player.pseudo)
		
		# TODO: Always play death anim even on 1v1
		# We have a winner here !
		if player_left_count() == 1:
			var remaining := get_remaining_players()
			var winner = NetworkManager.players[remaining[0]]
			leaderboard_list.append(winner.pseudo)
			gamestate.rpc("transition_to", "End", {leaderboard = leaderboard_list})
		else:
			# We buffer a death animation for the next "Turn" state
			# as it's only possible to transition to "Death" state from "Turn"
			# in the game logic
			gamestate.get_node("Turn").buffer_death(player)


func init_network_checkpoints() -> void:
	var checkpoints := [
		"cards_distributed", # The cards are successfully distributed to players 
		"ready_for_first_turn", # All the decks are flipped back for the first turn
		"death_animation_done", # The death animation for a player is finished
		"card_operation_done", # All the clients have performed a card operation (merge/steal...)
		"gobbit_rule_done" # The gobbit rule animation have been performed for all clients
	]
	
	for cp in checkpoints:
		NetworkManager.net_cp.create_checkpoint(cp)


# Start the game
sync func start() -> void:
	$Pivot.move_to_player_pov(NetworkManager.me().deck.get_ref())
	
	player_pointers.init()
	
	if NetworkManager.is_server:
		init_network_checkpoints()
	
	gamestate.start("Distribute")

# BUG: Follow the count for clients (in order to simplify prediction)
# Returns the players that haven't lost yet
func get_remaining_players() -> Array:
	var playing = []
	for player in NetworkManager.turn_order:
		if not player.lost:
			playing.push_back(player.id)
	return playing


# Returns the number of player left
func player_left_count() -> int:
	var count = 0
	for player_id in NetworkManager.players:
		if not NetworkManager.players[player_id].lost:
			count += 1
	return count


# The played cards of "from" goes to the bottom of the "to" deck
sync func steal_cards(from_id: int, to_id: int) -> void:
	var checkpoint_name := "steal_" + str(from_id) + "_" + str(to_id)
	NetworkManager.net_cp.create_checkpoint(checkpoint_name)
	
	var to : Player = NetworkManager.players[to_id]
	var from : Player = NetworkManager.players[from_id]
	if to.deck == null or from.played_cards == null or from.played_cards.get_ref().empty():
		return
	
	var deck : Deck = to.deck.get_ref()
	var cards : Deck = from.played_cards.get_ref()
	
	deck.merge_deck_on_bottom(cards)
	yield(deck, "deck_merged")
	
	NetworkManager.net_cp.validate(checkpoint_name)
	
	if NetworkManager.is_server:
		yield(NetworkManager.net_cp, checkpoint_name)
	
	from.emit_signal("lost_cards")
	to.emit_signal("got_cards")
	
	# Check if the player loses the game
	if from.has_just_lost():
		from.loose()
	
	NetworkManager.net_cp.remove_checkpoint(checkpoint_name)
	

# The target player loses it's played card (they go to the graveyard)
sync func lose_cards(target_id: int) -> void:
	var checkpoint_name := "lost_" + str(target_id)
	NetworkManager.net_cp.create_checkpoint(checkpoint_name)
	
	var target : Player = NetworkManager.players[target_id]
	if target.played_cards == null or target.played_cards.get_ref().empty():
		return
	var cards : Deck = target.played_cards.get_ref()
	
	decks_manager.graveyard.merge_deck_on_top(cards)
	yield(decks_manager.graveyard, "deck_merged")
	
	NetworkManager.net_cp.validate(checkpoint_name)
	
	if NetworkManager.is_server:
		yield(NetworkManager.net_cp, checkpoint_name)
	
	target.emit_signal("lost_cards")
	
	# Check if the player loses the game
	if target.has_just_lost():
		target.loose()
		
	NetworkManager.net_cp.remove_checkpoint(checkpoint_name)
