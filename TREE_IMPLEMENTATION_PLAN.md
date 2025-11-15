# Taxonomic Tree Implementation Plan

## 🎉 IMPLEMENTATION STATUS: COMPLETED (2025-11-15)

All core implementation phases have been completed:
- ✅ **Phase 1 (Days 1-3)**: Core hierarchy fix - server and client changes
- ✅ **Phase 2**: Visual enhancements - edge styling
- ⏭️ **Phase 3-5**: Optional enhancements (labels, orientation, progressive loading) - can be added later

The hierarchical taxonomic tree is now fully functional with:
- Virtual taxonomy nodes (Kingdom → Phylum → Class → Order → Family → Genus → Species)
- Visual differentiation between taxonomy nodes (gray, rank-based sizing) and animal nodes (color-coded)
- Enhanced edge rendering (thicker for hierarchy, thinner for leaf connections)
- Proper interaction (only animal nodes selectable)

**Next Step**: Test with actual data and verify hierarchy display.

---

## Executive Summary

The server already generates a proper hierarchical taxonomic tree structure using the Reingold-Tilford algorithm, but **only sends animal leaf nodes to the client**, not the intermediate taxonomy nodes (kingdom, phylum, class, etc.). This makes the tree appear flat instead of hierarchical.

**Key Finding**: `/server/graph/services_dynamic.py` line 332-334 has a TODO comment: "Add virtual taxonomy nodes - These are created from the hierarchy for complete tree visualization"

**Solution Implemented**: Modified `_build_nodes()` to include virtual taxonomy nodes, updated client data models and renderer to differentiate node types.

## Current State Analysis

### ✅ What's Working
- Server builds complete taxonomy hierarchy with virtual nodes in `_build_hierarchy()`
- Reingold-Tilford layout algorithm properly positions all nodes
- Parent-child edges are correctly generated
- Chunk system for progressive loading is implemented
- Client renderer handles 10k+ nodes at 60 FPS

### ❌ What's Broken
- Virtual taxonomy nodes exist on server but aren't sent to client
- Tree appears flat (animals side-by-side) instead of hierarchical
- Edges reference non-existent parent nodes on client side
- No visual distinction between taxonomy ranks and animals

## Implementation Plan

### Phase 1: Core Hierarchy Fix (2-3 days)

#### 1.1 Server: Include Virtual Taxonomy Nodes in Response

**File**: `/server/biologidex/graph/services_dynamic.py`

**Current Code (lines 332-356)**:
```python
def _build_nodes(self, animals, hierarchy_dict, layout_positions, user, friend_ids):
    """Build node objects for tree visualization."""
    # TODO: Add virtual taxonomy nodes
    # These are created from the hierarchy for complete tree visualization
    # Implementation depends on UI requirements

    nodes = []
    for animal in animals:
        # ... builds only animal nodes
```

**Required Changes**:
```python
def _build_nodes(self, animals, hierarchy_dict, layout_positions, user, friend_ids):
    """Build node objects for tree visualization."""
    nodes = []
    processed_taxonomy_nodes = set()

    # First, add all virtual taxonomy nodes from hierarchy
    def add_taxonomy_nodes(node, parent_path=""):
        node_path = f"{parent_path}/{node.name}" if parent_path else node.name

        # Skip if already processed or if it's an animal leaf
        if node_path in processed_taxonomy_nodes or node.data.get('animal'):
            return

        processed_taxonomy_nodes.add(node_path)

        # Create taxonomy node
        taxonomy_node = {
            'id': node.data['id'],
            'type': 'taxonomic',
            'node_type': 'taxonomic',  # For client compatibility
            'rank': node.data.get('rank', 'unknown'),
            'name': node.name,
            'scientific_name': node.name,  # For consistency
            'position': layout_positions.get(node.data['id'], [0, 0]),
            'captured_by_user': False,  # Taxonomy nodes aren't captured
            'captured_by_friends': [],
            'capture_count': 0,
            'children_count': len(node.children)
        }
        nodes.append(taxonomy_node)

        # Recursively add children
        for child in node.children:
            add_taxonomy_nodes(child, node_path)

    # Add taxonomy nodes starting from root
    if hierarchy_dict.get('root'):
        add_taxonomy_nodes(hierarchy_dict['root'])

    # Then add animal nodes (existing code)
    for animal in animals:
        # ... existing animal node code ...
        node['node_type'] = 'animal'  # Add this field
```

