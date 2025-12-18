extends Node2D
class_name WorldSpaceUI

## WorldSpaceUI - Container for UI elements that move with the world (pan with camera).
##
## Add this to PaperCameraScene's content_container to create UI that pans with the tree.
## Child Control nodes will be positioned relative to this node's world position.

## Position in world space where UI is centered
@export var anchor_position: Vector2 = Vector2.ZERO

## Whether to auto-position to anchor on ready
@export var auto_position: bool = true


func _ready() -> void:
	if auto_position:
		position = anchor_position


## Set the anchor position and update the node's position
func set_anchor(pos: Vector2) -> void:
	anchor_position = pos
	position = anchor_position


## Get the current anchor position
func get_anchor() -> Vector2:
	return anchor_position