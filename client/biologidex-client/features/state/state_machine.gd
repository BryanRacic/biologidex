class_name StateMachine extends Node

# Generic reusable state machine component
# Can be used for camera workflow, analysis jobs, UI flows, etc.

signal state_changed(old_state: int, new_state: int)
signal state_entered(state: int)
signal state_exited(state: int)

# Configuration
@export var initial_state: int = 0
@export var enable_history: bool = true
@export var max_history_size: int = 50
@export var enable_logging: bool = true

# State tracking
var current_state: int = -1
var previous_state: int = -1
var state_history: Array[int] = []
var state_entry_time: float = 0.0
var state_data: Dictionary = {}  # Store arbitrary data per state

# State names for debugging (optional)
var state_names: Dictionary = {}

# Transition validation (optional)
var valid_transitions: Dictionary = {}  # { from_state: [valid_to_states] }


func _ready() -> void:
	if current_state == -1:
		transition_to(initial_state)


# ============================================================================
# Core State Management
# ============================================================================

func transition_to(new_state: int, force: bool = false) -> bool:
	"""
	Transition to a new state with validation.
	Returns true if transition was successful.
	"""
	# Check if already in that state
	if current_state == new_state and not force:
		if enable_logging:
			_log("Already in state %s, ignoring transition" % _get_state_name(new_state))
		return false

	# Validate transition if rules are defined
	if not force and not _is_valid_transition(current_state, new_state):
		if enable_logging:
			_log_error("Invalid transition: %s -> %s" % [_get_state_name(current_state), _get_state_name(new_state)])
		return false

	# Perform transition
	var old_state = current_state
	previous_state = old_state

	# Exit old state
	if old_state != -1:
		state_exited.emit(old_state)
		_on_state_exit(old_state)

	# Update state
	current_state = new_state
	state_entry_time = Time.get_ticks_msec() / 1000.0

	# Add to history
	if enable_history:
		state_history.append(new_state)
		if state_history.size() > max_history_size:
			state_history.pop_front()

	# Emit signals
	state_changed.emit(old_state, new_state)
	state_entered.emit(new_state)

	if enable_logging:
		_log("State transition: %s -> %s" % [_get_state_name(old_state), _get_state_name(new_state)])

	# Enter new state
	_on_state_enter(new_state)

	return true


func get_current_state() -> int:
	"""Get the current state value"""
	return current_state


func get_previous_state() -> int:
	"""Get the previous state value"""
	return previous_state


func is_in_state(state: int) -> bool:
	"""Check if currently in a specific state"""
	return current_state == state


func is_in_any_state(states: Array[int]) -> bool:
	"""Check if currently in any of the given states"""
	return current_state in states


func get_time_in_current_state() -> float:
	"""Get seconds spent in current state"""
	return (Time.get_ticks_msec() / 1000.0) - state_entry_time


# ============================================================================
# State Data Management
# ============================================================================

func set_state_data(key: String, value: Variant) -> void:
	"""Store arbitrary data associated with current state"""
	if not state_data.has(current_state):
		state_data[current_state] = {}
	state_data[current_state][key] = value


func get_state_data(key: String, default_value: Variant = null) -> Variant:
	"""Get data associated with current state"""
	if state_data.has(current_state) and state_data[current_state].has(key):
		return state_data[current_state][key]
	return default_value


func clear_state_data(state: int = -1) -> void:
	"""Clear data for a specific state (or current state if not specified)"""
	var target_state = state if state != -1 else current_state
	if state_data.has(target_state):
		state_data.erase(target_state)


# ============================================================================
# History Management
# ============================================================================

func get_state_history() -> Array[int]:
	"""Get array of state history"""
	return state_history.duplicate()


func clear_history() -> void:
	"""Clear state history"""
	state_history.clear()


func can_go_back() -> bool:
	"""Check if we can return to previous state"""
	return previous_state != -1


func go_back() -> bool:
	"""Return to previous state"""
	if not can_go_back():
		return false
	return transition_to(previous_state)


# ============================================================================
# Transition Validation
# ============================================================================

func set_valid_transitions(from_state: int, to_states: Array[int]) -> void:
	"""Define valid transitions from a state"""
	valid_transitions[from_state] = to_states


func clear_transition_rules() -> void:
	"""Remove all transition validation rules"""
	valid_transitions.clear()


func _is_valid_transition(from_state: int, to_state: int) -> bool:
	"""Check if transition is valid according to rules"""
	# No rules defined = all transitions valid
	if valid_transitions.is_empty():
		return true

	# No rule for this state = all transitions valid from this state
	if not valid_transitions.has(from_state):
		return true

	# Check if to_state is in valid list
	return to_state in valid_transitions[from_state]


# ============================================================================
# State Naming (for debugging)
# ============================================================================

func set_state_name(state: int, name: String) -> void:
	"""Assign a name to a state for logging"""
	state_names[state] = name


func set_state_names(names: Dictionary) -> void:
	"""Assign names to multiple states"""
	state_names = names.duplicate()


func _get_state_name(state: int) -> String:
	"""Get state name or numeric value"""
	if state == -1:
		return "NONE"
	if state_names.has(state):
		return state_names[state]
	return str(state)


# ============================================================================
# Virtual Methods (override in subclasses if needed)
# ============================================================================

func _on_state_enter(state: int) -> void:
	"""Override to handle state entry"""
	pass


func _on_state_exit(state: int) -> void:
	"""Override to handle state exit"""
	pass


# ============================================================================
# Logging
# ============================================================================

func _log(message: String) -> void:
	"""Log a message"""
	if enable_logging:
		print("[StateMachine] %s" % message)


func _log_error(message: String) -> void:
	"""Log an error"""
	push_error("[StateMachine] %s" % message)


# ============================================================================
# Reset
# ============================================================================

func reset() -> void:
	"""Reset state machine to initial state"""
	clear_history()
	state_data.clear()
	transition_to(initial_state, true)