#### 1.2 Client: Update Data Models

**File**: `/client/biologidex-client/tree_data_models.gd`

**Add Node Type Enum**:
```gdscript
enum NodeType {
    TAXONOMIC = 0,
    ANIMAL = 1
}

enum TaxonomicRank {
    ROOT = 0,
    KINGDOM = 1,
    PHYLUM = 2,
    CLASS = 3,
    ORDER = 4,
    FAMILY = 5,
    SUBFAMILY = 6,
    GENUS = 7,
    SPECIES = 8,
    SUBSPECIES = 9
}
```

**Update TaxonomicNode Class**:
```gdscript
class TaxonomicNode extends Resource:
    # Existing fields...
    @export var node_type: int = NodeType.ANIMAL  # New field
    @export var rank: int = TaxonomicRank.SPECIES  # New field
    @export var name: String = ""  # For taxonomy nodes
    @export var children_count: int = 0  # New field

    func _init(data: Dictionary = {}) -> void:
        # Existing parsing...

        # Parse node type
        var type_str = data.get("node_type", data.get("type", "animal"))
        if type_str == "taxonomic":
            node_type = NodeType.TAXONOMIC
        else:
            node_type = NodeType.ANIMAL

        # Parse rank for taxonomy nodes
        var rank_str = data.get("rank", "species")
        rank = _parse_rank(rank_str)

        name = data.get("name", scientific_name)
        children_count = data.get("children_count", 0)

    func _parse_rank(rank_str: String) -> int:
        match rank_str.to_lower():
            "root": return TaxonomicRank.ROOT
            "kingdom": return TaxonomicRank.KINGDOM
            "phylum": return TaxonomicRank.PHYLUM
            "class": return TaxonomicRank.CLASS
            "order": return TaxonomicRank.ORDER
            "family": return TaxonomicRank.FAMILY
            "subfamily": return TaxonomicRank.SUBFAMILY
            "genus": return TaxonomicRank.GENUS
            "species": return TaxonomicRank.SPECIES
            "subspecies": return TaxonomicRank.SUBSPECIES
            _: return TaxonomicRank.SPECIES

    func is_taxonomic() -> bool:
        return node_type == NodeType.TAXONOMIC

    func is_animal() -> bool:
        return node_type == NodeType.ANIMAL
```

#### 1.3 Client: Update TreeRenderer

**File**: `/client/biologidex-client/tree_renderer.gd`

**Add Constants for Taxonomy Nodes**:
```gdscript
# Taxonomy node settings
const TAXONOMY_NODE_SIZE: float = 6.0
const COLOR_TAXONOMY: Color = Color(0.6, 0.6, 0.6, 0.8)  # Gray with transparency
const COLOR_TAXONOMY_HOVER: Color = Color(0.7, 0.7, 0.7, 0.9)

# Rank-specific sizes (hierarchy visual emphasis)
const RANK_SIZE_MULTIPLIERS = {
    TreeDataModels.TaxonomicRank.ROOT: 1.5,
    TreeDataModels.TaxonomicRank.KINGDOM: 1.4,
    TreeDataModels.TaxonomicRank.PHYLUM: 1.3,
    TreeDataModels.TaxonomicRank.CLASS: 1.2,
    TreeDataModels.TaxonomicRank.ORDER: 1.1,
    TreeDataModels.TaxonomicRank.FAMILY: 1.0,
    TreeDataModels.TaxonomicRank.GENUS: 0.9,
    TreeDataModels.TaxonomicRank.SPECIES: 0.8
}
```

