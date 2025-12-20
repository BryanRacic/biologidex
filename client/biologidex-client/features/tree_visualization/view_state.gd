class_name TreeViewState
extends RefCounted

## TreeViewState - Shared view state for tree coordinate conversions.
##
## This class eliminates triple redundancy of view state across TreeVisualization,
## TreeRenderer, and TreeNavigationArrowsLayer by providing a single source of truth.
##
## Coordinate Space Reference (from CLAUDE.md):
## - Screen space: Pixels, origin top-left (0,0). Used for UI, input events.
## - World space: World units, scene origin. Used for camera offset, content.
## - Tree-local space: World units, tree root (0,0). Server-provided node positions.
##
## Key formulas:
## - scroll_offset = world position that appears at viewport center
## - world_to_screen(W) = (W - scroll_offset) * scale + viewport_center
## - screen_to_world(S) = (S - viewport_center) / scale + scroll_offset

## Emitted when any view parameter changes
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

## Camera zoom scale (1.0 = normal, 2.0 = zoomed in 2x)
var current_scale: float = 1.0:
	set(value):
		if abs(current_scale - value) > 0.001:
			current_scale = value
			view_changed.emit()

## Viewport center in SCREEN SPACE (typically viewport_size / 2)
var viewport_center: Vector2 = Vector2(640, 360):
	set(value):
		if viewport_center != value:
			viewport_center = value
			view_changed.emit()

## Viewport size in SCREEN SPACE (pixels)
var viewport_size: Vector2 = Vector2(1280, 720):
	set(value):
		if viewport_size != value:
			viewport_size = value
			view_changed.emit()

## Tree graph scale factor (TreeVisualization.tree_scale)
## This is separate from camera zoom - it's the scale of the tree_graph Node2D
var tree_scale: float = 1.0:
	set(value):
		if abs(tree_scale - value) > 0.001:
			tree_scale = value
			view_changed.emit()

# =============================================================================
# Coordinate Conversions
# =============================================================================

## Convert TREE-LOCAL position to SCREEN coordinates.
## tree_local_pos: Position in tree-local space (same as node.position)
## Returns: Position in screen space (pixels from top-left)
func tree_local_to_screen(tree_local_pos: Vector2) -> Vector2:
	var world_pos: Vector2 = tree_local_pos * tree_scale
	return (world_pos - scroll_offset) * current_scale + viewport_center


## Convert SCREEN position to TREE-LOCAL coordinates.
## screen_pos: Position in screen space (pixels from top-left)
## Returns: Position in tree-local space (same as node.position)
func screen_to_tree_local(screen_pos: Vector2) -> Vector2:
	var world_pos: Vector2 = (screen_pos - viewport_center) / current_scale + scroll_offset
	return world_pos / tree_scale


## Convert WORLD position to SCREEN coordinates.
## world_pos: Position in world space
## Returns: Position in screen space (pixels from top-left)
func world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - scroll_offset) * current_scale + viewport_center


## Convert SCREEN position to WORLD coordinates.
## screen_pos: Position in screen space (pixels from top-left)
## Returns: Position in world space
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - viewport_center) / current_scale + scroll_offset


## Convert TREE-LOCAL position to WORLD coordinates.
## tree_local_pos: Position in tree-local space
## Returns: Position in world space
func tree_local_to_world(tree_local_pos: Vector2) -> Vector2:
	return tree_local_pos * tree_scale


## Convert WORLD position to TREE-LOCAL coordinates.
## world_pos: Position in world space
## Returns: Position in tree-local space
func world_to_tree_local(world_pos: Vector2) -> Vector2:
	return world_pos / tree_scale

# =============================================================================
# View Rectangle Calculations
# =============================================================================

## Get combined scale (camera zoom * tree scale)
func get_combined_scale() -> float:
	return current_scale * tree_scale


## Get view rectangle in TREE-LOCAL coordinates.
## margin_screen: Margin in screen pixels to add around viewport
## Returns: Rect2 in tree-local space that is currently visible
func get_view_rect(margin_screen: float = 0.0) -> Rect2:
	var combined_scale: float = current_scale * tree_scale
	var margin_local: float = margin_screen / combined_scale
	var half_size: Vector2 = (viewport_size / 2.0) / combined_scale + Vector2(margin_local, margin_local)
	var center: Vector2 = scroll_offset / tree_scale
	return Rect2(center - half_size, half_size * 2)


## Get viewport center in TREE-LOCAL coordinates.
## This is the tree-local position that appears at screen center.
func get_viewport_center_tree_local() -> Vector2:
	return scroll_offset / tree_scale

# =============================================================================
# Batch Update
# =============================================================================

## Update all view parameters at once (reduces signal emissions)
## Note: Setters emit view_changed signal individually, so we don't emit again here.
func update(new_scroll: Vector2, new_scale: float, new_center: Vector2, new_viewport_size: Vector2 = Vector2.ZERO) -> void:
	if scroll_offset != new_scroll:
		scroll_offset = new_scroll

	if abs(current_scale - new_scale) > 0.001:
		current_scale = new_scale

	if viewport_center != new_center:
		viewport_center = new_center

	if new_viewport_size != Vector2.ZERO and viewport_size != new_viewport_size:
		viewport_size = new_viewport_size


## Update from a viewport node (gets size automatically)
func update_from_viewport(new_scroll: Vector2, new_scale: float, viewport: Viewport) -> void:
	if viewport:
		var size: Vector2 = viewport.get_visible_rect().size
		update(new_scroll, new_scale, size / 2.0, size)
	else:
		update(new_scroll, new_scale, viewport_center)
