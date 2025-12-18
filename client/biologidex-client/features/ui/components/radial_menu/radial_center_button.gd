extends RadialButtonBase
class_name RadialCenterButton

## RadialCenterButton - Large circular button for the primary action.
##
## Extends RadialButtonBase with center-specific defaults:
## - Larger default radius (120px)
## - Larger default font size (48px)
## - Larger default icon size (64x64)
##
## Inherits: RadialButtonBase
## Used by: RadialMenuRing, RadialMenuCircles

# =============================================================================
# Default Overrides
# =============================================================================

func _on_ready() -> void:
	# Apply center-specific defaults if not already set by parent
	if radius == 60.0:  # Default base value
		radius = 120.0
	if font_size == 32:  # Default base value
		font_size = 48
	if icon_size == Vector2(32, 32):  # Default base value
		icon_size = Vector2(64, 64)

	# Update colors to center-specific defaults if using base defaults
	if normal_color == Color(0.2, 0.2, 0.25, 0.85):
		normal_color = Color(0.15, 0.15, 0.18, 0.95)
	if hover_color == Color(0.3, 0.3, 0.4, 0.95):
		hover_color = Color(0.25, 0.25, 0.35, 0.95)
	if pressed_color == Color(0.1, 0.1, 0.15, 1.0):
		pressed_color = Color(0.1, 0.1, 0.12, 1.0)
	if border_width == 2.0:
		border_width = 3.0
	if border_color == Color(0.4, 0.4, 0.5, 0.6):
		border_color = Color(0.4, 0.4, 0.5, 0.8)

	_update_size()
