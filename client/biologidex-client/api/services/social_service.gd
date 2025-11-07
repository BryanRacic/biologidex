extends BaseService
class_name SocialService

## SocialService - Friend management operations

signal friends_list_received(friends: Array)
signal friends_list_failed(error: APITypes.APIError)
signal pending_requests_received(requests: Array)
signal pending_requests_failed(error: APITypes.APIError)
signal friend_request_sent(request_data: Dictionary)
signal friend_request_failed(error: APITypes.APIError)
signal friendship_responded(response_data: Dictionary)
signal friendship_response_failed(error: APITypes.APIError)
signal friend_removed(friendship_id: int)
signal friend_removal_failed(error: APITypes.APIError)

## Get friends list
func get_friends(callback: Callable = Callable()) -> void:
	_log("Getting friends list")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_SOCIAL["friends"],
		_on_get_friends_success.bind(context),
		_on_get_friends_error.bind(context),
		req_config
	)

func _on_get_friends_success(response: Dictionary, context: Dictionary) -> void:
	var friends = response.get("results", [])
	_log("Received %d friends" % friends.size())
	friends_list_received.emit(friends)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_friends_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_friends")
	friends_list_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get pending friend requests
func get_pending_requests(callback: Callable = Callable()) -> void:
	_log("Getting pending friend requests")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_SOCIAL["pending"],
		_on_get_pending_requests_success.bind(context),
		_on_get_pending_requests_error.bind(context),
		req_config
	)

func _on_get_pending_requests_success(response: Dictionary, context: Dictionary) -> void:
	var requests = response.get("results", [])
	_log("Received %d pending requests" % requests.size())
	pending_requests_received.emit(requests)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_pending_requests_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_pending_requests")
	pending_requests_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Send friend request by friend_code or user_id
func send_friend_request(
	friend_code: String = "",
	user_id: int = 0,
	callback: Callable = Callable()
) -> void:
	if friend_code.is_empty() and user_id == 0:
		var error = APITypes.APIError.new(400, "Must provide friend_code or user_id", "Invalid parameters")
		friend_request_failed.emit(error)
		if callback:
			callback.call({"error": error.message}, error.code)
		return

	_log("Sending friend request (friend_code: %s, user_id: %d)" % [friend_code, user_id])

	var data = {}
	if not friend_code.is_empty():
		data["friend_code"] = friend_code
	if user_id > 0:
		data["to_user_id"] = user_id

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_SOCIAL["send_request"],
		data,
		_on_send_friend_request_success.bind(context),
		_on_send_friend_request_error.bind(context),
		req_config
	)

func _on_send_friend_request_success(response: Dictionary, context: Dictionary) -> void:
	_log("Friend request sent successfully")
	friend_request_sent.emit(response)
	if context.callback:
		context.callback.call(response, 200)

func _on_send_friend_request_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "send_friend_request")
	friend_request_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Respond to friend request (accept/reject/block)
func respond_to_request(
	friendship_id: int,
	action: String,
	callback: Callable = Callable()
) -> void:
	if not action in ["accept", "reject", "block"]:
		var error = APITypes.APIError.new(400, "Invalid action. Must be accept, reject, or block", "Invalid action")
		friendship_response_failed.emit(error)
		if callback:
			callback.call({"error": error.message}, error.code)
		return

	_log("Responding to friend request %d: %s" % [friendship_id, action])

	var endpoint = _format_endpoint(config.ENDPOINTS_SOCIAL["respond"], [str(friendship_id)])
	var data = {"action": action}

	var req_config = _create_request_config()

	var context = {"action": action, "callback": callback}

	api_client.post(
		endpoint,
		data,
		_on_respond_to_request_success.bind(context),
		_on_respond_to_request_error.bind(context),
		req_config
	)

func _on_respond_to_request_success(response: Dictionary, context: Dictionary) -> void:
	_log("Friend request response successful: %s" % context.action)
	friendship_responded.emit(response)
	if context.callback:
		context.callback.call(response, 200)

func _on_respond_to_request_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "respond_to_request")
	friendship_response_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Unfriend (remove friendship)
func unfriend(friendship_id: int, callback: Callable = Callable()) -> void:
	_log("Removing friendship: %d" % friendship_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_SOCIAL["unfriend"], [str(friendship_id)])

	var req_config = _create_request_config()

	var context = {"friendship_id": friendship_id, "callback": callback}

	api_client.delete(
		endpoint,
		_on_unfriend_success.bind(context),
		_on_unfriend_error.bind(context),
		req_config
	)

func _on_unfriend_success(response: Dictionary, context: Dictionary) -> void:
	_log("Friend removed successfully")
	friend_removed.emit(context.friendship_id)
	if context.callback:
		context.callback.call(response, 200)

func _on_unfriend_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "unfriend")
	friend_removal_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)
