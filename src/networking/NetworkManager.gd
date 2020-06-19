extends Node

signal player_list_changed # Triggers when a players joins or quits the room
signal connection_succeeded # Triggers when the player is connected to the server
signal connection_failed # Triggers when the players fails to connect to the server
signal game_started # Triggers when the game starts
signal server_closed # Triggers when the server is closed by the host

const NetworkCheckpoints := preload("res://src/networking/NetworkCheckpoints.gd")

const player_colors = [Color.red,  Color.darkorange, 
		Color.dodgerblue, Color.blueviolet,
		Color.lawngreen, Color.darkorange, 
		Color.cyan, Color.deeppink]

var pseudo := ""
var peer_id : int
var is_server : bool
var players := {}
var game_started := false
var player_count := 0

var net_cp : NetworkCheckpoints
# Players that have instantiated the scene for the game

var turn_order := []

func _ready():
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self,"_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected")
	get_tree().connect("connection_failed", self, "_connection_failed")
	get_tree().connect("server_disconnected", self, "_connection_failed")


# Called when a new player connects to the room
# Sends the client pseudo to the new player
func _player_connected(id) -> void:
	print("NEW CONNECTION: " + str(id))
	rpc_id(id, "register_player", pseudo)


func _player_disconnected(id):
	print("player disconnected : " + str(id))
	if game_started : # Disconnection during game
		if is_server:
			pass # TODO: Handler server disconnection
		else:
			pass # TODO: Handler player disconnection
	else:
		unregister_player(id)


# Host a new room
func host_room(pseudo) -> void:
	self.pseudo = pseudo
	var host = NetworkedMultiplayerENet.new()
	host.create_server(Globals.NETWORK_PORT, Globals.MAX_PLAYERS)
	get_tree().set_refuse_new_network_connections(false)
	get_tree().set_network_peer(host)
	# Add the server to it's local player list
	peer_id = get_tree().get_network_unique_id()
	players[peer_id] = Player.new(peer_id, pseudo)
	is_server = true


# Join a room hosted on a certain ip address
func join_room(pseudo, ip) -> void:
	self.pseudo = pseudo
	var client = NetworkedMultiplayerENet.new()
	client.create_client(ip, Globals.NETWORK_PORT)
	get_tree().set_network_peer(client)
	is_server = false


# Called when the client is connected to the server
func _connected():
	# Add the client to it's local player list
	peer_id = get_tree().get_network_unique_id()
	players[peer_id] = Player.new(peer_id, pseudo)
	emit_signal("connection_succeeded")


# Called when the client fails to connect to the server
func _connection_failed():
	get_tree().set_network_peer(null)
	emit_signal("connection_failed")


# Registers a new player in the room
remote func register_player(pseudo):
	var id = get_tree().get_rpc_sender_id()
	players[id] = Player.new(id, pseudo)
	emit_signal("player_list_changed")
	print("R3EGISTER PLAYER : " + pseudo + " " + str(id))


# Unregister a player from the room
func unregister_player(id):
	players.erase(id)
	emit_signal("player_list_changed")
	print("REMOVE PLAYER : " + str(id))


# Starts the game
func start_game() -> void:
	if not is_server:
		print("You're not an admin")
		return
	print("Start game")
	# TODO: Reset game scene
	get_tree().set_refuse_new_network_connections(true)
	
	rpc("initialize_game")


# Initializes the scene for the game to start
sync func initialize_game() -> void:
	
	# Initialize the checkpoint manager
	net_cp = NetworkCheckpoints.new(get_tree(), players.size())
	add_child(net_cp)
	if is_server:
		net_cp.create_checkpoint("scene_ready")
		net_cp.connect("scene_ready", self, "_on_everyone_ready")
	
	turn_order = players.values()
	turn_order.sort_custom(Player, "compare")

	player_count = players.size()
	
	# TODO: Move to a dedicated function
	var i := 0
	for player in turn_order:
		player.color = player_colors[i]
		i += 1
	
	game_started = true
	var deck_manager := get_tree().get_root().get_node("GameManager/Decks") as DecksManager 
	deck_manager.create_graveyard()
	deck_manager.create_decks()
	
	net_cp.validate("scene_ready")
	emit_signal("game_started")


func _on_everyone_ready() -> void:
	if not is_server:
		return
	var gm = get_tree().get_root().get_node("GameManager") as GameManager
	gm.rpc("start")


# Reset the room and reopen the lobby for new players
func reset_room() -> void:
	game_started = false
	get_tree().set_refuse_new_network_connections(false)


# Returns the current player
func me() -> Player:
	return players[peer_id]

  
# Disconnects the current player from the server
# If the player is the server, the server is closed
func self_disconnect() -> void:
	players.clear()
	if is_server:
		rpc("close_server")
	else:
		get_tree().set_network_peer(null)


sync func close_server() -> void:
	players.clear()
	emit_signal("server_closed")
	if is_server:
		get_tree().network_peer.set_refuse_new_connections(true)
		# HACK: Close the server after a delay to "ensure" all clients have left
		yield(get_tree().create_timer(1000), "timeout")
	get_tree().set_network_peer(null)
