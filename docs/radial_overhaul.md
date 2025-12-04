# Radial Tree Layout Algorithm Overhaul

## Implementation Plan for BiologiDex Taxonomic Tree Visualization

**Document Version:** 1.0
**Date:** 2025-12-03
**Author:** Claude (AI Assistant)
**Status:** Draft - Pending Review

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Research Findings](#3-research-findings)
4. [Proposed Solution](#4-proposed-solution)
5. [Algorithm Design](#5-algorithm-design)
6. [Implementation Details](#6-implementation-details)
7. [API Contract](#7-api-contract)
8. [Testing Strategy](#8-testing-strategy)
9. [Migration Plan](#9-migration-plan)
10. [Risk Assessment](#10-risk-assessment)

---

## 1. Executive Summary

The current radial tree layout in BiologiDex suffers from a critical bug where nodes from different taxonomic branches can overlap when they converge to the same angular position. This occurs because the existing implementation retrofits the Walker-Buchheim algorithm (designed for rectangular layouts) onto a radial coordinate system using a naive global x-coordinate normalization.

This document proposes replacing the current approach with the **Eades Radial Tree Algorithm**, which uses **angular wedge allocation** based on subtree leaf counts. This algorithm:

- Guarantees no node overlaps by construction
- Allocates space proportionally to subtree size
- Runs in O(n) time complexity
- Is purpose-built for radial visualizations

**Key Deliverables:**
- New `EadesRadialLayout` class replacing `RadialReingoldTilfordLayout`
- Comprehensive test suite with edge case coverage
- Zero breaking changes to the existing API contract

---

## 2. Problem Statement

### 2.1 Observed Bug

The "Japanese Spider Crab" (Arthropoda) and "American Bison" (Chordata) nodes render at identical screen coordinates despite being in completely different phyla:

```
Bison:  position = [0.00000000000019, -3100.0]
Crab:   position = [-0.0000000000006, -3100.0]
```

### 2.2 Root Cause Analysis

The current `RadialReingoldTilfordLayout` class operates in three phases:

1. **Build tree nodes** from hierarchy data
2. **Run Walker-Buchheim** to compute (x, y) coordinates in tree-space
3. **Transform to radial** by normalizing x globally to angles

The bug occurs in Phase 3. The transformation:

```python
normalized_x = (node.x - min_x) / x_range
angle_deg = normalized_x * self.angle_spread
```

This normalization is **global across all nodes**, meaning:

- Single-child chains inherit the same x-coordinate down the entire lineage
- Two branches from different phyla can converge to identical normalized_x values
- Identical normalized_x → identical angle → overlapping positions

### 2.3 Why Walker-Buchheim Is Wrong for Radial Layouts

Walker-Buchheim optimizes for **rectangular layouts** with these properties:
- Nodes at the same depth share a horizontal line
- Parents are centered horizontally over children
- Subtrees are compacted horizontally while avoiding overlap

For **radial layouts**, we need different properties:
- Nodes at the same depth share a concentric circle (radius)
- Parents are centered **angularly** over children
- Subtrees receive **angular wedges** proportional to their size

The current approach tries to map rectangular properties to polar coordinates, which fundamentally doesn't preserve tree structure.

---

## 3. Research Findings

### 3.1 Academic Literature

| Paper/Source | Year | Key Contribution |
|--------------|------|------------------|
| [Eades, "Drawing Free Trees"](https://eclipse.dev/elk/reference/algorithms/org-eclipse-elk-radial.html) | 1991 | Annulus wedge allocation based on leaf count |
| Reingold & Tilford, "Tidier Drawing of Trees" | 1981 | Linear-time algorithm for rectangular layouts |
| [Pavlo et al., "Parent-Centered Radial Layout"](https://www.cs.cmu.edu/~pavlo/papers/APavloThesis032006.pdf) | 2006 | Wedges centered on parent nodes (PLANET variant) |
| Buchheim et al., "Improving Walker's Algorithm" | 2002 | O(n) optimization of Walker's algorithm |

### 3.2 Industry Implementations

#### D3.js Radial Tree
- Uses Reingold-Tilford with polar coordinate transformation
- Applies custom **separation function**: `(a, b) => (a.parent == b.parent ? 1 : 2) / a.depth`
- Mitigates overlap via depth-scaled separation, but doesn't guarantee prevention

Reference: [D3 Radial Tree Observable](https://observablehq.com/@d3/radial-tree/2)

#### ELK (Eclipse Layout Kernel)
- Implements true Eades algorithm with annulus wedges
- Supports two wedge criteria:
  1. **Leaf count** (standard): Wedge size ∝ number of leaves in subtree
  2. **Node diagonal sum** (size-aware): Wedge size ∝ geometric size of nodes
- Reference: [ELK Radial Documentation](https://eclipse.dev/elk/reference/algorithms/org-eclipse-elk-radial.html)

#### yFiles BalloonLayout
- Optimized for trees with 10,000+ nodes
- Uses radial wedge allocation with configurable angular extent
- Reference: [yFiles Tree Layouts](https://docs.yworks.com/yfiles-html/dguide/layout/tree_layouts.html)

### 3.3 Algorithm Comparison

| Algorithm | Overlap-Free | Time Complexity | Angular Allocation | Best For |
|-----------|--------------|-----------------|-------------------|----------|
| Walker-Buchheim + Polar Transform | No | O(n) | Global normalization | Rectangular layouts |
| **Eades Radial (Leaf-Weighted)** | **Yes** | **O(n)** | **Proportional wedges** | **General radial trees** |
| PLANET (Parent-Centered) | Yes | O(n) | Per-parent polar system | Deep trees with self-similarity |
| Sunburst (Value-Weighted) | Yes | O(n) | Value-based wedges | Data with numeric weights |

### 3.4 Key Insight

> "Each subtree is assigned to an annulus wedge, a part of the circle. The node which shall be placed gets space according to the number of leaves it has compared to the number of leaves all nodes of the same layer have."
> — ELK Documentation

This is the core principle missing from our current implementation.

---

## 4. Proposed Solution

### 4.1 Solution Overview

Replace `RadialReingoldTilfordLayout` with a new `EadesRadialLayout` class that implements **angular wedge allocation** based on subtree leaf counts.

### 4.2 Algorithm Selection: Eades Radial (Leaf-Weighted)

**Rationale:**
1. **Guaranteed overlap-free**: Angular wedges are non-overlapping by construction
2. **Proportional space**: Larger subtrees (more species) get more angular space
3. **O(n) complexity**: Two linear passes (post-order + pre-order)
4. **Semantically meaningful**: Angular width reflects taxonomic diversity
5. **Well-documented**: Standard algorithm with proven implementations

### 4.3 High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                     EadesRadialLayout                            │
├─────────────────────────────────────────────────────────────────┤
│ Phase 1: Count Leaves (Post-Order Traversal)                    │
│   - Each node stores: leaf_count = sum(children.leaf_count) or 1│
│                                                                  │
│ Phase 2: Allocate Wedges (Pre-Order Traversal)                  │
│   - Root gets [0°, 360°]                                        │
│   - Each child gets wedge proportional to its leaf_count        │
│   - Node positioned at CENTER of its wedge                      │
│                                                                  │
│ Phase 3: Convert to Cartesian                                   │
│   - angle = center of wedge                                     │
│   - radius = min_radius + depth * radius_per_level              │
│   - x = radius * cos(angle), y = radius * sin(angle)            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Algorithm Design

### 5.1 Data Structures

```python
@dataclass
class RadialTreeNode:
    """Node representation for Eades radial layout."""
    id: str
    rank: str
    name: str
    children: List['RadialTreeNode']
    parent: Optional['RadialTreeNode']

    # Computed during layout
    leaf_count: int = 0          # Number of leaves in subtree
    wedge_start: float = 0.0     # Starting angle in radians
    wedge_end: float = 0.0       # Ending angle in radians
    angle: float = 0.0           # Final angle (center of wedge)
    radius: float = 0.0          # Distance from center
    x: float = 0.0               # Cartesian x
    y: float = 0.0               # Cartesian y
```

### 5.2 Algorithm Pseudocode

```
ALGORITHM EadesRadialLayout(tree, angle_spread, min_radius, radius_step)

INPUT:
  tree         - Hierarchical tree structure
  angle_spread - Total angular spread (default: 2π for full circle)
  min_radius   - Radius of first level from center
  radius_step  - Radial distance between levels

OUTPUT:
  positions    - Dictionary mapping node_id → (x, y)

PROCEDURE:

1. BUILD tree nodes from hierarchy
   root ← BuildTreeNodes(tree)

2. COUNT leaves (post-order traversal)
   CountLeaves(root)

   FUNCTION CountLeaves(node):
     IF node.children is empty:
       node.leaf_count ← 1
     ELSE:
       node.leaf_count ← 0
       FOR EACH child IN node.children:
         CountLeaves(child)
         node.leaf_count ← node.leaf_count + child.leaf_count

3. ALLOCATE angular wedges (pre-order traversal)
   root.wedge_start ← -π/2  # Start at top (12 o'clock)
   root.wedge_end ← root.wedge_start + angle_spread
   AllocateWedges(root, depth=0)

   FUNCTION AllocateWedges(node, depth):
     # Position this node
     node.angle ← (node.wedge_start + node.wedge_end) / 2
     node.radius ← min_radius + depth * radius_step IF depth > 0 ELSE 0

     # Convert to Cartesian
     node.x ← node.radius * cos(node.angle)
     node.y ← node.radius * sin(node.angle)

     # Allocate wedges to children proportionally
     IF node.children is not empty:
       current_angle ← node.wedge_start
       wedge_size ← node.wedge_end - node.wedge_start

       FOR EACH child IN node.children:
         child_fraction ← child.leaf_count / node.leaf_count
         child_wedge ← wedge_size * child_fraction

         child.wedge_start ← current_angle
         child.wedge_end ← current_angle + child_wedge
         current_angle ← child.wedge_end

         AllocateWedges(child, depth + 1)

4. EXTRACT positions
   positions ← {}
   FOR EACH node IN tree (any traversal):
     positions[node.id] ← (node.x, node.y)

   RETURN positions
```

### 5.3 Complexity Analysis

| Operation | Time | Space |
|-----------|------|-------|
| Build tree nodes | O(n) | O(n) |
| Count leaves | O(n) | O(h) stack |
| Allocate wedges | O(n) | O(h) stack |
| Extract positions | O(n) | O(n) |
| **Total** | **O(n)** | **O(n)** |

Where n = number of nodes, h = tree height.

### 5.4 Example Walkthrough

Given this tree:
```
root (13 leaves total)
├── Chordata (11 leaves)
│   ├── Mammalia (4 leaves)
│   │   ├── Artiodactyla (1 leaf) → Bison
│   │   └── Carnivora (3 leaves) → Dog, Cat, Panda
│   └── ...other classes (7 leaves)
├── Cnidaria (1 leaf) → Jellyfish
└── Arthropoda (1 leaf) → Crab
```

**Wedge Allocation:**

1. Root: [−90°, 270°] = 360° total
2. Chordata: 11/13 × 360° = 304.6° → [−90°, 214.6°]
3. Cnidaria: 1/13 × 360° = 27.7° → [214.6°, 242.3°]
4. Arthropoda: 1/13 × 360° = 27.7° → [242.3°, 270°]

**Result:**
- Bison ends up at ~−76° (within Chordata→Mammalia→Artiodactyla wedge)
- Crab ends up at ~256° (within Arthropoda wedge)
- **Separation: 332°** — no overlap possible!

---

## 6. Implementation Details

### 6.1 File Structure

```
server/graph/layout/
├── __init__.py
├── reingold_tilford.py      # Keep for rectangular layouts
├── eades_radial.py          # NEW: Radial layout implementation
└── base.py                  # NEW: Shared base classes (optional)
```

### 6.2 Class Design

```python
# server/graph/layout/eades_radial.py

"""
Eades Radial Tree Layout Algorithm.

Implements angular wedge allocation based on subtree leaf counts,
guaranteeing overlap-free radial tree visualizations.

Based on: Eades, P. (1991). Drawing Free Trees.

Time Complexity: O(n)
Space Complexity: O(n)
"""

import math
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class RadialNode:
    """Internal node for radial layout computation."""
    id: str
    rank: str
    name: str
    children: List['RadialNode'] = field(default_factory=list)
    parent: Optional['RadialNode'] = None

    # Layout properties
    leaf_count: int = 0
    wedge_start: float = 0.0
    wedge_end: float = 0.0
    depth: int = 0

    @property
    def wedge_center(self) -> float:
        """Angular center of this node's wedge."""
        return (self.wedge_start + self.wedge_end) / 2

    @property
    def wedge_size(self) -> float:
        """Angular size of this node's wedge."""
        return self.wedge_end - self.wedge_start

    def is_leaf(self) -> bool:
        """True if node has no children."""
        return len(self.children) == 0


class EadesRadialLayout:
    """
    Radial tree layout using Eades's angular wedge allocation.

    Each subtree receives an angular wedge proportional to its
    number of leaves, guaranteeing no overlapping nodes.

    Attributes:
        angle_spread: Total angular spread in radians (2π = full circle)
        min_radius: Radius of first level from center (pixels)
        radius_per_level: Radial distance between levels (pixels)
        start_angle: Starting angle for layout (−π/2 = top)
    """

    def __init__(
        self,
        angle_spread: float = 2 * math.pi,
        min_radius: float = 300.0,
        radius_per_level: float = 400.0,
        start_angle: float = -math.pi / 2
    ):
        self.angle_spread = angle_spread
        self.min_radius = min_radius
        self.radius_per_level = radius_per_level
        self.start_angle = start_angle

    def calculate_layout(self, hierarchy: Dict) -> Dict[str, Tuple[float, float]]:
        """
        Calculate radial positions for all nodes.

        Args:
            hierarchy: Tree structure from DynamicTaxonomicTreeService

        Returns:
            Dict mapping node IDs to (x, y) Cartesian coordinates
        """
        logger.info("Calculating Eades radial layout")

        # Phase 1: Build tree structure
        root = self._build_tree(hierarchy)
        if not root:
            logger.warning("Empty hierarchy provided")
            return {}

        # Phase 2: Count leaves (post-order)
        self._count_leaves(root)
        logger.debug(f"Tree has {root.leaf_count} total leaves")

        # Phase 3: Allocate wedges and compute positions (pre-order)
        root.wedge_start = self.start_angle
        root.wedge_end = self.start_angle + self.angle_spread
        self._allocate_wedges(root, depth=0)

        # Phase 4: Extract positions
        positions = self._extract_positions(root)

        logger.info(f"Layout complete: {len(positions)} nodes positioned")
        return positions

    def _build_tree(
        self,
        node_dict: Dict,
        parent: Optional[RadialNode] = None,
        depth: int = 0
    ) -> Optional[RadialNode]:
        """Recursively build RadialNode tree from hierarchy dict."""
        if not node_dict:
            return None

        node = RadialNode(
            id=node_dict.get('id', f'node_{id(node_dict)}'),
            rank=node_dict.get('rank', 'unknown'),
            name=node_dict.get('name', 'Unknown'),
            parent=parent,
            depth=depth
        )

        # Add taxonomic children
        for child_name, child_dict in node_dict.get('children', {}).items():
            child = self._build_tree(child_dict, parent=node, depth=depth + 1)
            if child:
                node.children.append(child)

        # Add animal leaves
        for animal in node_dict.get('animals', []):
            animal_node = RadialNode(
                id=str(animal.id),
                rank='animal',
                name=animal.scientific_name,
                parent=node,
                depth=depth + 1
            )
            node.children.append(animal_node)

        return node

    def _count_leaves(self, node: RadialNode) -> int:
        """
        Count leaves in subtree (post-order traversal).

        Sets node.leaf_count for all nodes.
        Returns leaf count for this subtree.
        """
        if node.is_leaf():
            node.leaf_count = 1
        else:
            node.leaf_count = sum(
                self._count_leaves(child) for child in node.children
            )
        return node.leaf_count

    def _allocate_wedges(self, node: RadialNode, depth: int):
        """
        Allocate angular wedges to all nodes (pre-order traversal).

        Each node is positioned at the center of its wedge.
        Children divide the parent's wedge proportionally by leaf count.
        """
        node.depth = depth

        # Skip allocation for children if this is a leaf
        if node.is_leaf():
            return

        # Divide wedge among children proportionally
        current_angle = node.wedge_start
        parent_wedge_size = node.wedge_size

        for child in node.children:
            # Fraction of parent's leaves in this child's subtree
            fraction = child.leaf_count / node.leaf_count
            child_wedge_size = parent_wedge_size * fraction

            child.wedge_start = current_angle
            child.wedge_end = current_angle + child_wedge_size
            current_angle = child.wedge_end

            # Recurse
            self._allocate_wedges(child, depth + 1)

    def _extract_positions(self, root: RadialNode) -> Dict[str, Tuple[float, float]]:
        """
        Extract Cartesian positions from all nodes.

        Converts (angle, radius) to (x, y) for each node.
        """
        positions = {}

        def traverse(node: RadialNode):
            # Calculate radius
            if node.depth == 0:
                radius = 0.0  # Root at center
            else:
                radius = self.min_radius + (node.depth - 1) * self.radius_per_level

            # Calculate Cartesian coordinates
            angle = node.wedge_center
            x = radius * math.cos(angle)
            y = radius * math.sin(angle)

            positions[node.id] = (x, y)

            for child in node.children:
                traverse(child)

        traverse(root)
        return positions

    def get_layout_metadata(self, positions: Dict[str, Tuple[float, float]]) -> Dict:
        """
        Return metadata about the layout for client rendering hints.
        """
        if not positions:
            return {}

        all_x = [p[0] for p in positions.values()]
        all_y = [p[1] for p in positions.values()]

        return {
            "layout_type": "radial",
            "algorithm": "eades_wedge",
            "angle_spread": math.degrees(self.angle_spread),
            "radius_per_level": self.radius_per_level,
            "min_radius": self.min_radius,
            "bounds": {
                "min_x": min(all_x) if all_x else 0,
                "max_x": max(all_x) if all_x else 0,
                "min_y": min(all_y) if all_y else 0,
                "max_y": max(all_y) if all_y else 0,
            },
            "center": (0.0, 0.0)
        }
```

### 6.3 Integration with Existing Code

Update `server/graph/services_dynamic.py`:

```python
# At imports
from graph.layout.eades_radial import EadesRadialLayout

# In DynamicTaxonomicTreeService._calculate_layout():
def _calculate_layout(self, hierarchy: Dict, layout_type: str = "radial") -> Dict:
    """Calculate node positions using specified layout algorithm."""

    if layout_type == "radial":
        # NEW: Use Eades algorithm for radial layouts
        layout_engine = EadesRadialLayout(
            angle_spread=math.radians(360),
            min_radius=300.0,
            radius_per_level=400.0
        )
    else:
        # Fall back to Walker-Buchheim for rectangular layouts
        layout_engine = ReingoldTilfordLayout(
            h_spacing=100.0,
            v_spacing=150.0
        )

    positions = layout_engine.calculate_layout(hierarchy)
    metadata = layout_engine.get_layout_metadata(positions)

    return {
        "positions": positions,
        "metadata": metadata,
        "type": layout_type
    }
```

### 6.4 Configuration Options

Add to Django settings or make configurable:

```python
# server/biologidex/settings/base.py

TREE_LAYOUT_CONFIG = {
    "radial": {
        "angle_spread_degrees": 360,
        "min_radius": 300,
        "radius_per_level": 400,
        "start_angle_degrees": -90,  # Top of circle
    },
    "rectangular": {
        "h_spacing": 100,
        "v_spacing": 150,
    }
}
```

---

## 7. API Contract

### 7.1 No Breaking Changes

The public API remains unchanged:

| Endpoint | Method | Response | Change |
|----------|--------|----------|--------|
| `/api/v1/graph/taxonomic-tree/` | GET | Tree with positions | None |
| `/api/v1/graph/invalidate-cache/` | POST | Success status | None |

### 7.2 Response Format

The `layout.positions` object format is unchanged:

```json
{
  "positions": {
    "node_id_1": [x, y],
    "node_id_2": [x, y]
  }
}
```

### 7.3 Metadata Additions

New optional fields in `layout.metadata`:

```json
{
  "metadata": {
    "layout_type": "radial",
    "algorithm": "eades_wedge",
    "angle_spread": 360.0,
    "min_radius": 300.0,
    "radius_per_level": 400.0
  }
}
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

```python
# server/graph/tests/test_eades_radial.py

import math
import pytest
from graph.layout.eades_radial import EadesRadialLayout, RadialNode


class TestLeafCounting:
    """Test Phase 2: Leaf count computation."""

    def test_single_node_is_leaf(self):
        """A node with no children has leaf_count = 1."""
        layout = EadesRadialLayout()
        hierarchy = {"id": "root", "name": "Root", "rank": "root"}
        root = layout._build_tree(hierarchy)
        layout._count_leaves(root)
        assert root.leaf_count == 1

    def test_parent_aggregates_children(self):
        """Parent leaf_count = sum of children's leaf_counts."""
        layout = EadesRadialLayout()
        hierarchy = {
            "id": "root",
            "children": {
                "a": {"id": "a", "children": {}},
                "b": {"id": "b", "children": {}},
                "c": {"id": "c", "children": {}}
            }
        }
        root = layout._build_tree(hierarchy)
        layout._count_leaves(root)
        assert root.leaf_count == 3


class TestWedgeAllocation:
    """Test Phase 3: Angular wedge allocation."""

    def test_full_circle_allocation(self):
        """Children divide 360° proportionally."""
        layout = EadesRadialLayout(angle_spread=2*math.pi)
        hierarchy = {
            "id": "root",
            "children": {
                "a": {"id": "a"},  # 1 leaf
                "b": {"id": "b"}   # 1 leaf
            }
        }
        root = layout._build_tree(hierarchy)
        layout._count_leaves(root)
        root.wedge_start = 0
        root.wedge_end = 2 * math.pi
        layout._allocate_wedges(root, depth=0)

        # Each child should get π radians (180°)
        child_a, child_b = root.children
        assert abs(child_a.wedge_size - math.pi) < 0.001
        assert abs(child_b.wedge_size - math.pi) < 0.001

    def test_proportional_allocation(self):
        """Larger subtrees get more angular space."""
        layout = EadesRadialLayout(angle_spread=2*math.pi)
        hierarchy = {
            "id": "root",
            "children": {
                "small": {"id": "small"},  # 1 leaf
                "large": {
                    "id": "large",
                    "children": {
                        "l1": {"id": "l1"},
                        "l2": {"id": "l2"},
                        "l3": {"id": "l3"}
                    }
                }  # 3 leaves
            }
        }
        root = layout._build_tree(hierarchy)
        layout._count_leaves(root)
        root.wedge_start = 0
        root.wedge_end = 2 * math.pi
        layout._allocate_wedges(root, depth=0)

        small, large = root.children
        # Small: 1/4 of circle, Large: 3/4 of circle
        assert abs(small.wedge_size - math.pi/2) < 0.001
        assert abs(large.wedge_size - 3*math.pi/2) < 0.001


class TestNoOverlap:
    """Test that positions never overlap."""

    def test_bison_crab_separation(self):
        """
        Regression test: Bison and Crab must be well-separated.

        This was the original bug where both ended up at (0, -3100).
        """
        layout = EadesRadialLayout()

        # Simplified hierarchy mimicking the real bug
        hierarchy = {
            "id": "root",
            "children": {
                "chordata": {
                    "id": "chordata",
                    "children": {
                        "mammalia": {
                            "id": "mammalia",
                            "children": {
                                "artiodactyla": {
                                    "id": "artiodactyla",
                                    "children": {
                                        "bison": {"id": "bison"}
                                    }
                                }
                            }
                        }
                    }
                },
                "arthropoda": {
                    "id": "arthropoda",
                    "children": {
                        "malacostraca": {
                            "id": "malacostraca",
                            "children": {
                                "decapoda": {
                                    "id": "decapoda",
                                    "children": {
                                        "crab": {"id": "crab"}
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        positions = layout.calculate_layout(hierarchy)

        bison_pos = positions["bison"]
        crab_pos = positions["crab"]

        # Calculate Euclidean distance
        distance = math.sqrt(
            (bison_pos[0] - crab_pos[0])**2 +
            (bison_pos[1] - crab_pos[1])**2
        )

        # They should be far apart (at least 500 pixels)
        assert distance > 500, f"Bison and Crab too close: {distance}px"

    def test_no_duplicate_positions(self):
        """All nodes must have unique positions."""
        layout = EadesRadialLayout()
        hierarchy = self._create_large_tree(depth=5, branching=3)

        positions = layout.calculate_layout(hierarchy)

        # Round to avoid floating-point comparison issues
        rounded = {k: (round(v[0], 2), round(v[1], 2)) for k, v in positions.items()}
        unique_positions = set(rounded.values())

        assert len(unique_positions) == len(positions), "Duplicate positions found"

    def _create_large_tree(self, depth, branching, prefix="node"):
        """Helper to create test trees."""
        if depth == 0:
            return {"id": prefix}
        return {
            "id": prefix,
            "children": {
                f"{prefix}_{i}": self._create_large_tree(
                    depth - 1, branching, f"{prefix}_{i}"
                )
                for i in range(branching)
            }
        }


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_empty_hierarchy(self):
        """Empty input returns empty positions."""
        layout = EadesRadialLayout()
        assert layout.calculate_layout({}) == {}
        assert layout.calculate_layout(None) == {}

    def test_single_node(self):
        """Single node placed at origin."""
        layout = EadesRadialLayout()
        positions = layout.calculate_layout({"id": "root"})
        assert positions["root"] == (0.0, 0.0)

    def test_single_chain(self):
        """Long chain without siblings."""
        layout = EadesRadialLayout()
        hierarchy = {
            "id": "a",
            "children": {
                "b": {
                    "id": "b",
                    "children": {
                        "c": {
                            "id": "c",
                            "children": {
                                "d": {"id": "d"}
                            }
                        }
                    }
                }
            }
        }
        positions = layout.calculate_layout(hierarchy)

        # All nodes should have different radii
        radii = [math.sqrt(x**2 + y**2) for x, y in positions.values()]
        unique_radii = set(round(r, 2) for r in radii)
        assert len(unique_radii) == 4

    def test_very_unbalanced_tree(self):
        """One huge subtree, many tiny siblings."""
        layout = EadesRadialLayout()
        hierarchy = {
            "id": "root",
            "children": {
                "tiny1": {"id": "tiny1"},
                "tiny2": {"id": "tiny2"},
                "huge": {
                    "id": "huge",
                    "children": {
                        f"child_{i}": {"id": f"child_{i}"}
                        for i in range(100)
                    }
                }
            }
        }
        positions = layout.calculate_layout(hierarchy)

        # Verify no overlaps
        all_pos = list(positions.values())
        for i, p1 in enumerate(all_pos):
            for p2 in all_pos[i+1:]:
                dist = math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)
                assert dist > 1, "Overlapping nodes detected"
```

### 8.2 Integration Tests

```python
# server/graph/tests/test_tree_service_integration.py

import pytest
from django.test import TestCase
from graph.services_dynamic import DynamicTaxonomicTreeService


class TestTreeServiceIntegration(TestCase):
    """Integration tests with real tree service."""

    def test_real_hierarchy_no_overlaps(self):
        """Test with actual database data."""
        service = DynamicTaxonomicTreeService()
        tree_data = service.build_tree(mode="friends", user_id=self.user.id)

        positions = tree_data["layout"]["positions"]

        # Check minimum distance between any two nodes
        pos_list = list(positions.values())
        min_distance = float('inf')

        for i, p1 in enumerate(pos_list):
            for p2 in pos_list[i+1:]:
                dist = ((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)**0.5
                min_distance = min(min_distance, dist)

        # Nodes should be at least 50 pixels apart
        self.assertGreater(min_distance, 50)
```

### 8.3 Visual Regression Tests

Create a script to generate before/after visualizations:

```python
# scripts/visualize_tree_layout.py

import matplotlib.pyplot as plt
from graph.layout.eades_radial import EadesRadialLayout

def visualize_tree(hierarchy, output_path):
    """Generate visual test output."""
    layout = EadesRadialLayout()
    positions = layout.calculate_layout(hierarchy)

    fig, ax = plt.subplots(figsize=(12, 12))

    for node_id, (x, y) in positions.items():
        ax.plot(x, y, 'o', markersize=8)
        ax.annotate(node_id, (x, y), fontsize=6)

    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    plt.savefig(output_path, dpi=150)
    plt.close()
```

---

## 9. Migration Plan

### 9.1 Rollout Phases

| Phase | Description | Duration | Rollback |
|-------|-------------|----------|----------|
| 1 | Implement EadesRadialLayout class | 1-2 hours | N/A |
| 2 | Add comprehensive unit tests | 1 hour | N/A |
| 3 | Integrate behind feature flag | 30 min | Disable flag |
| 4 | Test on staging environment | 1 hour | Disable flag |
| 5 | Deploy to production | 30 min | Revert commit |
| 6 | Monitor for 24 hours | 24 hours | Revert commit |
| 7 | Remove feature flag, clean up old code | 30 min | N/A |

### 9.2 Feature Flag Implementation

```python
# server/biologidex/settings/base.py
FEATURE_FLAGS = {
    "USE_EADES_RADIAL_LAYOUT": True,  # Set False to rollback
}

# server/graph/services_dynamic.py
from django.conf import settings

def _calculate_layout(self, hierarchy, layout_type="radial"):
    if layout_type == "radial":
        if settings.FEATURE_FLAGS.get("USE_EADES_RADIAL_LAYOUT", False):
            layout_engine = EadesRadialLayout(...)
        else:
            layout_engine = RadialReingoldTilfordLayout(...)  # Old
    ...
```

### 9.3 Cache Invalidation

After deployment, invalidate the tree cache:

```bash
# Production
curl -X POST https://biologidex.com/api/v1/graph/invalidate-cache/ \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

### 9.4 Client Compatibility

The client code requires **no changes** because:
- Position format `[x, y]` is unchanged
- Coordinate space (world units) is unchanged
- The client already handles arbitrary positions

---

## 10. Risk Assessment

### 10.1 Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Algorithm bug causes new overlaps | Low | High | Comprehensive test suite |
| Performance regression on large trees | Low | Medium | Benchmark testing |
| Client rendering issues | Very Low | Medium | No API changes |
| Cache inconsistency | Low | Low | Force cache invalidation |

### 10.2 Rollback Procedure

1. Set `FEATURE_FLAGS["USE_EADES_RADIAL_LAYOUT"] = False`
2. Restart web/celery containers: `docker-compose restart web celery_worker`
3. Invalidate cache: `POST /api/v1/graph/invalidate-cache/`
4. Verify old layout is restored

### 10.3 Success Criteria

- [ ] All unit tests pass
- [ ] Bison and Crab are visually separated (manual verification)
- [ ] No performance regression (tree generation < 500ms for 1000 nodes)
- [ ] Zero client-side errors in production logs for 24 hours
- [ ] User feedback confirms improved visualization

---

## Appendix A: References

1. [ELK Radial Layout Documentation](https://eclipse.dev/elk/reference/algorithms/org-eclipse-elk-radial.html)
2. [D3.js Radial Tree Observable](https://observablehq.com/@d3/radial-tree/2)
3. [Stack Overflow: Radial Tree Layout Algorithm](https://stackoverflow.com/questions/33328245/radial-tree-layout-algorithm)
4. [Vega Radial Tree Example](https://vega.github.io/vega/examples/radial-tree-layout/)
5. [Stanford CS448B Lecture: Graphs and Trees](https://hci.stanford.edu/courses/cs448b/f09/lectures/CS448B-20091021-GraphsAndTrees.pdf)
6. [Andy Pavlo Thesis: Interactive Tree-Based Graph Visualization](https://www.cs.cmu.edu/~pavlo/papers/APavloThesis032006.pdf)
7. [PLANET: A Radial Layout Algorithm](https://www.sciencedirect.com/science/article/abs/pii/S037843711931670X)

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Annulus Wedge** | A pie-slice-shaped region between two concentric circles |
| **Leaf Count** | Number of terminal nodes in a subtree |
| **Angular Spread** | Total angle available for layout (360° = full circle) |
| **Radial Layout** | Tree visualization with root at center, depth as radius |
| **Walker-Buchheim** | O(n) algorithm for rectangular tree layout |
| **Eades Algorithm** | Radial layout using proportional wedge allocation |
