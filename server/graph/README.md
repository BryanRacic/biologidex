# Graph Module - Taxonomic Tree Visualization

## Overview

The graph module provides dynamic taxonomic tree generation and visualization for BiologiDex. It builds hierarchical trees from user-captured animals and computes optimal layouts using the Walker-Buchheim algorithm.

## Components

### Layout Algorithm (`layout/reingold_tilford.py`)

**Implementation**: Walker-Buchheim O(n) algorithm for tree layout

**Key Features**:
- **O(n) linear time complexity** for n nodes
- Proper handling of m-ary trees (nodes with any number of children)
- Efficient contour threading for conflict resolution
- No node overlaps, even with multiple animals per species
- Aesthetically pleasing, compact layouts

**Aesthetic Properties**:
1. Nodes at same depth on same horizontal line
2. Parent nodes centered over children
3. Subtrees as narrow as possible without overlap
4. Identical subtrees have identical layouts
5. Left-to-right ordering preserved

**Algorithm References**:
- Reingold & Tilford (1981): "Tidier Drawings of Trees"
- Walker (1990): "A Node-Positioning Algorithm for General Trees"
- Buchheim, Jünger & Leipert (2002): "Improving Walker's Algorithm to Run in Linear Time"

**Recent Fixes** (2025-11-18):
- ✅ Fixed node overlap bug when multiple animals belong to same species
- ✅ Implemented complete Walker-Buchheim algorithm with contour threading
- ✅ Added proper parent and sibling references for O(1) sibling access
- ✅ Improved time complexity from O(n²) to O(n)
- ✅ Added subtree shifting and conflict resolution

### Dynamic Tree Service (`services_dynamic.py`)

**Class**: `DynamicTaxonomicTreeService`

**Modes**:
- `PERSONAL`: User's own dex entries only
- `FRIENDS`: User + friends' captures
- `SELECTED`: Specific user list
- `GLOBAL`: All users (admin only)

**Key Methods**:
- `get_tree_data()`: Generate complete tree with layout
- `get_chunk(x, y)`: Extract spatial chunk for progressive loading
- `search_tree(query)`: Search within current scope

**Performance**:
- Prefetch optimizations for database queries
- 5-minute cache TTL (2 minutes for friends overview)
- Spatial chunking (2048x2048 units) for large trees

### API Endpoints (`views.py`)

- `GET /api/v1/graph/tree/` - Full tree (modes: personal, friends, selected, global)
- `GET /api/v1/graph/tree/chunk/{x}/{y}/` - Progressive chunk loading
- `GET /api/v1/graph/tree/search/?q=query` - Scope-aware search
- `POST /api/v1/graph/tree/invalidate/` - Cache invalidation
- `GET /api/v1/graph/tree/friends/` - Friend stats for UI

## Tree Structure

### Node Types

**Taxonomic Nodes** (Virtual):
- Rank: kingdom, phylum, class, order, family, genus, species
- ID format: `{rank}_{name}` (e.g., `genus_Canis`)
- Contains metadata: animal_count, children_count

**Animal Nodes** (Actual):
- ID format: UUID
- Contains: scientific_name, common_name, taxonomy, capture info
- Links to discoverer and capture statistics

### Edge Types

All edges use `parent_child` relationship with `rank_transition` metadata:
- `phylum_to_class`
- `genus_to_species`
- `species_to_species` (species → individual animal)

## Layout Algorithm Details

### Tree Building (`_build_tree_nodes`)

```python
# Critical: Set parent and sibling index for each node
tree_node.parent = parent
tree_node.number = sibling_index

# For animal leaves - MUST set parent reference
animal_node.parent = tree_node  # Fixes overlap bug
animal_node.number = child_index
```

### First Walk (`_first_walk`)

Post-order traversal computing preliminary positions:
1. Process all children recursively
2. Apportion siblings to resolve conflicts
3. Execute accumulated shifts
4. Center parent over children

### Apportioning (`_apportion`)

Resolves subtree conflicts using contour threading:
- Tracks inner/outer contours of adjacent subtrees
- Calculates minimum shift to avoid overlap
- Distributes shifts among siblings
- Sets thread pointers for efficient traversal

### Second Walk (`_second_walk`)

