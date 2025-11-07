- I've already created a basic tree scene: biologidex/client/biologidex-client/tree.tscn
- Currently order alphabetically under each step
    - In the future access primary source for phylogeny data (evolutionary tree style)
- Display as a tidy tree using the `Reingold-Tilford` algortihmn
    - Algortihmn description: ```
    Here is a very brief overview of the logic I used to determine an appropriate X position of each node

    1. Do a post-order traversal of the tree
    2. Assign an X value to each node of 0 if it’s a left-most node, or leftSibling.X + 1 if it’s not.

    3. For each parent node, we want the node centered over the children. This would be the midway point between the first child’s X position, and the last child’s X position.

    If the parent has no left sibling, change it’s X value to this midpoint value. If it has a left sibling, we’re going to store it in another node property. I’m calling this property Mod just because that’s what I see it called in other examples.

    The Mod property is used to determine how much to modify the children’s X values in order to center them under the parent node, and will be used when we’re done with all our calculates to determine the final X value of each node. It should actually be set to Parent.X – MiddleOfChildrenX to determine the correct amount to shift the children by.
    4. Check that this tree does not conflict with any of the previous sibling trees, and adjust the Mod property if needed. This means looping through each Y level in the current node, and checking that the right-most X value of any sibling to the left of the node does not cross the left-most X value of any child in the current node.
    5. Do a second walk through the tree to determine that no children will be drawn off-screen, and adjust the Mod property if needed. This can happen when if the Mod property is negative.
    6. Do a third walk through the tree to determine the final X values for each node. This will be the X of the node, plus the sum of all the Mod values of all parent nodes to that node.```
        - source: https://rachel53461.wordpress.com/2014/04/20/algorithm-for-drawing-trees/
- scene setup considerations 
 └─ VBox (VBoxContainer)
       │   └─ View (ViewportContainer)     # UI node that displays a SubViewport
       │       └─ SV (SubViewport)         # 2D-only; no World/Camera
       │           └─ World2D (Node2D)     # applies pan/zoom (Transform2D)
       │               └─ Graph (Node2D)   # renderer + managers live here
       │                   ├─ Edges (MultiMeshInstance2D)
       │                   ├─ Nodes (MultiMeshInstance2D)
       │                   └─ LabelLayer (Node2D)   # pooled Labels for visible nodes (optional)
    - A SubViewport-based 2D canvas (fast) embedded in UI (pure Control tree).
    - MultiMeshInstance2D batching for hundreds of thousands of nodes/edges.
    - Input for mouse, trackpad, touch gestures, keyboard, with inertial panning.
    - Chunked culling + level-of-detail hooks so you never render everything at once.
    - Export & project settings tips for HTML5.
- Perfomance/optimzation considerations 
    - Recommend precomputed layouts (server-side or offline) for tidy tree/reingold-tilford
        - Save results as chunked tiles (grid in world space), e.g., one JSON per tile with:
            - nodes: [ [x,y,id,label,rank,...], ... ]
            - edges: [ [id_a,id_b], ... ] or flat pairs.
            - On view change, compute which tiles intersect the visible rect; request and load_chunk(...) only those.
                - This avoids pushing 500k nodes to WebGL at once and keeps frame times stable.
    - Labels
        - Never create a Label per node. Instead:
            - Maintain a small pool (e.g., 200–1000) of Label controls in LabelLayer.
            - On each visibility update, place labels only for the largest / most important nodes in view (rank-based, zoom-based, or top-N by screen-space size).
            - Use SDF DynamicFont with low weight, and distance-based fade (modulate.a) to reduce clutter.
    - Nodes: Hundreds of thousands are fine with MultiMeshInstance2D (single material).
    - Edges: Also MultiMesh (thin quads). Consider LOD: hide edges below zoom thresholds; show only spanning tree at mid zooms; add cross-links only when zoomed in.
    - Chunking: ~2048×2048 world-units per tile is a good start. Keep per-tile node counts under ~30–60k.
    - Culling: quick rect tests first, optional quadtree if hotspots stutter.
    - GPU state: 1 material per layer (nodes, edges). Avoid per-instance color unless necessary.
    - Interaction: transform the World2D node (single Transform2D)—cheap and simple.
