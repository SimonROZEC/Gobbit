extends Spatial
class_name GameManager

onready var decks_manager : DecksManager = $Decks
onready var graveyard : Deck = $Decks/Graveyard
onready var card_pool := $Cards

onready var gamestate := $GameStates
onready var camera := $Pivot

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		pass


func init_network_checkpoints() -> void:
	var checkpoints := [
		"cards_distributed", # The cards are successfully distributed to players 
		"ready_for_first_turn" # All the decks are flipped back for the first turn
	]
	
	for cp in checkpoints:
		NetworkManager.net_cp.create_checkpoint(cp)


# Start the game
sync func start() -> void:
#	Engine.time_scale = 3 # TODO: remove when debugging finished 
	$Pivot.move_to_player_pov(NetworkManager.me().deck.get_ref())

	if NetworkManager.is_server:
		init_network_checkpoints()

	gamestate.start("Distribute")


# Returns the players that haven't lost yet
func get_playing_players() -> Array:
	var playing = []
	for player_id in NetworkManager.players:
		if not NetworkManager.players[player_id].lost:
			playing.push_back(player_id)
	return playing
