# TreeRenderer Future Improvements

This document outlines remaining features and enhancements for the taxonomic tree visualization system that have been planned but not yet implemented.

## 🎯 Next Steps for Testing

1. **Restart Server** (if running): The server code has been modified, so restart the Django server or Docker containers
2. **Clear Tree Cache**: Server caches tree data for 2-5 minutes. Either:
   - Wait for cache to expire, OR
   - Clear manually via Django shell: `DynamicTaxonomicTreeService.invalidate_global_cache()`
3. **Test Tree View**: Open the tree visualization in the client and verify:
   - Animals now connect through taxonomic hierarchy (not flat)
   - Gray taxonomy nodes visible (Kingdom, Phylum, Class, etc.)
   - One shared node per taxonomic rank (e.g., single "Mammalia")
   - Only animal nodes are selectable (taxonomy nodes print debug message)
4. **Report Issues**: If tree still appears flat or has errors, check browser console and server logs

---

## ✅ Phase 0: Core Hierarchical Tree Structure - COMPLETED (2025-11-15)

**Status**: The core hierarchical tree visualization has been fully implemented and is ready for testing.

### Implementation Summary

**Server Changes** (`/server/graph/services_dynamic.py`):
- ✅ Modified `_build_nodes()` method to include virtual taxonomy nodes
- ✅ Added recursive traversal of hierarchy to serialize all taxonomy ranks
- ✅ Each taxonomic rank creates a single shared node (deduplication working)
- ✅ Reingold-Tilford layout algorithm was already implemented and working

**Client Changes**:
- ✅ Added `NodeType` and `TaxonomicRank` enums to `tree_data_models.gd`
- ✅ Updated `TaxonomicNode` class with new fields and helper methods
- ✅ Updated `tree_renderer.gd` to differentiate rendering by node type
- ✅ Taxonomy nodes: gray color, rank-based sizing
- ✅ Animal nodes: color-coded by capture status
- ✅ Enhanced edge rendering: thicker for hierarchy, thinner for leaves
- ✅ Only animal nodes are selectable/interactive

### Server-Side Requirements

- [x] **Generate Complete Taxonomic Tree Structure**
  - Create nodes for ALL taxonomic ranks (Kingdom, Phylum, Class, Order, Family, Genus, Species, Subspecies)
  - Each taxonomic level should have a single node shared by all descendants
  - Example: One "Animalia" node at kingdom level for all animals
  - Example: For "Canis lupus", create chain: Animalia → Chordata → Mammalia → Carnivora → Canidae → Canis → C. lupus
  - Deduplicate taxonomic nodes (e.g., single "Mammalia" node for all mammals)

- [x] **Implement Reingold-Tilford Layout Algorithm**
  - ✅ Reingold-Tilford algorithm was already implemented in `/server/graph/layout/reingold_tilford.py`
  - ✅ Proper hierarchical layout with parent-child positioning
  - ✅ Nodes properly spaced at each depth level
  - ✅ Minimal edge crossings with tree structure

- [x] **Update Node Data Structure**
  - ✅ Added `node_type` field: "taxonomic" vs "animal"
  - ✅ Added `rank` field for taxonomic nodes (kingdom, phylum, class, etc.)
  - ✅ Edges properly connect parent-child relationships throughout hierarchy
  - ✅ Animal nodes (species/subspecies) contain full dex entry data

- [x] **Update API Response**
  - ✅ `/graph/taxonomic-tree/` now returns complete hierarchical structure
  - ✅ Includes both taxonomic nodes and animal nodes
  - ✅ Edges properly connect all hierarchical relationships
  - ✅ Layout positions reflect Reingold-Tilford tree structure
  - Response structure (implemented):
    ```json
    {
      "nodes": [
        {"id": "kingdom_animalia", "type": "taxonomic", "rank": "kingdom", "name": "Animalia", "position": [0, 0]},
        {"id": "phylum_chordata", "type": "taxonomic", "rank": "phylum", "name": "Chordata", "position": [0, 100]},
        {"id": "class_mammalia", "type": "taxonomic", "rank": "class", "name": "Mammalia", "position": [-200, 200]},
        {"id": "order_carnivora", "type": "taxonomic", "rank": "order", "name": "Carnivora", "position": [-300, 300]},
        {"id": "family_canidae", "type": "taxonomic", "rank": "family", "name": "Canidae", "position": [-350, 400]},
        {"id": "genus_canis", "type": "taxonomic", "rank": "genus", "name": "Canis", "position": [-350, 500]},
        {"id": "animal_123", "type": "animal", "scientific_name": "Canis lupus", "position": [-400, 600],
         "captured_by_user": true, "captured_by_friends": [], "dex_entry_data": {...}}
      ],
      "edges": [
        {"source": "kingdom_animalia", "target": "phylum_chordata"},
        {"source": "phylum_chordata", "target": "class_mammalia"},
        {"source": "class_mammalia", "target": "order_carnivora"},
        {"source": "order_carnivora", "target": "family_canidae"},
        {"source": "family_canidae", "target": "genus_canis"},
        {"source": "genus_canis", "target": "animal_123"}
      ]
    }
    ```

