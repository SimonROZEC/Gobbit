extends Node2D
class_name GlobalMenu

onready var popup_manager : MenuPopupManager = $PopupLayer
onready var hub := $MenuLayer/Hub

const GAME_SCENE = "res://src/game/Game.tscn"

var menu_stack = [] # The stack of the opened submenus
var in_hub := false # Is the player in the hub or not

func _ready() -> void:
	$AnimationPlayer.play("Opening")
	add_to_group("global_menu")


func _on_AnimationPlayer_animation_finished(anim_name: String) -> void:
	match anim_name :
		"Opening":
			if not NetworkManager.connected_to_server:
				$AnimationPlayer.play("DeploySubMenu")
				push_menu($MenuLayer/SubMenus/Main)
			else:
				open_hub()
		"Exit":
			get_tree().quit()


# Closes the game with a fancy animation
func exit() -> void:
	$AnimationPlayer.play("Exit")


# Closes the menu and opens the hub interface
func open_hub() -> void:
	in_hub = true
	if menu_stack.size() > 0:
		$AnimationPlayer.play("ShrinkSubMenu")
		menu_stack[-1].close()
		yield(menu_stack[-1], "closed")
		yield($AnimationPlayer, "animation_finished")
	$AnimationPlayer.play("DeployHub")
	hub.open()
	hub.refresh_player_list()


# Closes the hub and returns to the main menu
func close_hub() -> void:
	in_hub = false
	$AnimationPlayer.play("CloseHub")
	yield($AnimationPlayer, "animation_finished")
	menu_stack.clear()
	push_menu($MenuLayer/SubMenus/Main)


# Push a new submenu in the stack
func push_menu(sm: SubMenu) -> void:
	if menu_stack.size() > 0:
		$AnimationPlayer.play("ShrinkSubMenu")
		menu_stack[-1].close()
		yield(menu_stack[-1], "closed")
		yield($AnimationPlayer, "animation_finished")
	menu_stack.push_back(sm)
	$AnimationPlayer.play("DeploySubMenu")
	sm.open()


# Pop the last submenu from the stack
# If the stack is empty, the game is closed
func pop_menu() -> void:
	$AnimationPlayer.play("ShrinkSubMenu")
	menu_stack[-1].close()
	yield(menu_stack[-1], "closed")
	yield($AnimationPlayer, "animation_finished")
	
	menu_stack.pop_back()
	if menu_stack.size() == 0:
		exit()
	else:
		$AnimationPlayer.play("DeploySubMenu")
		menu_stack[-1].open()


# Plays a start-game animation and loads the board scene after
func start_game() -> void:
	print("start game")
	$AnimationPlayer.play("StartGame")
	yield($AnimationPlayer, "animation_finished")
	var game_scene = load(GAME_SCENE)
	get_tree().change_scene_to(game_scene)
