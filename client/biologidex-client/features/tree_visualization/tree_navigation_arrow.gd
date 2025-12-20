class_name TreeNavigationArrow
extends Node2D

## TreeNavigationArrow - Clickable arrow for tree navigation.
##
## Uses Sprite2D for rendering. Click detection is handled by the parent layer
## using manual hit testing (consistent with TreeRenderer pattern).
## Positioned along edges and rotated to point towards the target node.
##
## COORDINATE SPACES (per CLAUDE.md conventions):
## - `position`: TREE-LOCAL space (same as node.position in TreeDataModels)
## - `target_position`: TREE-LOCAL space
## - `_size`: TREE-LOCAL units (scales with tree, not screen)
##
## The parent TreeNavigationArrowsLayer converts screen input to tree-local
## coordinates before calling contains_point().

# =============================================================================
# Navigation Target (TREE-LOCAL coordinates)
# =============================================================================

## The target node ID this arrow navigates to
var target_node_id: String = ""

## The target position in TREE-LOCAL coordinates (same space as node.position)
var target_position: Vector2 = Vector2.ZERO

# =============================================================================
# State
# =============================================================================

## Whether this arrow is currently active (in use from pool)
var _is_active: bool = false

## Size of the arrow in TREE-LOCAL units (for hit detection and rendering)
var _size: float = 60.0

## Sprite for rendering the arrow
var _sprite: Sprite2D = null

## Arrow icon texture (cached at class level for efficiency)
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


## Activate this arrow for a specific edge endpoint.
##
## All positions are in TREE-LOCAL coordinates (same space as node.position).
## The arrow will be positioned at `pos` and rotated to point in `direction`.
##
## Parameters:
## - pos: Arrow position in TREE-LOCAL coordinates
## - target_pos: Position to navigate to in TREE-LOCAL coordinates
## - target_id: Node ID of the target
## - direction: Direction vector the arrow should point (normalized, TREE-LOCAL)
## - arrow_size: Size of the arrow in TREE-LOCAL units
func activate(pos: Vector2, target_pos: Vector2, target_id: String, direction: Vector2, arrow_size: float) -> void:
	target_position = target_pos
	target_node_id = target_id
	_is_active = true
	_size = arrow_size
	visible = true

	# Set position (TREE-LOCAL coordinates)
	position = pos

	# Calculate rotation from direction vector
	# Arrow icon points right (0 radians), so rotation = direction angle
	rotation = direction.angle()

	# Set sprite scale based on arrow size and texture size
	if _sprite and _arrow_texture:
		var tex_size: Vector2 = _arrow_texture.get_size()
		var scale_factor: float = arrow_size / maxf(tex_size.x, tex_size.y)
		_sprite.scale = Vector2(scale_factor, scale_factor)


## Deactivate this arrow (return to pool).
## Clears all navigation state.
func deactivate() -> void:
	_is_active = false
	visible = false
	target_node_id = ""
	target_position = Vector2.ZERO


## Check if arrow is currently active (in use from pool).
func is_active() -> bool:
	return _is_active


## Check if a point is inside this arrow's hit area.
##
## The point must be in TREE-LOCAL coordinates (same space as this arrow's position).
## Uses circular hit area centered on arrow position for consistent touch targets.
##
## Parameters:
## - local_point: Point to test in TREE-LOCAL coordinates
##
## Returns: true if point is within hit radius
func contains_point(local_point: Vector2) -> bool:
	if not _is_active:
		return false

	# Use circular hit area centered on arrow position
	# Minimum 22 tree-local units ensures reasonable touch target at typical zoom levels
	var hit_radius: float = maxf(_size / 2.0, 22.0)
	return position.distance_to(local_point) <= hit_radius


## Get the hit radius in TREE-LOCAL units.
## Useful for debugging or collision visualization.
func get_hit_radius() -> float:
	return maxf(_size / 2.0, 22.0)