### Client-Side Requirements

- [x] **Update TreeDataModels** (`tree_data_models.gd`)
  - ✅ Added `NodeType` enum: TAXONOMIC = 0, ANIMAL = 1
  - ✅ Added `TaxonomicRank` enum (ROOT, KINGDOM, PHYLUM, CLASS, ORDER, FAMILY, SUBFAMILY, GENUS, SPECIES, SUBSPECIES)
  - ✅ Updated TaxonomicNode class with new fields: node_type, rank, name, children_count
  - ✅ Added helper methods: `is_taxonomic()`, `is_animal()`, `_parse_rank()`
  - ✅ Proper parsing of server response with both node types

- [x] **Differentiate Node Rendering** (`tree_renderer.gd`)
  - ✅ **Taxonomic nodes** (internal):
    - Smaller appearance (6.0 base size with rank-based multipliers)
    - Gray color with transparency (0.6, 0.6, 0.6, 0.8)
    - Non-interactive (cannot be selected, only animal nodes selectable)
    - Hover feedback with lighter gray color
    - Rank-based sizing (larger for Kingdom/Phylum, smaller for Genus)
  - ✅ **Animal nodes** (leaves):
    - Current rendering style maintained (colored by capture status)
    - Full interactivity (selection, hover, signals)
    - Represent actual dex entries
    - Show scientific/common names

- [x] **Update Edge Rendering** (`tree_renderer.gd`)
  - ✅ Edges follow tree hierarchy from server
  - ✅ Different edge styles implemented:
    - Taxonomy-to-taxonomy: thicker (2.0), more opaque (hierarchical structure)
    - Taxonomy-to-animal: thinner (1.0), less opaque (leaf connections)
  - ✅ Edges connect properly in hierarchical layout
  - ✅ Only parent-child edges (no sibling connections)

- [x] **Fix Node Positioning**
  - ✅ Uses positions from server's Reingold-Tilford layout
  - ✅ Tree structure properly displayed with hierarchy
  - ✅ Proper spacing between tree levels (from layout algorithm)
  - ✅ No overlapping nodes (handled by Reingold-Tilford)

### Testing & Validation

**Ready for User Testing** - The following should be verified when running the application:

- [ ] **Verify Tree Structure**
  - Confirm each animal displays complete taxonomic path (Kingdom → Species)
  - Check that taxonomic nodes are properly shared (e.g., one "Mammalia" for all mammals)
  - Validate Reingold-Tilford layout appears hierarchical (not flat)
  - Test with animals from different taxonomic groups

- [ ] **Example Test Cases**
  - "Canis lupus" and "Canis familiaris" - should share all nodes up to Genus (Canis)
  - "Felis catus" - should share up to Order (Carnivora) with Canis species
  - "Homo sapiens" - should share only Kingdom (Animalia) and Phylum (Chordata) with carnivores

- [ ] **Visual Verification**
  - Taxonomy nodes appear gray and smaller
  - Animal nodes are color-coded (blue=user, green=friends, purple=both)
  - Edges are visible and connect hierarchy properly
  - Only animal nodes can be selected (clicking taxonomy nodes prints debug)

- [ ] **Cache Management**
  - May need to clear server cache: `DynamicTaxonomicTreeService.invalidate_global_cache()`
  - Or wait for cache TTL to expire (typically 2-5 minutes)

---

## ✅ Phase 1: Basic Rendering - COMPLETED (with Phase 0 updates)

**Status**: All rendering functionality implemented and updated for hierarchical tree display.

