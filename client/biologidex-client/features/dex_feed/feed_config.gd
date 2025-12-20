class_name FeedConfig
extends RefCounted

## FeedConfig - Configuration object for feed visualization and navigation.
##
## This provides a single configuration object for feed-related settings,
## eliminating redundant parameter propagation between components.
## Changes to config values automatically propagate via config_changed signal.

## Emitted when any configuration value changes
signal config_changed()

# =============================================================================
# Arrow Appearance (screen pixels for arrows since they need fixed screen size)
# =============================================================================

## Size of arrow buttons in screen pixels (constant on screen regardless of zoom)
## 80px provides good touch target (minimum 44px recommended, larger is better for feed)
var size: float = 80.0:
	set(value):
		if absf(size - value) > 0.1:
			size = value
			config_changed.emit()

## Distance from screen edge to arrow center in pixels
var arrow_edge_distance: float = 40.0:
	set(value):
		if absf(arrow_edge_distance - value) > 0.1:
			arrow_edge_distance = value
			config_changed.emit()

## Opacity of arrow buttons (0.0 - 1.0) - matches tree arrows
var arrow_opacity: float = 0.75:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if absf(arrow_opacity - value) > 0.01:
			arrow_opacity = value
			config_changed.emit()

## Color tint for arrows (modulate) - black like tree arrows
var arrow_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		if arrow_color != value:
			arrow_color = value
			config_changed.emit()

# =============================================================================
# Image Layout (world units - applied before camera zoom)
# =============================================================================

## Minimum vertical spacing between images in world units
var min_spacing: float = 100.0:
	set(value):
		if absf(min_spacing - value) > 0.1:
			min_spacing = value
			config_changed.emit()

## Maximum additional random spacing in world units
var max_random_spacing: float = 60.0:
	set(value):
		if absf(max_random_spacing - value) > 0.1:
			max_random_spacing = value
			config_changed.emit()

## Maximum horizontal offset as fraction of viewport width (-1.0 to 1.0)
var max_horizontal_offset: float = 0.1:
	set(value):
		value = clampf(value, -1.0, 1.0)
		if absf(max_horizontal_offset - value) > 0.001:
			max_horizontal_offset = value
			config_changed.emit()

## Maximum rotation in degrees
var max_rotation: float = 8.0:
	set(value):
		if absf(max_rotation - value) > 0.1:
			max_rotation = value
			config_changed.emit()

# =============================================================================
# Image Sizing
# =============================================================================

## Base image width as fraction of viewport (0.0 - 1.0)
var base_width_fraction: float = 0.85:
	set(value):
		value = clampf(value, 0.1, 1.0)
		if absf(base_width_fraction - value) > 0.001:
			base_width_fraction = value
			config_changed.emit()

## Maximum height as fraction of viewport (0.0 - 1.0)
var max_height_fraction: float = 0.7:
	set(value):
		value = clampf(value, 0.1, 1.0)
		if absf(max_height_fraction - value) > 0.001:
			max_height_fraction = value
			config_changed.emit()

## Default aspect ratio for images (width / height) before actual image loads
var default_aspect_ratio: float = 1.33:  # 4:3 aspect ratio
	set(value):
		if absf(default_aspect_ratio - value) > 0.01:
			default_aspect_ratio = value
			config_changed.emit()

# =============================================================================
# Pool Configuration
# =============================================================================

## Size of the image pool (number of pre-allocated WorldSpaceImage nodes)
## 10 provides enough buffer for smooth scrolling with large images
var pool_size: int = 10:
	set(value):
		value = clampi(value, 3, 20)
		if pool_size != value:
			pool_size = value
			config_changed.emit()

## Buffer distance (in screen pixels) for visibility calculations
## Images within this margin of the viewport are considered "visible"
var visibility_buffer: float = 200.0:
	set(value):
		if absf(visibility_buffer - value) > 1.0:
			visibility_buffer = value
			config_changed.emit()

# =============================================================================
# Factory Methods
# =============================================================================

## Create a config with default values
static func create_default() -> FeedConfig:
	return FeedConfig.new()


## Create a config from a dictionary of values
static func from_dict(values: Dictionary) -> FeedConfig:
	var config := FeedConfig.new()

	if values.has("size"):
		config.size = values.size
	if values.has("arrow_edge_distance"):
		config.arrow_edge_distance = values.arrow_edge_distance
	if values.has("arrow_opacity"):
		config.arrow_opacity = values.arrow_opacity
	if values.has("arrow_color"):
		config.arrow_color = values.arrow_color
	if values.has("min_spacing"):
		config.min_spacing = values.min_spacing
	if values.has("max_random_spacing"):
		config.max_random_spacing = values.max_random_spacing
	if values.has("max_horizontal_offset"):
		config.max_horizontal_offset = values.max_horizontal_offset
	if values.has("max_rotation"):
		config.max_rotation = values.max_rotation
	if values.has("base_width_fraction"):
		config.base_width_fraction = values.base_width_fraction
	if values.has("max_height_fraction"):
		config.max_height_fraction = values.max_height_fraction
	if values.has("default_aspect_ratio"):
		config.default_aspect_ratio = values.default_aspect_ratio
	if values.has("pool_size"):
		config.pool_size = values.pool_size
	if values.has("visibility_buffer"):
		config.visibility_buffer = values.visibility_buffer

	return config


## Export current config to dictionary
func to_dict() -> Dictionary:
	return {
		"size": size,
		"arrow_edge_distance": arrow_edge_distance,
		"arrow_opacity": arrow_opacity,
		"arrow_color": arrow_color,
		"min_spacing": min_spacing,
		"max_random_spacing": max_random_spacing,
		"max_horizontal_offset": max_horizontal_offset,
		"max_rotation": max_rotation,
		"base_width_fraction": base_width_fraction,
		"max_height_fraction": max_height_fraction,
		"default_aspect_ratio": default_aspect_ratio,
		"pool_size": pool_size,
		"visibility_buffer": visibility_buffer
	}