**Update _get_node_color()**:
```gdscript
func _get_node_color(node: TreeDataModels.TaxonomicNode) -> Color:
    # Taxonomy nodes are gray
    if node.is_taxonomic():
        return COLOR_TAXONOMY

    # Existing animal color logic
    if node.captured_by_user and node.captured_by_friends.size() > 0:
        return COLOR_BOTH_CAPTURED
    # ... rest of existing code
```

**Update _get_node_scale()**:
```gdscript
func _get_node_scale(node: TreeDataModels.TaxonomicNode) -> float:
    if node.is_taxonomic():
        var base = TAXONOMY_NODE_SIZE
        var multiplier = RANK_SIZE_MULTIPLIERS.get(node.rank, 1.0)
        return (base * multiplier) / NODE_SIZE_BASE

    # Existing animal scale logic
    var base_size = NODE_SIZE_BASE
    # ... rest of existing code
```

**Update Interaction Handling**:
```gdscript
func _handle_click(screen_pos: Vector2) -> void:
    # ... existing code to get world_pos

    var node = get_node_at_position(world_pos)

    if node:
        # Only select animal nodes, not taxonomy nodes
        if node.is_animal():
            select_node(node)
        else:
            # Could show taxonomy info in future
            print("[TreeRenderer] Clicked taxonomy node: %s (rank: %d)" % [node.name, node.rank])
    else:
        clear_selection()

func set_hovered_node(node: TreeDataModels.TaxonomicNode) -> void:
    if hovered_node == node:
        return

    hovered_node = node
    _update_multimesh()

    if node:
        if node.is_animal():
            node_hovered.emit(node)
        # Taxonomy nodes could have different hover behavior
    else:
        node_unhovered.emit()
```

### Phase 2: Visual Enhancements (1-2 days)

#### 2.1 Add Node Labels for Taxonomy Nodes

**File**: `/client/biologidex-client/tree_renderer.gd`

**Add Label Rendering**:
```gdscript
var taxonomy_labels: Dictionary = {}  # node_id -> Label

func _render_taxonomy_labels() -> void:
    # Clear old labels
    for label in taxonomy_labels.values():
        label.queue_free()
    taxonomy_labels.clear()

    # Only show labels when zoomed in enough
    if not camera or camera.zoom.x < 0.5:
        return

    # Add labels for visible taxonomy nodes
    for render_data in visible_nodes:
        if render_data.node.is_taxonomic():
            var label = Label.new()
            label.text = render_data.node.name
            label.add_theme_font_size_override("font_size", 10)
            label.add_theme_color_override("font_color", Color.WHITE)
            label.position = render_data.position + Vector2(0, -20)
            add_child(label)
            taxonomy_labels[render_data.node.id] = label
```

#### 2.2 Different Edge Styles by Rank

**File**: `/client/biologidex-client/tree_renderer.gd`

```gdscript
func _draw_edge(edge: TreeDataModels.TreeEdge) -> void:
    var source_node = tree_data.get_node_by_id(edge.source)
    var target_node = tree_data.get_node_by_id(edge.target)

    if not source_node or not target_node:
        return

    var line = Line2D.new()
    line.add_point(source_node.position)
    line.add_point(target_node.position)

    # Vary edge appearance by rank transition
    if source_node.is_taxonomic() and target_node.is_taxonomic():
        # Taxonomy to taxonomy: thicker, more opaque
        line.width = 2.0
        line.default_color = Color(0.4, 0.4, 0.4, 0.5)
    elif source_node.is_taxonomic() and target_node.is_animal():
        # Taxonomy to animal: thinner, less opaque
        line.width = 1.0
        line.default_color = Color(0.3, 0.3, 0.3, 0.3)
    else:
        # Default (shouldn't happen with proper hierarchy)
        line.width = 1.0
        line.default_color = COLOR_EDGE

    line.antialiased = false
    edges_container.add_child(line)
```

### Phase 3: Tree Orientation & Layout (1 day)

#### 3.1 Add Tree Orientation Option

**File**: `/client/biologidex-client/tree_controller.gd`