- [x] Create tree_renderer.gd class
- [x] Implement MultiMeshInstance2D setup
- [x] Basic node rendering with positions
- [x] Simple camera controls (pan, zoom)
- [x] Frustum culling
- [x] Color coding by capture status
- [x] Node size variations
- [x] Edge rendering system
- [x] Hover/selection states
- [x] Camera panning with mouse
- [x] Zoom with mouse wheel
- [x] **Updates from Phase 0 integration**:
  - ✅ Handle different node types (taxonomic vs animal)
  - ✅ Proper hierarchical edge connections with varied styling
  - ⏭️ Vertical/horizontal tree orientation (deferred to future phase)

---

## 📋 Phase 2: Visual Polish

### Node Labels
- [ ] **Implement LOD-based label rendering**
  - Show labels only when zoomed in close
  - Fade in/out based on zoom level
  - Use `Label` nodes or custom text rendering
  - Pool labels for performance

- [ ] **Label content and styling**
  - Scientific name (primary)
  - Common name (secondary, smaller)
  - Capture count indicator
  - Conservation status icon

### Animations
- [ ] **Selection animations**
  - Smooth outline pulse effect
  - Scale up slightly on selection
  - Ease-in/ease-out transitions

- [ ] **Hover effects**
  - Glow or brightness increase
  - Smooth transition (0.1s duration)

- [ ] **Camera transitions**
  - Tween camera position when focusing on nodes
  - Smooth zoom animations
  - Ease-in-out curves for natural feel

### Edge Improvements
- [ ] **Curved edges**
  - Bezier curves for better visual flow
  - Control points based on tree structure
  - Performance testing with curves vs lines

- [ ] **Thickness by rank**
  - Thicker lines for higher-level connections (kingdom → phylum)
  - Thinner lines for lower-level connections (genus → species)
  - Configurable thickness mapping

- [ ] **Edge hover effects**
  - Highlight edge on hover
  - Show relationship info (rank transition)

### UI Improvements
- [ ] **Hover tooltip system**
  - Floating tooltip near cursor
  - Shows basic node info without selecting
  - Auto-hide on mouse move away
  - Touch-friendly alternative

- [ ] **Loading indicators**
  - Progress bar for large trees
  - Chunk loading feedback
  - Smooth fade-in for new nodes

---

## ⚡ Phase 3: Performance Optimization

### Level of Detail (LOD) System
- [ ] **Implement LOD tiers**
  - **LOD 0 (Close)**: Full detail, all labels, all edges
  - **LOD 1 (Medium)**: Simplified labels, some edges
  - **LOD 2 (Far)**: Points only, no labels, major edges only
  - **LOD 3 (Very Far)**: Heat map or density visualization

- [ ] **Dynamic LOD calculation**
  - Calculate LOD per node based on camera distance
  - Use zoom level as primary factor
  - Consider node importance (user captures, rarity)

- [ ] **Cluster visualization**
  - Merge nearby nodes into clusters when zoomed out
  - Show cluster size/density
  - Expand on zoom in
  - K-means or spatial clustering

### Chunk-Based Loading
- [ ] **Implement chunk manager**
  - Divide tree into 2048x2048 unit chunks
  - Track loaded/unloaded chunks
  - Priority queue for loading

- [ ] **Progressive loading**
  - Load visible chunks first
  - Preload adjacent chunks
  - Unload far chunks to free memory
  - Background loading without frame drops

- [ ] **Chunk caching**
  - Memory budget management (max 16 chunks)
  - LRU eviction policy
  - Persistent cache to disk for large trees

- [ ] **API integration**
  - Use `TreeService.fetch_chunk()` for on-demand loading
  - Handle chunk load failures gracefully
  - Retry logic with exponential backoff

### Spatial Indexing
- [ ] **Quadtree implementation**
  - Replace simple grid with quadtree
  - Faster click detection for dense areas
  - Dynamic subdivision based on node density
  - Max depth limit

- [ ] **R-tree for edges**
  - Efficient edge culling
  - Fast hover detection for edges
  - Spatial queries for visible edges

### Memory Management
- [ ] **Instance pooling**
  - Pool Line2D nodes for edges
  - Reuse label nodes
  - Limit total object count

- [ ] **Texture atlasing**
  - Combine node textures into atlas
  - Reduce draw calls
  - Custom shader for texture regions

- [ ] **Garbage collection optimization**
  - Manual cleanup of unused objects
  - Avoid creating garbage during rendering
  - Object pooling patterns

---

