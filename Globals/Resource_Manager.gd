# Resource_Manager.gd
extends Node

## Holds the persistent player scene/instance and forwards text-display
## calls to the GameTextBox singleton.

# Scene references
var player_instance = null

# Game resources
var player_script = preload("res://Player/player.tscn")

## Displays text via the GameTextBox singleton
func display_text(text_content: String):
	GameTextBox.display_text(text_content)

## Displays temporary text that clears itself after duration
func display_temporary_text(text_content: String, duration: float = 3.0):
	GameTextBox.display_temporary_text(text_content, duration)

## Clears text history
func clear_text_history():
	GameTextBox.clear_history()
