class_name TreeNavigationArrow
extends Node2D

## TreeNavigationArrow - Clickable arrow for tree navigation.
##
## Uses Sprite2D for rendering. Click detection is handled by the parent layer
## using manual hit testing (consistent with TreeRenderer pattern).
## Positioned along edges and rotated to point towards the target node.

## The target node ID this arrow navigates to
var target_node_id: String = ""

## The target position in tree-local coordinates
var target_position: Vector2 = Vector2.ZERO

## Whether this arrow is currently active (in use from pool)
var _is_active: bool = false

## Size of the arrow (for hit detection)
var _size: float = 60.0

## Sprite for rendering the arrow
var _sprite: Sprite2D = null

## Arrow icon texture (cached)
static var _arrow_texture: Texture2D = null


func _ready() -> void:
	# Load arrow texture once (static cache)
	if not _arrow_texture:
		_arrow_texture = load("res://resources/icons/kenny_board-game-icons/arrow_right.svg")

	# Create sprite
	_sprite = Sprite2D.new()
	_sprite.texture = _arrow_texture
	add_child(_sprite)

	# Start inactive
	visible = false
	_is_active = false


## Activate this arrow for a specific edge endpoint
## pos: Arrow position in tree-local coordinates
## target_pos: Position to navigate to (tree-local)
## target_id: Node ID of the target
## direction: Direction vector the arrow should point (normalized)
## arrow_size: Size of the arrow in tree-local units
func activate(pos: Vector2, target_pos: Vector2, target_id: String, direction: Vector2, arrow_size: float) -> void:
	target_position = target_pos
	target_node_id = target_id
	_is_active = true
	_size = arrow_size
	visible = true

	# Set position
	position = pos

	# Calculate rotation from direction vector
	# Arrow icon points right (0 radians), so rotation = direction angle
	rotation = direction.angle()

	# Set sprite scale based on arrow size and texture size
	if _sprite and _arrow_texture:
		var tex_size = _arrow_texture.get_size()
		var scale_factor = arrow_size / max(tex_size.x, tex_size.y)
		_sprite.scale = Vector2(scale_factor, scale_factor)


## Deactivate this arrow (return to pool)
func deactivate() -> void:
	_is_active = false
	visible = false
	target_node_id = ""
	target_position = Vector2.ZERO


## Check if arrow is currently active
func is_active() -> bool:
	return _is_active


## Check if a point (in tree-local coordinates) is inside this arrow's hit area
func contains_point(local_point: Vector2) -> bool:
	if not _is_active:
		return false
	# Use circular hit area centered on arrow position
	var hit_radius = max(_size / 2.0, 22.0)  # Minimum 22 for 44px touch target at scale 1.0
	return position.distance_to(local_point) <= hit_radius


## Get the hit radius in tree-local units
func get_hit_radius() -> float:
	return max(_size / 2.0, 22.0)
