class_name ErrorHandler extends Node

# Centralized error handling utility
# Provides error classification, logging, retry strategies, and user-friendly messages

enum ErrorSeverity {
	INFO,       # Informational message
	WARNING,    # Warning but not critical
	ERROR,      # Error that affects operation
	CRITICAL    # Critical error requiring immediate attention
}

enum ErrorCategory {
	NETWORK,       # Network connectivity issues
	API,           # Server API errors
	VALIDATION,    # Client-side validation
	TIMEOUT,       # Request timeout
	AUTHENTICATION,  # Auth errors
	PERMISSION,    # Permission denied
	NOT_FOUND,     # Resource not found
	SERVER,        # Server-side error
	CLIENT,        # Client-side error
	UNKNOWN        # Unknown error type
}

# HTTP status code ranges
const CLIENT_ERROR_MIN = 400
const CLIENT_ERROR_MAX = 499
const SERVER_ERROR_MIN = 500
const SERVER_ERROR_MAX = 599

# Retry configuration
const MAX_RETRIES = 3
const BASE_RETRY_DELAY = 1.0  # seconds
const MAX_RETRY_DELAY = 30.0  # seconds


# ============================================================================
# Error Classification
# ============================================================================

static func classify_error(code: int, message: String, context: String = "") -> Dictionary:
	"""
	Classify an error and return structured error information.

	Returns:
		{
			"code": int,
			"message": String,
			"category": ErrorCategory,
			"severity": ErrorSeverity,
			"retryable": bool,
			"context": String,
			"user_message": String,
			"timestamp": float
		}
	"""
	var error = {
		"code": code,
		"message": message,
		"context": context,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Determine category based on HTTP code
	var category = _categorize_by_code(code)
	error["category"] = category

	# Determine severity
	error["severity"] = _determine_severity(code, category)

	# Check if retryable
	error["retryable"] = is_retryable(error)

	# Generate user-friendly message
	error["user_message"] = get_user_message(error)

	return error


static func _categorize_by_code(code: int) -> ErrorCategory:
	"""Categorize error by HTTP status code"""
	match code:
		0:
			return ErrorCategory.NETWORK
		401, 403:
			return ErrorCategory.AUTHENTICATION
		404:
			return ErrorCategory.NOT_FOUND
		408, 504:
			return ErrorCategory.TIMEOUT
		_:
			if code >= CLIENT_ERROR_MIN and code <= CLIENT_ERROR_MAX:
				return ErrorCategory.CLIENT
			elif code >= SERVER_ERROR_MIN and code <= SERVER_ERROR_MAX:
				return ErrorCategory.SERVER
			else:
				return ErrorCategory.UNKNOWN


static func _determine_severity(code: int, category: ErrorCategory) -> ErrorSeverity:
	"""Determine error severity"""
	match category:
		ErrorCategory.NETWORK, ErrorCategory.TIMEOUT:
			return ErrorSeverity.WARNING
		ErrorCategory.AUTHENTICATION:
			return ErrorSeverity.ERROR
		ErrorCategory.SERVER:
			return ErrorSeverity.CRITICAL
		ErrorCategory.NOT_FOUND:
			return ErrorSeverity.WARNING
		_:
			if code >= SERVER_ERROR_MIN:
				return ErrorSeverity.CRITICAL
			elif code >= CLIENT_ERROR_MIN:
				return ErrorSeverity.ERROR
			else:
				return ErrorSeverity.WARNING


# ============================================================================
# Retry Logic
# ============================================================================

static func is_retryable(error: Dictionary) -> bool:
	"""
	Determine if an error is retryable.

	Retryable errors:
	- Network errors (code 0)
	- Timeout errors (408, 504)
	- Server errors (500-599) except 501 Not Implemented
	- Rate limiting (429)
	"""
	var code = error.get("code", 0)
	var category = error.get("category", ErrorCategory.UNKNOWN)

	match category:
		ErrorCategory.NETWORK, ErrorCategory.TIMEOUT:
			return true
		ErrorCategory.SERVER:
			return code != 501  # Not Implemented is not retryable
		_:
			return code == 429  # Rate limited


static func get_retry_delay(attempt: int, exponential: bool = true) -> float:
	"""
	Calculate retry delay with exponential backoff.

	Args:
		attempt: Current retry attempt (0-indexed)
		exponential: Use exponential backoff if true, linear if false

	Returns:
		Delay in seconds
	"""
	if exponential:
		# Exponential backoff: 1s, 2s, 4s, 8s...
		var delay = BASE_RETRY_DELAY * pow(2, attempt)
		return min(delay, MAX_RETRY_DELAY)
	else:
		# Linear backoff: 1s, 2s, 3s, 4s...
		var delay = BASE_RETRY_DELAY * (attempt + 1)
		return min(delay, MAX_RETRY_DELAY)


static func should_retry(error: Dictionary, current_attempt: int) -> bool:
	"""Check if error should be retried based on current attempt"""
	return is_retryable(error) and current_attempt < MAX_RETRIES


# ============================================================================
# User-Friendly Messages
# ============================================================================

static func get_user_message(error: Dictionary) -> String:
	"""
	Generate a user-friendly error message.

	Args:
		error: Error dictionary from classify_error()

	Returns:
		User-friendly error message
	"""
	var code = error.get("code", 0)
	var category = error.get("category", ErrorCategory.UNKNOWN)
	var message = error.get("message", "")

	# Generate message based on category
	match category:
		ErrorCategory.NETWORK:
			return "Connection failed. Please check your internet connection and try again."

		ErrorCategory.TIMEOUT:
			return "The request timed out. Please try again."

		ErrorCategory.AUTHENTICATION:
			if code == 401:
				return "Your session has expired. Please log in again."
			elif code == 403:
				return "You don't have permission to perform this action."
			else:
				return "Authentication failed. Please log in again."

		ErrorCategory.NOT_FOUND:
			return "The requested resource was not found."

		ErrorCategory.VALIDATION:
			return "Invalid input: %s" % message

		ErrorCategory.SERVER:
			if code == 500:
				return "Server error. Please try again later."
			elif code == 503:
				return "Service temporarily unavailable. Please try again later."
			else:
				return "Server error (code %d). Please try again." % code

		ErrorCategory.CLIENT:
			if code == 400:
				return "Invalid request: %s" % message
			elif code == 429:
				return "Too many requests. Please wait a moment and try again."
			else:
				return "Request failed: %s" % message

		_:
			if not message.is_empty():
				return message
			else:
				return "An unexpected error occurred. Please try again."


static func get_recovery_suggestion(error: Dictionary) -> String:
	"""Get suggested recovery action for error"""
	var category = error.get("category", ErrorCategory.UNKNOWN)

	match category:
		ErrorCategory.NETWORK:
			return "Check your internet connection"
		ErrorCategory.TIMEOUT:
			return "Try again with a better connection"
		ErrorCategory.AUTHENTICATION:
			return "Log in again"
		ErrorCategory.SERVER:
			return "Wait a moment and try again"
		ErrorCategory.CLIENT:
			return "Check your input and try again"
		_:
			return "Try again later"


# ============================================================================
# Logging
# ============================================================================

static func log_error(error: Dictionary, severity: ErrorSeverity = ErrorSeverity.ERROR) -> void:
	"""
	Log an error with appropriate severity.

	Args:
		error: Error dictionary from classify_error()
		severity: Optional severity override
	"""
	var code = error.get("code", 0)
	var message = error.get("message", "")
	var context = error.get("context", "")
	var category = error.get("category", ErrorCategory.UNKNOWN)

	var log_msg = "[ErrorHandler] [%s] Code %d: %s" % [
		_category_to_string(category),
		code,
		message
	]

	if not context.is_empty():
		log_msg += " (Context: %s)" % context

	match severity:
		ErrorSeverity.INFO:
			print(log_msg)
		ErrorSeverity.WARNING:
			push_warning(log_msg)
		ErrorSeverity.ERROR, ErrorSeverity.CRITICAL:
			push_error(log_msg)


static func _category_to_string(category: ErrorCategory) -> String:
	"""Convert ErrorCategory to string"""
	match category:
		ErrorCategory.NETWORK:
			return "NETWORK"
		ErrorCategory.API:
			return "API"
		ErrorCategory.VALIDATION:
			return "VALIDATION"
		ErrorCategory.TIMEOUT:
			return "TIMEOUT"
		ErrorCategory.AUTHENTICATION:
			return "AUTH"
		ErrorCategory.PERMISSION:
			return "PERMISSION"
		ErrorCategory.NOT_FOUND:
			return "NOT_FOUND"
		ErrorCategory.SERVER:
			return "SERVER"
		ErrorCategory.CLIENT:
			return "CLIENT"
		_:
			return "UNKNOWN"


# ============================================================================
# Error Context
# ============================================================================

static func create_error_context(operation: String, details: Dictionary = {}) -> String:
	"""Create a context string for error logging"""
	var context = operation
	if not details.is_empty():
		var detail_parts: Array[String] = []
		for key in details:
			detail_parts.append("%s=%s" % [key, details[key]])
		context += " {%s}" % ", ".join(detail_parts)
	return context