## 🎮 Phase 4: Advanced Interactions

### Node Information System
- [ ] **Detailed info panel**
  - Side panel or modal popup
  - Full taxonomy hierarchy
  - Capture details (who, when)
  - Conservation status
  - Link to dex entry or animal detail page

- [ ] **Context menu**
  - Right-click on node for options
  - "View Details"
  - "Focus on Subtree"
  - "Add to Favorites"
  - "Share"

### Selection Enhancements
- [ ] **Multi-select**
  - Ctrl+click to add to selection
  - Shift+click for range select
  - Box select with drag
  - Selection count indicator

- [ ] **Selection actions**
  - Compare selected nodes
  - Batch operations
  - Export selection
  - Create collection from selection

### Search Integration
- [ ] **Search result highlighting**
  - Highlight matching nodes in tree
  - Different color for search results
  - "Next/Previous" navigation
  - Clear search results

- [ ] **Visual search indicators**
  - Markers or pins on matching nodes
  - Count of results
  - Zoom to fit all results

### Camera Enhancements
- [ ] **Focus on node**
  - Double-click to center and zoom
  - Smooth animation to target
  - Configurable zoom level

- [ ] **Minimap**
  - Small overview map in corner
  - Shows entire tree
  - Viewport indicator
  - Click to navigate

- [ ] **Bookmarks**
  - Save camera positions
  - Quick navigation to saved views
  - Named bookmarks
  - Persistent across sessions

### Touch/Mobile Support
- [ ] **Touch gestures**
  - Pinch to zoom
  - Two-finger pan
  - Tap to select
  - Long-press for context menu

- [ ] **Mobile UI adjustments**
  - Larger touch targets
  - Mobile-friendly controls
  - Simplified UI for small screens

---

## 🚀 Phase 5: Advanced Features

### Heat Map Visualization
- [ ] **Density heat map**
  - Show capture density when zoomed out
  - Color gradient based on capture count
  - Smooth interpolation
  - Toggle between heat map and node view

- [ ] **Rarity heat map**
  - Highlight rare species
  - Based on capture frequency
  - Help users find unique animals

### Time-Lapse Animation
- [ ] **Capture history playback**
  - Animate tree growth over time
  - Show when each animal was captured
  - Adjustable playback speed
  - Scrub timeline

- [ ] **Friend comparison animation**
  - Show differences between user and friend dex
  - Highlight unique captures
  - Animate transitions

### Comparison Modes
- [ ] **Side-by-side comparison**
  - Compare two users' trees
  - Synchronized camera
  - Highlight differences
  - Venn diagram view

- [ ] **Differential view**
  - Show only differences
  - Color code: yours only, theirs only, both
  - Toggle layers

### Export Features
- [ ] **Screenshot system**
  - High-res export
  - Configurable viewport size
  - Include labels/legend
  - Save to file or share

- [ ] **Tree export**
  - Export visible tree as image
  - SVG export for vector graphics
  - JSON export for data
  - Print-friendly format

### Filter and View Modes
- [ ] **Taxonomic rank filtering**
  - Show only specific ranks (e.g., just species)
  - Hide intermediate nodes
  - Dynamic layout adjustment

- [ ] **Capture status filtering**
  - Show only captured nodes
  - Show only uncaptured
  - Show only friend captures

- [ ] **Conservation status filtering**
  - Filter by IUCN status
  - Highlight endangered species
  - Educational mode

### Social Features
- [ ] **Friend highlights**
  - Hover to see which friends captured
  - Friend-specific coloring
  - Toggle friend visibility

- [ ] **Collaborative viewing**
  - Synchronized view with friend
  - Follow friend's camera
  - Shared annotations

---

## 🔧 Technical Improvements

### Shader Enhancements
- [ ] **Custom vertex shader**
  - GPU-based instance transformations
  - Faster than CPU updates
  - Custom vertex attributes

- [ ] **Outline shader**
  - Smooth outline for selection
  - Adjustable thickness and color
  - Anti-aliased

- [ ] **Glow shader**
  - Bloom effect for special nodes
  - Animated glow
  - Performance-friendly

### Compute Shaders (Godot 4+)
- [ ] **GPU-based LOD calculation**
  - Calculate LOD on GPU
  - Faster than CPU for large trees
  - Parallel processing

- [ ] **GPU culling**
  - Frustum culling on GPU
  - Compute shader for visibility
  - Reduce CPU load

