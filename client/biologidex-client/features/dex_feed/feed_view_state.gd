class_name FeedViewState
extends RefCounted

## FeedViewState - Shared view state for feed coordinate conversions.
##
## COORDINATE SPACES:
## - Screen space: Pixels, origin top-left (0,0). Used for UI, input events.
## - World space: World units, scene origin. Camera.position is in world space.
## - Feed-local space: World units, feed origin (0,0 at top). Entry positions.
##
## The feed uses a simple vertical layout where Y increases downward.
## This class provides coordinate conversion utilities and view rect calculations.

signal view_changed()

# =============================================================================
# View Parameters
# =============================================================================

## Camera scroll offset in WORLD SPACE (position at viewport center)
var scroll_offset: Vector2 = Vector2.ZERO:
	set(value):
		if scroll_offset != value:
			scroll_offset = value
			view_changed.emit()

## Camera zoom scale (1.0 = normal)
var current_scale: float = 1.0:
	set(value):
		if absf(current_scale - value) > 0.001:
			current_scale = value
			view_changed.emit()

## Viewport center in SCREEN SPACE (pixels)
var viewport_center: Vector2 = Vector2(640, 360)

## Viewport size in SCREEN SPACE (pixels)
var viewport_size: Vector2 = Vector2(1280, 720)


# =============================================================================
# Coordinate Conversions
# =============================================================================

## Convert FEED-LOCAL position to SCREEN coordinates.
## Formula: (feed_pos - scroll_offset) * scale + viewport_center
func feed_local_to_screen(feed_pos: Vector2) -> Vector2:
	return (feed_pos - scroll_offset) * current_scale + viewport_center


## Convert SCREEN position to FEED-LOCAL coordinates.
## Inverse of feed_local_to_screen.
func screen_to_feed_local(screen_pos: Vector2) -> Vector2:
	return (screen_pos - viewport_center) / current_scale + scroll_offset


## Get view rectangle in FEED-LOCAL coordinates.
## Optional margin is in SCREEN PIXELS and gets converted to feed-local units.
func get_view_rect(margin_screen: float = 0.0) -> Rect2:
	var margin_local: float = margin_screen / current_scale
	var half_size: Vector2 = (viewport_size / 2.0) / current_scale + Vector2(margin_local, margin_local)
	var center: Vector2 = scroll_offset
	return Rect2(center - half_size, half_size * 2)


## Get the feed-local Y position at viewport center.
## Useful for determining which entry is "focused".
func get_center_y() -> float:
	return scroll_offset.y


## Get feed-local position at viewport center.
func get_center_position() -> Vector2:
	return scroll_offset


## Convert a distance in screen pixels to feed-local units.
func screen_to_local_distance(screen_dist: float) -> float:
	return screen_dist / current_scale


## Convert a distance in feed-local units to screen pixels.
func local_to_screen_distance(local_dist: float) -> float:
	return local_dist * current_scale


# =============================================================================
# Batch Update
# =============================================================================

## Batch update view parameters. Reduces signal emissions when multiple
## parameters change at once.
func update(new_scroll: Vector2, new_scale: float, new_center: Vector2, new_size: Vector2) -> void:
	var changed := false

	if scroll_offset != new_scroll:
		scroll_offset = new_scroll
		changed = true

	if absf(current_scale - new_scale) > 0.001:
		current_scale = new_scale
		changed = true

	viewport_center = new_center
	viewport_size = new_size

	if changed:
		view_changed.emit()


## Update just the scroll and scale (common case from camera).
func update_from_camera(cam_position: Vector2, zoom: float) -> void:
	var changed := false

	if scroll_offset != cam_position:
		scroll_offset = cam_position
		changed = true

	if absf(current_scale - zoom) > 0.001:
		current_scale = zoom
		changed = true

	if changed:
		view_changed.emit()


## Update viewport dimensions (call when viewport resizes).
func update_viewport(new_size: Vector2) -> void:
	viewport_size = new_size
	viewport_center = new_size / 2.0
