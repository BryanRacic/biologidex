class_name ClipboardHelper
extends RefCounted
## Cross-platform clipboard utility supporting desktop and web exports.
## Uses DisplayServer for desktop and JavaScriptBridge for web.


static func copy_to_clipboard(text: String) -> bool:
	"""Copy text to system clipboard. Returns true on success."""
	if text.is_empty():
		return false

	if OS.has_feature("web"):
		return _copy_web(text)
	else:
		return _copy_desktop(text)


static func _copy_desktop(text: String) -> bool:
	"""Copy using DisplayServer (desktop platforms)."""
	DisplayServer.clipboard_set(text)
	# Verify the copy worked
	return DisplayServer.clipboard_get() == text


static func _copy_web(text: String) -> bool:
	"""Copy using JavaScript Clipboard API (web platform)."""
	# Use JavaScriptBridge to access navigator.clipboard
	# Note: This requires user interaction (click) to work due to browser security
	var js_code := """
		(function() {
			try {
				navigator.clipboard.writeText('%s').then(function() {
					console.log('Copied to clipboard: %s');
				}).catch(function(err) {
					console.error('Clipboard write failed:', err);
					// Fallback: try execCommand
					var textArea = document.createElement('textarea');
					textArea.value = '%s';
					textArea.style.position = 'fixed';
					textArea.style.left = '-999999px';
					document.body.appendChild(textArea);
					textArea.select();
					document.execCommand('copy');
					document.body.removeChild(textArea);
				});
				return true;
			} catch (e) {
				console.error('Clipboard error:', e);
				return false;
			}
		})()
	""" % [text.c_escape(), text.c_escape(), text.c_escape()]

	var result = JavaScriptBridge.eval(js_code)
	return result == true


static func get_from_clipboard() -> String:
	"""Get text from system clipboard. May be empty on web due to security restrictions."""
	if OS.has_feature("web"):
		# Web clipboard read is heavily restricted by browsers
		# Only works in specific contexts (user gesture + permissions)
		return ""
	else:
		return DisplayServer.clipboard_get()
