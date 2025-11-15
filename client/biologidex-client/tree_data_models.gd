"""
Data models for taxonomic tree visualization.
Matches server API response structure from DynamicTaxonomicTreeService.
"""
class_name TreeDataModels extends Resource

# =============================================================================
# Core Data Models
# =============================================================================

class TaxonomicNode extends Resource:
	"""
	Represents a single animal node in the tree.
	Maps to server 'nodes' array entries.
	"""
	@export var id: String = ""
	@export var type: String = "animal"  # Always "animal" for now
	@export var scientific_name: String = ""
	@export var common_name: String = ""
	@export var creation_index: int = -1

	# Taxonomy hierarchy
	@export var taxonomy: Dictionary = {}  # {kingdom, phylum, class, order, family, genus, species}

	# Position in world space
	@export var position: Vector2 = Vector2.ZERO

	# Capture info (scope-specific)
	@export var captured_by_user: bool = false
	@export var captured_by_friends: Array = []  # Array of {user_id, username, captured_at}
	@export var capture_count: int = 0

	# Additional metadata
	@export var conservation_status: String = ""
	@export var verified: bool = false
	@export var discoverer: Dictionary = {}  # {user_id, username, is_self, is_friend}

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return

		id = data.get("id", "")
		type = data.get("type", "animal")
		scientific_name = data.get("scientific_name", "")
		common_name = data.get("common_name", "")
		creation_index = data.get("creation_index", -1)
		taxonomy = data.get("taxonomy", {})

		# Parse position array to Vector2
		var pos_array = data.get("position", [0, 0])
		if pos_array is Array and pos_array.size() >= 2:
			position = Vector2(pos_array[0], pos_array[1])

		captured_by_user = data.get("captured_by_user", false)
		captured_by_friends = data.get("captured_by_friends", [])
		capture_count = data.get("capture_count", 0)
		conservation_status = data.get("conservation_status", "")
		verified = data.get("verified", false)
		discoverer = data.get("discoverer", {})


class TreeEdge extends Resource:
	"""
	Represents a parent-child edge in the tree.
	Maps to server 'edges' array entries.
	"""
	@export var source: String = ""
	@export var target: String = ""
	@export var relationship: String = "parent_child"
	@export var rank_transition: String = ""

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return

		source = data.get("source", "")
		target = data.get("target", "")
		relationship = data.get("relationship", "parent_child")
		rank_transition = data.get("rank_transition", "")


class TreeLayoutData extends Resource:
	"""
	Layout information for the entire tree.
	Maps to server 'layout' object.
	"""
	@export var positions: Dictionary = {}  # node_id -> Vector2
	@export var world_bounds: Rect2 = Rect2()
	@export var chunk_metadata: Dictionary = {}
	@export var chunk_size: Vector2 = Vector2(2048, 2048)

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return

		# Parse positions
		var positions_dict = data.get("positions", {})
		for node_id in positions_dict:
			var pos_array = positions_dict[node_id]
			if pos_array is Array and pos_array.size() >= 2:
				positions[node_id] = Vector2(pos_array[0], pos_array[1])

		# Parse world bounds - can be array [min_x, min_y, max_x, max_y] or dict
		var bounds_data = data.get("world_bounds", [])
		if bounds_data is Array and bounds_data.size() >= 4:
			# Array format: [min_x, min_y, max_x, max_y]
			var min_x = float(bounds_data[0])
			var min_y = float(bounds_data[1])
			var max_x = float(bounds_data[2])
			var max_y = float(bounds_data[3])
			world_bounds = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		elif bounds_data is Dictionary and not bounds_data.is_empty():
			# Dict format: {x, y, width, height}
			world_bounds = Rect2(
				bounds_data.get("x", 0),
				bounds_data.get("y", 0),
				bounds_data.get("width", 0),
				bounds_data.get("height", 0)
			)

		chunk_metadata = data.get("chunk_metadata", {})

		# Parse chunk size
		var chunk_size_dict = data.get("chunk_size", {"width": 2048, "height": 2048})
		chunk_size = Vector2(
			chunk_size_dict.get("width", 2048),
			chunk_size_dict.get("height", 2048)
		)


class TreeChunk extends Resource:
	"""
	A spatial chunk of tree data for progressive loading.
	"""
	@export var chunk_id: Vector2i = Vector2i.ZERO  # Grid coordinates
	@export var world_bounds: Rect2 = Rect2()
	@export var node_ids: Array[String] = []
	@export var edge_indices: Array = []  # Array of [source_id, target_id]
	@export var is_loaded: bool = false

	func _init(chunk_x: int = 0, chunk_y: int = 0, data: Dictionary = {}) -> void:
		chunk_id = Vector2i(chunk_x, chunk_y)

		if data.is_empty():
			return

		# Parse bounds
		var bounds_dict = data.get("bounds", {})
		if not bounds_dict.is_empty():
			world_bounds = Rect2(
				bounds_dict.get("x", 0),
				bounds_dict.get("y", 0),
				bounds_dict.get("width", 0),
				bounds_dict.get("height", 0)
			)

		node_ids = data.get("node_ids", [])
		edge_indices = data.get("edges", [])
		is_loaded = true


