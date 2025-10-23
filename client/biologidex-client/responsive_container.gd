class_name ResponsiveContainer
extends MarginContainer

# ResponsiveContainer - Automatically adjusts margins based on device class
# Usage: Attach this script to any MarginContainer that should adapt to screen size

@export_group("Margin Settings")
@export var mobile_margins: int = 16
@export var tablet_margins: int = 32
@export var desktop_margins: int = 48

@export_group("Breakpoints")
@export var mobile_breakpoint: int = 800
@export var tablet_breakpoint: int = 1280

@export var auto_update: bool = true

enum DeviceClass {
	MOBILE,
	TABLET,
	DESKTOP
}

var current_device_class: DeviceClass = DeviceClass.DESKTOP


func _ready() -> void:
	if auto_update:
		_update_margins()
		get_viewport().size_changed.connect(_update_margins)


func _update_margins() -> void:
	var width := get_viewport_rect().size.x
	var margin_value: int
	var new_device_class: DeviceClass

	# Determine device class and margin value
	if width < mobile_breakpoint:
		margin_value = mobile_margins
		new_device_class = DeviceClass.MOBILE
	elif width < tablet_breakpoint:
		margin_value = tablet_margins
		new_device_class = DeviceClass.TABLET
	else:
		margin_value = desktop_margins
		new_device_class = DeviceClass.DESKTOP

	# Update if device class changed
	if new_device_class != current_device_class:
		current_device_class = new_device_class
		_on_device_class_changed(new_device_class)

	# Apply margins to all sides
	add_theme_constant_override("margin_left", margin_value)
	add_theme_constant_override("margin_right", margin_value)
	add_theme_constant_override("margin_top", margin_value)
	add_theme_constant_override("margin_bottom", margin_value)


func _on_device_class_changed(new_class: DeviceClass) -> void:
	"""Override this method in derived classes to respond to device class changes"""
	pass


func get_device_class() -> DeviceClass:
	"""Returns the current device class"""
	return current_device_class


func get_device_class_string() -> String:
	"""Returns the current device class as a string"""
	match current_device_class:
		DeviceClass.MOBILE:
			return "mobile"
		DeviceClass.TABLET:
			return "tablet"
		DeviceClass.DESKTOP:
			return "desktop"
		_:
			return "unknown"


func set_margins_for_device_class(device_class: DeviceClass, margin: int) -> void:
	"""Manually set the margin value for a specific device class"""
	match device_class:
		DeviceClass.MOBILE:
			mobile_margins = margin
		DeviceClass.TABLET:
			tablet_margins = margin
		DeviceClass.DESKTOP:
			desktop_margins = margin

	if current_device_class == device_class:
		_update_margins()


func force_update() -> void:
	"""Force an immediate margin update"""
	_update_margins()