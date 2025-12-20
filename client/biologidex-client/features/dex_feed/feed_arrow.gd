class_name FeedArrow
extends Node2D

## FeedArrow - Single navigation arrow for feed (Node2D-based).
##
## COORDINATE SPACES:
## - position: Feed-local space (recalculated each frame to appear at fixed screen position)
## - _size: Size in feed-local units (scaled inversely with camera zoom)
##
## Since there's no arrow_up.svg or arrow_down.svg, we use arrow_right.svg
## and rotate it: UP = -90 degrees, DOWN = +90 degrees.

enum Direction { UP, DOWN }

## Direction this arrow points
var direction: Direction = Direction.DOWN

## Hit detection callback (set by parent layer)
var _hit_callback: Callable = Callable()

# =============================================================================
# Internal Components
# =============================================================================

var _sprite: Sprite2D = null
var _is_active: bool = false
var _size: float = 48.0  # Size in feed-local units

# Shared texture (loaded once)
static var _arrow_texture: Texture2D = null

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	# Load texture if not already loaded
	if not _arrow_texture:
		_arrow_texture = load("res://resources/icons/kenny_board-game-icons/arrow_right.svg")

	# Create sprite for arrow display
	_sprite = Sprite2D.new()
	_sprite.name = "ArrowSprite"
	_sprite.texture = _arrow_texture
	add_child(_sprite)

	visible = false


# =============================================================================
# Public API
# =============================================================================

## Activate the arrow at a position with a size, color, and opacity.
## pos: Position in FEED-LOCAL space
## arrow_size: Size in FEED-LOCAL units (already scaled for zoom)
## color: Arrow color (modulate)
## opacity: Arrow opacity (0.0 - 1.0)
func activate(pos: Vector2, arrow_size: float, color: Color = Color.BLACK, opacity: float = 0.75) -> void:
	_is_active = true
	_size = arrow_size
	position = pos
	visible = true

	# Apply rotation based on direction
	# arrow_right.svg points right, so:
	# - UP: rotate -90 degrees (counter-clockwise)
	# - DOWN: rotate +90 degrees (clockwise)
	match direction:
		Direction.UP:
			_sprite.rotation_degrees = -90.0
		Direction.DOWN:
			_sprite.rotation_degrees = 90.0

	# Scale sprite to match desired size
	if _sprite.texture:
		var tex_size: float = _sprite.texture.get_size().x
		if tex_size > 0:
			var scale_val: float = arrow_size / tex_size
			_sprite.scale = Vector2(scale_val, scale_val)

	# Apply color and opacity (matching tree arrows)
	_sprite.modulate = Color(color.r, color.g, color.b, opacity)


## Deactivate the arrow
func deactivate() -> void:
	_is_active = false
	visible = false


## Check if a point in FEED-LOCAL space hits this arrow.
## Uses circular hit detection for touch-friendly interaction.
func contains_point(local_pos: Vector2) -> bool:
	if not _is_active:
		return false

	# Use circular hit detection (more forgiving for touch)
	var hit_radius: float = _size / 2.0
	var dist: float = position.distance_to(local_pos)
	return dist <= hit_radius


## Check if the arrow is currently active/visible
func is_active() -> bool:
	return _is_active


## Get the current size in feed-local units
func get_size() -> float:
	return _size


## Set a callback for when this arrow is pressed
func set_hit_callback(callback: Callable) -> void:
	_hit_callback = callback


## Call the hit callback (invoked by parent layer)
func on_pressed() -> void:
	if _hit_callback.is_valid():
		_hit_callback.call()
