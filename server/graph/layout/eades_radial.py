"""
Eades Radial Tree Layout Algorithm.

Implements angular wedge allocation based on subtree leaf counts,
guaranteeing overlap-free radial tree visualizations.

Based on: Eades, P. (1991). "Drawing Free Trees"

This algorithm replaces the previous RadialReingoldTilfordLayout which suffered
from node overlap issues when retrofitting rectangular Walker-Buchheim coordinates
onto a radial coordinate system.

Key advantages:
- Guaranteed overlap-free by construction
- Angular space proportional to subtree size (taxonomic diversity)
- O(n) time complexity
- Purpose-built for radial visualizations

Time Complexity: O(n)
Space Complexity: O(n)
"""
import logging
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class RadialNode:
    """
    Internal node representation for Eades radial layout computation.

    Attributes:
        id: Unique node identifier
        rank: Taxonomic rank (e.g., 'kingdom', 'phylum', 'species', 'animal')
        name: Display name
        children: Child nodes
        parent: Parent node reference

        # Computed during layout:
        leaf_count: Number of leaves in this subtree
        wedge_start: Starting angle of this node's angular wedge (radians)
        wedge_end: Ending angle of this node's angular wedge (radians)
        depth: Distance from root (0 for root)
    """
    id: str
    rank: str
    name: str
    children: List['RadialNode'] = field(default_factory=list)
    parent: Optional['RadialNode'] = None

    # Layout properties computed by algorithm
    leaf_count: int = 0
    wedge_start: float = 0.0
    wedge_end: float = 0.0
    depth: int = 0

    @property
    def wedge_center(self) -> float:
        """Angular center of this node's wedge (radians)."""
        return (self.wedge_start + self.wedge_end) / 2.0

    @property
    def wedge_size(self) -> float:
        """Angular size of this node's wedge (radians)."""
        return self.wedge_end - self.wedge_start

    def is_leaf(self) -> bool:
        """True if node has no children."""
        return len(self.children) == 0


