extends Node

# NavigationManager - Global singleton for scene navigation
# Handles scene transitions with history stack for back navigation

signal scene_changed(new_scene_path: String)
signal navigation_failed(error_message: String)

var scene_stack: Array[String] = []
var max_stack_size: int = 10  # Prevent memory issues with very deep navigation


func navigate_to(scene_path: String, clear_history: bool = false) -> void:
	"""
	Navigate to a new scene

	Args:
		scene_path: Path to the scene file (e.g., "res://scenes/login.tscn")
		clear_history: If true, clears the navigation history
	"""
	if not ResourceLoader.exists(scene_path):
		var error_msg := "Scene not found: " + scene_path
		push_error(error_msg)
		navigation_failed.emit(error_msg)
		return

	# Store current scene in history unless clearing
	if not clear_history:
		var current_scene := get_tree().current_scene
		if current_scene and current_scene.scene_file_path:
			scene_stack.push_back(current_scene.scene_file_path)

			# Limit stack size
			if scene_stack.size() > max_stack_size:
				scene_stack.pop_front()

	# Change to new scene
	var error := get_tree().change_scene_to_file(scene_path)

	if error != OK:
		var error_msg := "Failed to load scene: " + scene_path
		push_error(error_msg)
		navigation_failed.emit(error_msg)
	else:
		scene_changed.emit(scene_path)


func go_back() -> bool:
	"""
	Navigate back to the previous scene in history

	Returns:
		true if navigation was successful, false if no history exists
	"""
	if scene_stack.size() == 0:
		push_warning("Cannot go back: navigation history is empty")
		return false

	var previous_scene: String = scene_stack.pop_back()

	if not ResourceLoader.exists(previous_scene):
		push_error("Previous scene no longer exists: " + previous_scene)
		navigation_failed.emit("Previous scene not found")
		return false

	# Change scene without adding to history
	var error := get_tree().change_scene_to_file(previous_scene)

	if error != OK:
		push_error("Failed to go back to: " + previous_scene)
		navigation_failed.emit("Failed to navigate back")
		return false

	scene_changed.emit(previous_scene)
	return true


func clear_history() -> void:
	"""Clear the entire navigation history"""
	scene_stack.clear()


func get_history() -> Array[String]:
	"""Get a copy of the navigation history"""
	return scene_stack.duplicate()


func can_go_back() -> bool:
	"""Returns true if there is navigation history to go back to"""
	return scene_stack.size() > 0


func get_history_size() -> int:
	"""Returns the number of scenes in the navigation history"""
	return scene_stack.size()


func peek_previous() -> String:
	"""
	Get the path of the previous scene without navigating

	Returns:
		The scene path or empty string if no history exists
	"""
	if scene_stack.size() > 0:
		return scene_stack.back()
	return ""