### Performance Monitoring
- [ ] **Built-in profiler**
  - FPS counter
  - Node/edge count display
  - Memory usage
  - Draw call count

- [ ] **Performance presets**
  - Low/Medium/High/Ultra settings
  - Auto-detect based on performance
  - User configurable

---

## 📊 Testing & Quality Assurance

### Stress Testing
- [ ] **Large tree tests**
  - Test with 10k, 50k, 100k+ nodes
  - Measure frame rate
  - Memory profiling
  - Load time measurement

- [ ] **Edge case handling**
  - Empty tree
  - Single node
  - Extremely deep hierarchy
  - Very wide hierarchy

### Visual Regression Testing
- [ ] **Screenshot comparison**
  - Capture reference screenshots
  - Compare against current render
  - Detect visual regressions
  - Automated testing

### Interaction Testing
- [ ] **Input testing**
  - Mouse, keyboard, touch
  - Different devices
  - Edge cases (rapid clicking, etc.)

---

## 📱 Platform-Specific Enhancements

### Web Export Optimizations
- [ ] **Web-specific performance**
  - Single-threaded optimizations
  - Reduced memory footprint
  - Lazy loading for web

- [ ] **Progressive Web App features**
  - Offline support
  - Caching strategy
  - Service worker integration

### Desktop Enhancements
- [ ] **Keyboard shortcuts**
  - Arrow keys for panning
  - +/- for zoom
  - Space for reset
  - F for focus on selected

- [ ] **High DPI support**
  - Retina display support
  - Scale UI appropriately
  - Sharp text rendering

---

## 🎨 Accessibility

### Visual Accessibility
- [ ] **Colorblind modes**
  - Alternative color schemes
  - Deuteranopia, Protanopia, Tritanopia
  - Pattern overlays in addition to color

- [ ] **High contrast mode**
  - Increased contrast
  - Larger text
  - Simplified visuals

### Interaction Accessibility
- [ ] **Keyboard navigation**
  - Tab through nodes
  - Arrow key navigation
  - Enter to select

- [ ] **Screen reader support**
  - Describe tree structure
  - Read node information
  - Navigation cues

---

## 🗺️ Implementation Priority

### 🔴 CRITICAL - Must Complete First
**Phase 0: Core Hierarchical Tree Structure**
1. Server: Generate complete taxonomic tree with all rank nodes
2. Server: Implement Reingold-Tilford layout algorithm
3. Server: Update API to return hierarchical structure
4. Client: Update data models for node types
5. Client: Differentiate rendering between taxonomic and animal nodes
6. Testing: Validate proper tree structure and layout

### High Priority (After Phase 0)
1. Node labels with LOD
2. Smooth animations for selection
3. Detailed info panel
4. Search result highlighting

### Medium Priority (Next Month)
1. LOD system implementation
2. Chunk-based loading
3. Quadtree spatial indexing
4. Touch/mobile gestures
5. Minimap

### Low Priority (Future)
1. Heat map visualization
2. Time-lapse animation
3. Advanced export features
4. Compute shaders
5. Collaborative viewing

---

## 📈 Performance Targets (Reminder)

- **60 FPS** with 10,000 visible nodes
- **30 FPS** with 50,000 visible nodes
- **<100ms** chunk load time
- **<2GB** memory usage at peak
- **<50ms** input latency

---

## 🔗 Related Files

- **Implementation**: `client/biologidex-client/tree_renderer.gd`
- **Controller**: `client/biologidex-client/tree_controller.gd`
- **Data Models**: `client/biologidex-client/tree_data_models.gd`
- **API Service**: `client/biologidex-client/api/services/tree_service.gd`
- **Server Endpoint**: `server/biologidex/graph/views.py`

---

## 📝 Notes

- **CRITICAL**: Phase 0 must be completed before any other improvements - the current flat node display is fundamentally incorrect
- The tree must show proper taxonomic hierarchy (Kingdom → Phylum → Class → Order → Family → Genus → Species)
- Each taxonomic level should be a shared node (e.g., one "Mammalia" node for all mammals)
- Only leaf nodes (species/subspecies) represent actual dex entries with capture status
- All phases should maintain backward compatibility with existing API (after Phase 0 changes)
- Performance should be measured and validated at each phase
- User feedback should guide priority of feature implementation
- Consider mobile-first design for touch interactions
- Ensure all features work in web export (single-threaded mode)
