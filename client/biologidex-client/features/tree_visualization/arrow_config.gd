class_name TreeArrowConfig
extends RefCounted

## TreeArrowConfig - Configuration object for tree navigation arrows.
##
## This eliminates redundant parameter propagation between TreeVisualization
## and TreeNavigationArrowsLayer by providing a single configuration object.
## Changes to config values are automatically reflected in the arrows layer.

## Emitted when any configuration value changes
signal config_changed()

# =============================================================================
# Arrow Appearance (all in tree-local units unless noted)
# =============================================================================

## Size of arrow buttons in tree-local units
var size: float = 30.0:
	set(value):
		if abs(size - value) > 0.1:
			size = value
			config_changed.emit()

## Base distance from node center to place arrow
var distance_from_node: float = 60.0:
	set(value):
		if abs(distance_from_node - value) > 0.1:
			distance_from_node = value
			config_changed.emit()

## Opacity of arrow buttons (0.0 - 1.0)
var opacity: float = 0.75:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if abs(opacity - value) > 0.01:
			opacity = value
			config_changed.emit()

## Color tint for arrows (modulate)
var color: Color = Color(0, 0, 0, 1.0):
	set(value):
		if color != value:
			color = value
			config_changed.emit()

## Extra offset when placing arrows near nodes with dex images
## This accounts for ~1000 size dex images to prevent overlap
var dex_image_offset: float = 500.0:
	set(value):
		if abs(dex_image_offset - value) > 0.1:
			dex_image_offset = value
			config_changed.emit()

## Minimum edge length to show arrows (shorter edges get no arrows)
var min_edge_length: float = 120.0:
	set(value):
		if abs(min_edge_length - value) > 0.1:
			min_edge_length = value
			config_changed.emit()

## Maximum portion of edge length for arrow placement (0.0 - 1.0)
## Arrows won't be placed more than this fraction along an edge
var max_edge_fraction: float = 0.4:
	set(value):
		value = clampf(value, 0.1, 0.9)
		if abs(max_edge_fraction - value) > 0.01:
			max_edge_fraction = value
			config_changed.emit()

# =============================================================================
# Diff Circle Offset (for root node arrows)
# =============================================================================

## Extra padding beyond diff circle radius for arrow placement
## This ensures arrows appear clearly outside the diff circle
var diff_circle_padding: float = 30.0:
	set(value):
		if abs(diff_circle_padding - value) > 0.1:
			diff_circle_padding = value
			config_changed.emit()

# =============================================================================
# Pool Configuration
# =============================================================================

## Maximum number of arrows in the object pool
## Reduced from 200 to 50 since only one node's arrows are shown at a time
var pool_size: int = 50:
	set(value):
		value = clampi(value, 10, 500)
		if pool_size != value:
			pool_size = value
			config_changed.emit()

# =============================================================================
# Factory Methods
# =============================================================================

## Create a config with default values
static func create_default() -> TreeArrowConfig:
	return TreeArrowConfig.new()


## Create a config from a dictionary of values
static func from_dict(values: Dictionary) -> TreeArrowConfig:
	var config := TreeArrowConfig.new()

	if values.has("size"):
		config.size = values.size
	if values.has("distance_from_node"):
		config.distance_from_node = values.distance_from_node
	if values.has("opacity"):
		config.opacity = values.opacity
	if values.has("color"):
		config.color = values.color
	if values.has("dex_image_offset"):
		config.dex_image_offset = values.dex_image_offset
	if values.has("min_edge_length"):
		config.min_edge_length = values.min_edge_length
	if values.has("max_edge_fraction"):
		config.max_edge_fraction = values.max_edge_fraction
	if values.has("diff_circle_padding"):
		config.diff_circle_padding = values.diff_circle_padding
	if values.has("pool_size"):
		config.pool_size = values.pool_size

	return config


## Export current config to dictionary
func to_dict() -> Dictionary:
	return {
		"size": size,
		"distance_from_node": distance_from_node,
		"opacity": opacity,
		"color": color,
		"dex_image_offset": dex_image_offset,
		"min_edge_length": min_edge_length,
		"max_edge_fraction": max_edge_fraction,
		"diff_circle_padding": diff_circle_padding,
		"pool_size": pool_size
	}