class TreeStats extends Resource:
	"""
	Statistics about the current tree.
	Maps to server 'stats' object.
	"""
	@export var total_animals: int = 0
	@export var total_nodes: int = 0
	@export var total_edges: int = 0
	@export var mode: String = ""
	@export var user_captures: int = 0
	@export var friend_captures: int = 0
	@export var unique_to_user: int = 0
	@export var shared_with_friends: int = 0

	# Taxonomic diversity
	@export var unique_kingdom: int = 0
	@export var unique_phylum: int = 0
	@export var unique_class: int = 0
	@export var unique_order: int = 0
	@export var unique_family: int = 0
	@export var unique_genus: int = 0

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return

		total_animals = data.get("total_animals", 0)
		total_nodes = data.get("total_nodes", 0)
		total_edges = data.get("total_edges", 0)
		mode = data.get("mode", "")
		user_captures = data.get("user_captures", 0)
		friend_captures = data.get("friend_captures", 0)
		unique_to_user = data.get("unique_to_user", 0)
		shared_with_friends = data.get("shared_with_friends", 0)

		unique_kingdom = data.get("unique_kingdom", 0)
		unique_phylum = data.get("unique_phylum", 0)
		unique_class = data.get("unique_class", 0)
		unique_order = data.get("unique_order", 0)
		unique_family = data.get("unique_family", 0)
		unique_genus = data.get("unique_genus", 0)


class TreeMetadata extends Resource:
	"""
	Metadata about the tree request.
	Maps to server 'metadata' object.
	"""
	@export var mode: String = ""
	@export var user_id: String = ""
	@export var username: String = ""
	@export var scoped_users: String = ""  # Number or "all"
	@export var total_nodes: int = 0
	@export var total_edges: int = 0
	@export var cache_key: String = ""

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return

		mode = data.get("mode", "")
		user_id = data.get("user_id", "")
		username = data.get("username", "")

		# Handle scoped_users which can be int or string "all"
		var scoped = data.get("scoped_users", "")
		scoped_users = str(scoped)

		total_nodes = data.get("total_nodes", 0)
		total_edges = data.get("total_edges", 0)
		cache_key = data.get("cache_key", "")


# =============================================================================
# Complete Tree Data Container
# =============================================================================

class TreeData extends Resource:
	"""
	Complete tree data response from server.
	Top-level container for all tree information.
	"""
	@export var nodes: Array[TaxonomicNode] = []
	@export var edges: Array[TreeEdge] = []
	@export var layout: TreeLayoutData
	@export var stats: TreeStats
	@export var metadata: TreeMetadata

	# Internal lookup maps for efficient querying
	var nodes_by_id: Dictionary = {}  # node_id -> TaxonomicNode
	var edges_by_source: Dictionary = {}  # source_id -> Array[TreeEdge]
	var edges_by_target: Dictionary = {}  # target_id -> Array[TreeEdge]

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			layout = TreeLayoutData.new()
			stats = TreeStats.new()
			metadata = TreeMetadata.new()
			return

		# Parse nodes
		var nodes_array = data.get("nodes", [])
		for node_dict in nodes_array:
			var node = TaxonomicNode.new(node_dict)
			nodes.append(node)
			nodes_by_id[node.id] = node

		# Parse edges
		var edges_array = data.get("edges", [])
		for edge_dict in edges_array:
			var edge = TreeEdge.new(edge_dict)
			edges.append(edge)

			# Build lookup maps
			if not edges_by_source.has(edge.source):
				edges_by_source[edge.source] = []
			edges_by_source[edge.source].append(edge)

			if not edges_by_target.has(edge.target):
				edges_by_target[edge.target] = []
			edges_by_target[edge.target].append(edge)

		# Parse layout
		layout = TreeLayoutData.new(data.get("layout", {}))

		# Parse stats
		stats = TreeStats.new(data.get("stats", {}))

		# Parse metadata
		metadata = TreeMetadata.new(data.get("metadata", {}))

	func get_node_by_id(node_id: String) -> TaxonomicNode:
		"""Get node by ID, returns null if not found."""
		return nodes_by_id.get(node_id, null)

	func get_children(node_id: String) -> Array[TaxonomicNode]:
		"""Get all child nodes of a given node."""
		var children: Array[TaxonomicNode] = []
		var child_edges = edges_by_source.get(node_id, [])
		for edge in child_edges:
			var child = get_node_by_id(edge.target)
			if child:
				children.append(child)
		return children

	func get_parent(node_id: String) -> TaxonomicNode:
		"""Get parent node of a given node."""
		var parent_edges = edges_by_target.get(node_id, [])
		if parent_edges.size() > 0:
			return get_node_by_id(parent_edges[0].source)
		return null
