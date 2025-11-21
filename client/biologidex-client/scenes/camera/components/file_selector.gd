extends Node
class_name FileSelector

# File selection component - handles web file access and editor test images
# Emits signals when files are loaded

signal file_selected(file_name: String, file_type: String, file_data: PackedByteArray)
signal file_load_progress(bytes_loaded: int, bytes_total: int)
signal file_load_error(error_message: String)
signal file_load_cancelled

# Test images for editor mode
const TEST_IMAGES: Array[String] = [
	"res://resources/test_img.jpeg",
	"res://resources/test_img2.jpeg",
	"res://resources/test_img3.jpeg",
	"res://resources/test_img4.jpeg",
	"res://resources/test_img5.jpeg"
]

var file_access_web: FileAccessWeb
var current_test_image_index: int = 0
var is_editor_mode: bool = false
var is_web_mode: bool = false


func _ready() -> void:
	_initialize_platform()


func _initialize_platform() -> void:
	"""Initialize based on platform"""
	if OS.has_feature("editor"):
		is_editor_mode = true
		print("[FileSelector] Editor mode initialized with ", TEST_IMAGES.size(), " test images")
	elif OS.get_name() == "Web":
		is_web_mode = true
		file_access_web = FileAccessWeb.new()
		file_access_web.load_started.connect(_on_web_file_load_started)
		file_access_web.loaded.connect(_on_web_file_loaded)
		file_access_web.progress.connect(_on_web_file_progress)
		file_access_web.error.connect(_on_web_file_error)
		file_access_web.upload_cancelled.connect(_on_web_file_cancelled)
		print("[FileSelector] Web mode initialized")
	else:
		print("[FileSelector] WARNING: Unsupported platform for file selection")


func open_file_picker() -> void:
	"""Open file picker (platform-dependent)"""
	if is_editor_mode:
		_load_test_image()
	elif is_web_mode:
		print("[FileSelector] Opening web file picker...")
		file_access_web.open("image/*")
	else:
		print("[FileSelector] ERROR: Cannot open file picker on this platform")
		file_load_error.emit("File selection not supported on this platform")


func _load_test_image() -> void:
	"""Load test image in editor mode"""
	if current_test_image_index >= TEST_IMAGES.size():
		print("[FileSelector] All test images cycled. Resetting to first image.")
		current_test_image_index = 0

	var image_path = TEST_IMAGES[current_test_image_index]
	print("[FileSelector] Loading test image: ", image_path, " (", current_test_image_index + 1, "/", TEST_IMAGES.size(), ")")

	# Load file data
	var file = FileAccess.open(image_path, FileAccess.READ)
	if not file:
		print("[FileSelector] ERROR: Could not load test image: ", image_path)
		file_load_error.emit("Could not load test image")
		return

	var file_data = file.get_buffer(file.get_length())
	var file_name = image_path.get_file()
	var file_type = "image/jpeg"
	file.close()

	print("[FileSelector] Test image loaded: ", file_name, " (", file_data.size(), " bytes)")
	file_selected.emit(file_name, file_type, file_data)


func cycle_test_image() -> void:
	"""Move to next test image (editor mode only)"""
	if is_editor_mode:
		current_test_image_index += 1


# Web file access callbacks
func _on_web_file_load_started(file_name: String) -> void:
	print("[FileSelector] Web file load started: ", file_name)


func _on_web_file_loaded(file_name: String, file_type: String, base64_data: String) -> void:
	"""Called when web file is fully loaded"""
	print("[FileSelector] Web file loaded: ", file_name, " Type: ", file_type)

	# Convert base64 to binary
	var file_data = Marshalls.base64_to_raw(base64_data)
	print("[FileSelector] Converted to binary: ", file_data.size(), " bytes")

	file_selected.emit(file_name, file_type, file_data)


func _on_web_file_progress(bytes_loaded: int, bytes_total: int) -> void:
	file_load_progress.emit(bytes_loaded, bytes_total)


func _on_web_file_error(error_msg: String) -> void:
	print("[FileSelector] Web file error: ", error_msg)
	file_load_error.emit(error_msg)


func _on_web_file_cancelled() -> void:
	print("[FileSelector] Web file selection cancelled")
	file_load_cancelled.emit()