Pre-order traversal applying modifiers to get final positions:
- Adds cumulative modifier from ancestors
- Sets final (x, y) coordinates

## Performance Characteristics

### Time Complexity
- **Layout calculation**: O(n) where n = number of nodes
- **Tree building**: O(n) with prefetch optimizations
- **Position extraction**: O(n)
- **Total**: O(n) end-to-end

### Space Complexity
- O(n) for node storage
- O(n) for position dictionary
- Minimal overhead from threading pointers

### Database Queries
- Optimized with `select_related()` and `prefetch_related()`
- Single query for animals with scoped captures
- Annotated capture counts for efficiency

## Caching Strategy

### Server-Side Cache
- **Key format**: `taxonomic_tree_{mode}_{user_id}`
- **TTL**: 5 minutes (300s) for regular modes, 2 minutes for friends overview
- **Storage**: Django cache framework (Redis in production)
- **Invalidation**: Manual via `/invalidate/` endpoint or on cache expiry

### Client-Side Cache
- Handled by `tree_cache.gd` in Godot client
- Dual-layer: memory + disk (`user://tree_cache/`)
- Version-controlled with TTL invalidation
- Chunk-based LRU eviction (max 50 chunks)

## Spatial Chunking

### Chunk Manager (`layout/chunk_manager.py`)

**Purpose**: Divide large trees into manageable spatial regions

**Chunk Size**: 2048×2048 units

**Features**:
- Assigns nodes to chunks based on position
- Edge assignment using line rasterization
- 10% padding on world bounds
- Progressive loading support

## Known Limitations & Future Work

### Current Limitations
1. Fixed spacing (100 units horizontal, 150 units vertical)
2. No variable node size support
3. No collision detection for overlapping labels

### Future Enhancements
1. Variable node sizes based on content
2. Dynamic spacing based on tree density
3. Radial/non-layered layouts for specific use cases
4. Animation support for tree transitions
5. Incremental updates (avoid full recalculation)

## Testing

### Key Test Cases
1. **Multiple animals per species** - Ensure no overlap
2. **Deep trees** - Verify O(n) performance (10,000+ nodes)
3. **Wide trees** - Nodes with many children
4. **Identical subtrees** - Should produce identical layouts
5. **Single-child chains** - Proper vertical alignment

### Performance Benchmarks
- 100 nodes: < 10ms
- 1,000 nodes: < 50ms
- 10,000 nodes: < 500ms
- 100,000 nodes: < 5s

## Troubleshooting

### Overlapping Nodes
- **Symptom**: Multiple nodes at identical positions
- **Cause**: Missing parent references or broken sibling links
- **Fix**: Ensure `node.parent` and `node.number` are set correctly

### Poor Performance
- **Symptom**: Slow layout calculation (> 1s for small trees)
- **Cause**: Missing threading or contour optimization
- **Fix**: Verify `_apportion()` is using threading correctly

### Incorrect Centering
- **Symptom**: Parents not centered over children
- **Cause**: Modifier not applied correctly
- **Fix**: Check `_execute_shifts()` processes children right-to-left

### Cache Staleness
- **Symptom**: Old tree data after new captures
- **Fix**: Call `/invalidate/` endpoint or wait for TTL expiry

## References

### Papers
- [Reingold & Tilford (1981)](https://reingold.co/tidier-drawings.pdf)
- [Buchheim et al. (2002)](https://link.springer.com/chapter/10.1007/3-540-36151-0_32)

### Implementations
- [llimllib Python implementation](http://llimllib.github.io/pymag-trees/)
- [Rachel's Algorithm Walkthrough](https://rachel53461.wordpress.com/2014/04/20/algorithm-for-drawing-trees/)
- [William Yao's Functional Approach](https://williamyaoh.com/posts/2023-04-22-drawing-trees-functionally.html)

## Changelog

### 2025-11-18
- **CRITICAL FIX**: Resolved node overlap bug for multiple animals per species
- Implemented complete Walker-Buchheim O(n) algorithm
- Added contour threading and subtree conflict resolution
- Improved sibling access from O(n) to O(1)
- Added comprehensive documentation and algorithm references
- Time complexity improved from O(n²) to O(n)
