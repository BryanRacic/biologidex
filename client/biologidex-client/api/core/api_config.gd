extends RefCounted
class_name APIConfig

## APIConfig - Centralized API configuration and endpoints
## Contains all API endpoints, timeouts, and configuration constants

# Base URL for all API requests
const BASE_URL = "https://biologidex.io/api/v1"

# Timeouts (in seconds)
const DEFAULT_TIMEOUT = 30.0
const UPLOAD_TIMEOUT = 60.0
const LONG_POLL_TIMEOUT = 45.0

# Retry configuration
const MAX_RETRIES = 3
const BASE_RETRY_DELAY = 1.0
const MAX_RETRY_DELAY = 30.0

# Request queue configuration
const MAX_CONCURRENT_REQUESTS = 3

# Authentication endpoints
const ENDPOINTS_AUTH = {
	"login": "/auth/login/",
	"refresh": "/auth/refresh/",
}

# User endpoints
const ENDPOINTS_USER = {
	"register": "/users/",
	"me": "/users/me/",
	"friend_code": "/users/friend-code/",
	"lookup_friend_code": "/users/lookup_friend_code/",
}

# Vision/CV endpoints
const ENDPOINTS_VISION = {
	"jobs": "/vision/jobs/",
	"job_detail": "/vision/jobs/%s/",  # Format with job ID
	"completed": "/vision/jobs/completed/",
	"retry": "/vision/jobs/%s/retry/",  # Format with job ID
}

# Dex endpoints
const ENDPOINTS_DEX = {
	"entries": "/dex/entries/",
	"my_entries": "/dex/entries/my_entries/",
	"favorites": "/dex/entries/favorites/",
	"toggle_favorite": "/dex/entries/%s/toggle_favorite/",  # Format with entry ID
	"sync": "/dex/entries/sync_entries/",
}

# Social endpoints
const ENDPOINTS_SOCIAL = {
	"friends": "/social/friendships/friends/",
	"pending": "/social/friendships/pending/",
	"send_request": "/social/friendships/send_request/",
	"respond": "/social/friendships/%s/respond/",  # Format with friendship ID
	"unfriend": "/social/friendships/%s/unfriend/",  # Format with friendship ID
}

# Tree/Graph endpoints
const ENDPOINTS_TREE = {
	"tree": "/graph/tree/",
	"chunk": "/graph/tree/chunk/%d/%d/",  # Format with x, y
	"search": "/graph/tree/search/",
	"invalidate": "/graph/tree/invalidate/",
	"friends": "/graph/tree/friends/",
}

# Animals endpoints
const ENDPOINTS_ANIMALS = {
	"list": "/animals/",
	"lookup_or_create": "/animals/lookup_or_create/",
}

## Build full URL from endpoint path
func build_url(endpoint: String) -> String:
	if endpoint.begins_with("http"):
		return endpoint
	return BASE_URL + endpoint

## Build URL with query parameters
func build_url_with_params(endpoint: String, params: Dictionary) -> String:
	var url = build_url(endpoint)

	if params.size() > 0:
		var param_strings = []
		for key in params:
			var value = params[key]
			# Convert value to string if needed
			var value_str = str(value) if typeof(value) != TYPE_STRING else value
			param_strings.append("%s=%s" % [key, value_str])
		url += "?" + "&amp;".join(param_strings)

	return url

## Get retry delay with exponential backoff and jitter
func get_retry_delay(attempt: int) -> float:
	var delay = min(BASE_RETRY_DELAY * pow(2, attempt), MAX_RETRY_DELAY)
	return delay * randf_range(0.8, 1.2)