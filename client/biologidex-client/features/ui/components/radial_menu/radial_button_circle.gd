extends RadialButtonBase
class_name RadialButtonCircle

## RadialButtonCircle - Circular button for ring placement in radial menus.
##
## Extends RadialButtonBase with positioning support for circular arrangement
## around a center point. The parent menu positions these buttons using
## set_ring_position() based on their angle around the center.
##
## Inherits: RadialButtonBase
## Used by: RadialMenuCircles

# =============================================================================
# Export Variables - Ring Position
# =============================================================================

@export_group("Ring Position")
## The angle (radians) where this button is positioned around the center
@export var angle: float = 0.0

## The distance from the menu center to this button's center
@export var distance_from_center: float = 200.0

# =============================================================================
# Internal State
# =============================================================================

## Index in the ring (set by parent menu)
var ring_index: int = -1

# =============================================================================
# Default Overrides
# =============================================================================

func _on_ready() -> void:
	# Ring buttons use base defaults (smaller than center)
	pass

# =============================================================================
# Public API - Positioning
# =============================================================================

func set_ring_position(ring_angle: float, ring_distance: float, menu_center: Vector2) -> void:
	"""Position this button around the ring at the given angle and distance."""
	angle = ring_angle
	distance_from_center = ring_distance

	# Calculate world position based on polar coordinates
	var offset := Vector2(cos(angle), sin(angle)) * distance_from_center
	var button_center := menu_center + offset

	# Position so button center aligns with calculated position
	position = button_center - Vector2(radius, radius)


func get_angle() -> float:
	"""Get the angle of this button in the ring."""
	return angle


func get_distance() -> float:
	"""Get the distance from center."""
	return distance_from_center


func get_ring_index() -> int:
	"""Get this button's index in the ring."""
	return ring_index


func set_ring_index(idx: int) -> void:
	"""Set this button's index in the ring."""
	ring_index = idx