class EadesRadialLayout:
    """
    Radial tree layout using Eades's angular wedge allocation algorithm.

    Each subtree receives an angular wedge proportional to its number of leaves,
    guaranteeing no overlapping nodes by construction.

    Algorithm phases:
    1. Build tree structure from hierarchy dict
    2. Count leaves (post-order traversal) - each node stores subtree leaf count
    3. Allocate wedges (pre-order traversal) - divide parent's wedge among children
    4. Extract positions - convert (angle, radius) to (x, y) Cartesian coordinates

    Attributes:
        angle_spread: Total angular spread in radians (2π = full circle)
        min_radius: Radius of first level from center (pixels)
        radius_per_level: Radial distance between tree levels (pixels)
        start_angle: Starting angle for layout (-π/2 = top, tree grows downward)
    """

    def __init__(
        self,
        angle_spread: float = 2 * math.pi,
        min_radius: float = 300.0,
        radius_per_level: float = 400.0,
        start_angle: float = -math.pi / 2
    ):
        """
        Initialize Eades radial layout engine.

        Args:
            angle_spread: Total angular spread in radians (default: 2π for full circle)
            min_radius: Radius of first level from center in pixels (default: 300)
            radius_per_level: Radial distance between levels in pixels (default: 400)
            start_angle: Starting angle in radians (default: -π/2 for top)
        """
        self.angle_spread = angle_spread
        self.min_radius = min_radius
        self.radius_per_level = radius_per_level
        self.start_angle = start_angle
        self._node_counter = 0

    def calculate_layout(self, hierarchy: Dict) -> Dict[str, Tuple[float, float]]:
        """
        Calculate radial positions for all nodes using Eades wedge allocation.

        This is the main entry point for layout calculation.

        Args:
            hierarchy: Tree structure from DynamicTaxonomicTreeService
                       Expected format: {id, rank, name, children: {name: {...}}, animals: [...]}

        Returns:
            Dict mapping node IDs to (x, y) Cartesian coordinates
        """
        logger.info("Calculating Eades radial layout (O(n) linear time)")
        self._node_counter = 0

        if not hierarchy:
            logger.warning("Empty hierarchy provided")
            return {}

        # Phase 1: Build tree structure
        root = self._build_tree(hierarchy)
        if not root:
            logger.warning("Failed to build tree from hierarchy")
            return {}

        # Phase 2: Count leaves (post-order traversal)
        self._count_leaves(root)
        logger.debug(f"Tree has {root.leaf_count} total leaves across {self._node_counter} nodes")

        # Phase 3: Allocate angular wedges (pre-order traversal)
        root.wedge_start = self.start_angle
        root.wedge_end = self.start_angle + self.angle_spread
        self._allocate_wedges(root, depth=0)

        # Phase 4: Extract Cartesian positions
        positions = self._extract_positions(root)

        logger.info(f"Layout complete: {len(positions)} nodes positioned")
        return positions

    def _build_tree(
        self,
        node_dict: Dict,
        parent: Optional[RadialNode] = None,
        depth: int = 0
    ) -> Optional[RadialNode]:
        """
        Recursively build RadialNode tree from hierarchy dictionary.

        Args:
            node_dict: Node data from hierarchy
            parent: Parent RadialNode (None for root)
            depth: Current depth in tree

        Returns:
            RadialNode representing this subtree, or None if input is invalid
        """
        if not node_dict:
            return None

        # Generate unique ID if not provided
        node_id = node_dict.get('id')
        if node_id is None:
            node_id = f'node_{self._node_counter}'
        self._node_counter += 1

        node = RadialNode(
            id=str(node_id),
            rank=node_dict.get('rank', 'unknown'),
            name=node_dict.get('name', 'Unknown'),
            parent=parent,
            depth=depth
        )

        # Process taxonomic children (dict with name keys)
        children_dict = node_dict.get('children', {})
        for child_name, child_dict in children_dict.items():
            child = self._build_tree(child_dict, parent=node, depth=depth + 1)
            if child:
                node.children.append(child)

        # Process animal leaves (list of Animal objects)
        animals = node_dict.get('animals', [])
        for animal in animals:
            animal_node = RadialNode(
                id=str(animal.id),
                rank='animal',
                name=getattr(animal, 'scientific_name', str(animal)),
                parent=node,
                depth=depth + 1
            )
            self._node_counter += 1
            node.children.append(animal_node)

        return node

    def _count_leaves(self, node: RadialNode) -> int:
        """
        Count leaves in subtree using post-order traversal.

        Sets node.leaf_count for all nodes in the subtree.
        A leaf node has leaf_count = 1.
        An internal node has leaf_count = sum of children's leaf_counts.

        Args:
            node: Root of subtree to count

        Returns:
            Number of leaves in this subtree
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
        Allocate angular wedges to all nodes using pre-order traversal.

        Each node is positioned at the center of its wedge.
        Children divide the parent's wedge proportionally by their leaf counts.

        This is the core of the Eades algorithm - it guarantees no overlaps
        because each subtree gets a non-overlapping angular region proportional
        to its size (number of leaves).

        Args:
            node: Current node to position
            depth: Current depth in tree
        """
        node.depth = depth

        # If this is a leaf node, we're done (no children to allocate to)
        if node.is_leaf():
            return

        # Guard against division by zero (shouldn't happen if tree is well-formed)
        if node.leaf_count == 0:
            logger.warning(f"Node {node.id} has leaf_count=0 but has children")
            return

        # Divide wedge among children proportionally based on their leaf counts
        current_angle = node.wedge_start
        parent_wedge_size = node.wedge_size

        for child in node.children:
            # Fraction of parent's leaves that are in this child's subtree
            fraction = child.leaf_count / node.leaf_count
            child_wedge_size = parent_wedge_size * fraction

            child.wedge_start = current_angle
            child.wedge_end = current_angle + child_wedge_size
            current_angle = child.wedge_end

            # Recurse to child's subtree
            self._allocate_wedges(child, depth + 1)

    def _extract_positions(self, root: RadialNode) -> Dict[str, Tuple[float, float]]:
        """
        Extract Cartesian (x, y) positions from all nodes.

        Converts each node's (angle, radius) polar coordinates to Cartesian.
        - angle = center of node's wedge
        - radius = min_radius + (depth - 1) * radius_per_level for depth > 0
        - radius = 0 for root (at center)

        Args:
            root: Root of the positioned tree

        Returns:
            Dict mapping node IDs to (x, y) tuples
        """
        positions = {}

        def traverse(node: RadialNode):
            # Calculate radius based on depth
            if node.depth == 0:
                radius = 0.0  # Root at center
            else:
                radius = self.min_radius + (node.depth - 1) * self.radius_per_level

            # Calculate Cartesian coordinates from polar
            angle = node.wedge_center
            x = radius * math.cos(angle)
            y = radius * math.sin(angle)

            positions[node.id] = (x, y)

            # Recurse to children
            for child in node.children:
                traverse(child)

        traverse(root)
        return positions

    def get_layout_metadata(self, positions: Dict[str, Tuple[float, float]]) -> Dict:
        """
        Return metadata about the layout for client rendering hints.

        Args:
            positions: Computed node positions

        Returns:
            Dict containing layout type, algorithm name, parameters, and bounds
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
            "start_angle_degrees": math.degrees(self.start_angle),
            "bounds": {
                "min_x": min(all_x) if all_x else 0,
                "max_x": max(all_x) if all_x else 0,
                "min_y": min(all_y) if all_y else 0,
                "max_y": max(all_y) if all_y else 0,
            },
            "center": (0.0, 0.0)
        }
