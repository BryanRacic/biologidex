class_name AppState extends Node

## Centralized application state management with reactive updates
## Provides a single source of truth for application state

signal state_changed(path: String, value: Variant)
signal user_changed(user_data: Dictionary)
signal auth_state_changed(is_authenticated: bool)
signal sync_state_changed(sync_data: Dictionary)

# State structure
var _state: Dictionary = {
	"auth": {
		"is_authenticated": false,
		"user": null,
		"tokens": {
			"access": "",
			"refresh": ""
		}
	},
	"ui": {
		"current_scene": "",
		"is_loading": false,
		"error": null
	},
	"dex": {
		"current_user_id": null,
		"total_entries": 0,
		"last_sync": 0
	},
	"social": {
		"friends_count": 0,
		"pending_requests": 0
	},
	"camera": {
		"current_state": "IDLE",
		"analysis_job_id": null
	}
}

# Subscribers: path -> Array[Callable]
var _subscribers: Dictionary = {}

# State history for undo/redo
var _history: Array[Dictionary] = []
var _max_history_size: int = 20

## Get state value by path (e.g., "auth.user.username")
func get_state(path: String) -> Variant:
	var keys: PackedStringArray = path.split(".")
	var current: Variant = _state

	for key in keys:
		if current is Dictionary and key in current:
			current = current[key]
		else:
			return null

	return current

## Set state value by path
func set_state(path: String, value: Variant, emit_signal: bool = true) -> void:
	var keys: PackedStringArray = path.split(".")
	if keys.size() == 0:
		return

	# Save to history
	_save_to_history()

	# Navigate to parent
	var current: Dictionary = _state
	for i in range(keys.size() - 1):
		var key: String = keys[i]
		if not key in current:
			current[key] = {}
		current = current[key]

	# Set value
	var final_key: String = keys[keys.size() - 1]
	current[final_key] = value

	if emit_signal:
		# Notify subscribers
		_notify_subscribers(path, value)

		# Emit specific signals for important state changes
		_emit_specific_signals(path, value)

		# Emit general state changed signal
		state_changed.emit(path, value)

## Subscribe to state changes at a specific path
func subscribe(path: String, callback: Callable) -> void:
	if not path in _subscribers:
		_subscribers[path] = []

	if not callback in _subscribers[path]:
		_subscribers[path].append(callback)

## Unsubscribe from state changes
func unsubscribe(path: String, callback: Callable) -> void:
	if not path in _subscribers:
		return

	var index: int = _subscribers[path].find(callback)
	if index >= 0:
		_subscribers[path].remove_at(index)

	if _subscribers[path].is_empty():
		_subscribers.erase(path)

## Update multiple state values at once
func batch_update(updates: Dictionary) -> void:
	_save_to_history()

	for path in updates.keys():
		set_state(path, updates[path], false)

	# Emit all changes
	for path in updates.keys():
		_notify_subscribers(path, updates[path])
		_emit_specific_signals(path, updates[path])
		state_changed.emit(path, updates[path])

## Reset state to initial values
func reset() -> void:
	_save_to_history()

	_state = {
		"auth": {
			"is_authenticated": false,
			"user": null,
			"tokens": {
				"access": "",
				"refresh": ""
			}
		},
		"ui": {
			"current_scene": "",
			"is_loading": false,
			"error": null
		},
		"dex": {
			"current_user_id": null,
			"total_entries": 0,
			"last_sync": 0
		},
		"social": {
			"friends_count": 0,
			"pending_requests": 0
		},
		"camera": {
			"current_state": "IDLE",
			"analysis_job_id": null
		}
	}

	state_changed.emit("", _state)

## Get entire state (use sparingly)
func get_full_state() -> Dictionary:
	return _state.duplicate(true)

## Undo last state change
func undo() -> bool:
	if _history.is_empty():
		return false

	_state = _history.pop_back()
	state_changed.emit("", _state)
	return true

## Clear history
func clear_history() -> void:
	_history.clear()

## Notify all subscribers for a path
func _notify_subscribers(path: String, value: Variant) -> void:
	# Exact path subscribers
	if path in _subscribers:
		for callback in _subscribers[path]:
			if callback.is_valid():
				callback.call(value)

	# Wildcard subscribers (parent paths)
	var parts: PackedStringArray = path.split(".")
	for i in range(parts.size()):
		var parent_path: String = ".".join(parts.slice(0, i + 1))
		if parent_path in _subscribers:
			for callback in _subscribers[parent_path]:
				if callback.is_valid():
					callback.call(value)

## Emit specific signals for important state changes
func _emit_specific_signals(path: String, value: Variant) -> void:
	match path:
		"auth.user":
			if value is Dictionary:
				user_changed.emit(value)
		"auth.is_authenticated":
			auth_state_changed.emit(value)
		"dex.last_sync", "dex.total_entries":
			var dex_state: Dictionary = get_state("dex")
			if dex_state != null:
				sync_state_changed.emit(dex_state)

## Save current state to history
func _save_to_history() -> void:
	_history.append(_state.duplicate(true))

	# Limit history size
	if _history.size() > _max_history_size:
		_history.remove_at(0)

# Convenience methods for common state operations

## Set authentication state
func set_authenticated(is_auth: bool, user_data: Dictionary = {}, tokens: Dictionary = {}) -> void:
	batch_update({
		"auth.is_authenticated": is_auth,
		"auth.user": user_data if not user_data.is_empty() else null,
		"auth.tokens": tokens if not tokens.is_empty() else {"access": "", "refresh": ""}
	})

## Set loading state
func set_loading(is_loading: bool) -> void:
	set_state("ui.is_loading", is_loading)

## Set error state
func set_error(error: Variant) -> void:
	set_state("ui.error", error)

## Clear error
func clear_error() -> void:
	set_state("ui.error", null)

## Update dex state
func update_dex_state(user_id: String, total_entries: int, last_sync: int) -> void:
	batch_update({
		"dex.current_user_id": user_id,
		"dex.total_entries": total_entries,
		"dex.last_sync": last_sync
	})

## Update social state
func update_social_state(friends_count: int, pending_count: int) -> void:
	batch_update({
		"social.friends_count": friends_count,
		"social.pending_requests": pending_count
	})

## Update camera state
func update_camera_state(state: String, job_id: String = "") -> void:
	batch_update({
		"camera.current_state": state,
		"camera.analysis_job_id": job_id if job_id != "" else null
	})