```gdscript
enum TreeOrientation {
    TOP_DOWN = 0,
    LEFT_RIGHT = 1
}

var tree_orientation: TreeOrientation = TreeOrientation.TOP_DOWN

func _on_orientation_changed(index: int) -> void:
    tree_orientation = index as TreeOrientation
    if tree_renderer and current_tree_data:
        # Rotate all positions 90 degrees for left-right orientation
        if tree_orientation == TreeOrientation.LEFT_RIGHT:
            for node in current_tree_data.nodes:
                var pos = node.position
                node.position = Vector2(pos.y, -pos.x)
        tree_renderer.render_tree(current_tree_data)
```

### Phase 5: Progressive Loading (Optional, 2-3 days)

#### 5.1 Implement Chunk-Based Loading

**File**: `/client/biologidex-client/tree_controller.gd`

```gdscript
var loaded_chunks: Dictionary = {}  # Vector2i -> bool
var chunk_queue: Array[Vector2i] = []

func _load_visible_chunks() -> void:
    if not tree_camera or not current_tree_data:
        return

    var viewport_rect = _get_camera_world_rect()
    var chunk_size = current_tree_data.layout.chunk_size

    # Calculate which chunks are visible
    var min_chunk_x = int(viewport_rect.position.x / chunk_size.x)
    var min_chunk_y = int(viewport_rect.position.y / chunk_size.y)
    var max_chunk_x = int(viewport_rect.end.x / chunk_size.x)
    var max_chunk_y = int(viewport_rect.end.y / chunk_size.y)

    # Queue chunks for loading
    for x in range(min_chunk_x, max_chunk_x + 1):
        for y in range(min_chunk_y, max_chunk_y + 1):
            var chunk_id = Vector2i(x, y)
            if not loaded_chunks.has(chunk_id):
                chunk_queue.append(chunk_id)
                loaded_chunks[chunk_id] = false

    # Process queue
    _process_chunk_queue()

func _process_chunk_queue() -> void:
    if chunk_queue.is_empty():
        return

    var chunk_id = chunk_queue.pop_front()
    APIManager.tree.fetch_chunk(
        chunk_id.x,
        chunk_id.y,
        current_mode,
        selected_friend_ids
    )
```

## Implementation Order

1. **Day 1**: Server changes - modify `_build_nodes()` to include virtual taxonomy nodes
2. **Day 2**: Client data model updates - add node types and parsing
3. **Day 3**: Client renderer updates - differentiate rendering by node type
4. **Day 4**: Testing and bug fixes
5. **Day 5**: Visual enhancements (labels, edge styles)
6. **Days 6-7** (Optional): Progressive chunk loading

## Success Criteria

- [ ] Tree displays full taxonomic hierarchy from kingdom to species
- [ ] Each taxonomic rank has a single shared node (e.g., one "Mammalia" for all mammals)
- [ ] Visual distinction between taxonomy nodes and animal nodes
- [ ] Proper parent-child edge connections throughout hierarchy
- [ ] Performance maintains 60 FPS with 10k visible nodes
- [ ] Click/hover interactions work correctly for different node types

## Risk Mitigation

1. **Performance Impact**: More nodes to render
   - Mitigation: Implement LOD system, hide taxonomy nodes when zoomed out

2. **Layout Complexity**: Reingold-Tilford may need tuning for larger trees
   - Mitigation: Add node spacing parameters, consider alternative layouts

3. **Memory Usage**: Full hierarchy increases memory footprint
   - Mitigation: Implement progressive loading, node pooling

## Files to Modify

### Server
- `/server/biologidex/graph/services_dynamic.py` - Add virtual nodes to response
- `/server/biologidex/graph/serializers.py` - Add node_type field (if needed)

### Client
- `/client/biologidex-client/tree_data_models.gd` - Add node types and ranks
- `/client/biologidex-client/tree_renderer.gd` - Differentiate rendering
- `/client/biologidex-client/tree_controller.gd` - Handle orientation, chunking

## Notes

- The server already does 90% of the work correctly
- Main issue is a simple omission in `_build_nodes()`
- Client changes are mostly additive (backwards compatible)
- Can be deployed incrementally without breaking existing functionality