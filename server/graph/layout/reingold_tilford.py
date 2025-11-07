"""
Reingold-Tilford tree layout algorithm for taxonomic trees.
Produces aesthetically pleasing hierarchical layouts.
"""
import logging
from typing import Dict, List, Tuple, Optional

logger = logging.getLogger(__name__)


class TreeNode:
    """
    Internal node representation for layout algorithm.
    """
    def __init__(self, node_id: str, rank: str, name: str, children: Optional[List['TreeNode']] = None):
        self.id = node_id
        self.rank = rank
        self.name = name
        self.children = children or []

        # Layout properties
        self.x = 0.0
        self.y = 0.0
        self.mod = 0.0  # Modifier for subtree positioning
        self.prelim = 0.0  # Preliminary x coordinate
        self.thread = None  # Thread pointer for complex layouts
        self.ancestor = self  # Reference to ancestor for conflict resolution

    def is_leaf(self) -> bool:
        return len(self.children) == 0

    def get_left_sibling(self, parent: Optional['TreeNode']) -> Optional['TreeNode']:
        """Get the left sibling of this node."""
        if parent:
            siblings = parent.children
            for i, sibling in enumerate(siblings):
                if sibling == self and i > 0:
                    return siblings[i - 1]
        return None


class ReingoldTilfordLayout:
    """
    Implements the Reingold-Tilford algorithm for tree layout.

    Creates aesthetically pleasing, compact tree layouts with:
    - Nodes at the same depth on the same horizontal line
    - Parent nodes centered over children
    - Subtrees as narrow as possible
    - Identical subtrees with identical layouts
    """

    def __init__(self, h_spacing: float = 100.0, v_spacing: float = 150.0):
        """
        Initialize layout engine.

        Args:
            h_spacing: Horizontal spacing between nodes
            v_spacing: Vertical spacing between levels
        """
        self.h_spacing = h_spacing
        self.v_spacing = v_spacing
        self.node_counter = 0

    def calculate_layout(self, hierarchy: Dict) -> Dict[str, Tuple[float, float]]:
        """
        Calculate positions for all nodes in the tree.

        Args:
            hierarchy: Tree structure from DynamicTaxonomicTreeService

        Returns:
            Dict mapping node IDs to (x, y) positions
        """
        logger.info("Calculating Reingold-Tilford layout")

        # Build internal tree structure
        root = self._build_tree_nodes(hierarchy)

        if not root:
            return {}

        # Execute layout algorithm
        self._first_walk(root)
        self._second_walk(root, -root.prelim)

        # Extract positions
        positions = self._extract_positions(root)

        logger.info(f"Layout calculated for {len(positions)} nodes")
        return positions

    def _build_tree_nodes(self, node_dict: Dict, depth: int = 0) -> Optional[TreeNode]:
        """
        Recursively build TreeNode structure from hierarchy dict.

        Args:
            node_dict: Node from hierarchy
            depth: Current depth in tree

        Returns:
            TreeNode representing this subtree
        """
        if not node_dict:
            return None

        node_id = node_dict.get('id', f'node_{self.node_counter}')
        self.node_counter += 1

        rank = node_dict.get('rank', 'unknown')
        name = node_dict.get('name', 'Unknown')

        # Create node
        tree_node = TreeNode(node_id, rank, name)
        tree_node.y = depth * self.v_spacing

        # Process children (taxonomic ranks)
        children = node_dict.get('children', {})
        for child_name, child_dict in children.items():
            child_node = self._build_tree_nodes(child_dict, depth + 1)
            if child_node:
                tree_node.children.append(child_node)

        # Process animal leaves
        animals = node_dict.get('animals', [])
        for animal in animals:
            animal_id = str(animal.id)
            animal_node = TreeNode(animal_id, 'species', animal.scientific_name)
            animal_node.y = (depth + 1) * self.v_spacing
            tree_node.children.append(animal_node)

        return tree_node

    def _first_walk(self, node: TreeNode, depth: int = 0):
        """
        First post-order walk to compute preliminary x coordinates.

        This is the core of the Reingold-Tilford algorithm.
        """
        node.y = depth * self.v_spacing

        if node.is_leaf():
            # Leaf node: position relative to left sibling
            left_sibling = node.get_left_sibling(getattr(node, '_parent', None))
            if left_sibling:
                node.prelim = left_sibling.prelim + self.h_spacing
            else:
                node.prelim = 0.0
        else:
            # Internal node: position based on children
            # Store parent reference for sibling lookups
            for child in node.children:
                child._parent = node
                self._first_walk(child, depth + 1)

            # Get leftmost and rightmost children
            leftmost_child = node.children[0]
            rightmost_child = node.children[-1]

            # Place parent at midpoint of children
            midpoint = (leftmost_child.prelim + rightmost_child.prelim) / 2.0

            left_sibling = node.get_left_sibling(getattr(node, '_parent', None))
            if left_sibling:
                node.prelim = left_sibling.prelim + self.h_spacing
                node.mod = node.prelim - midpoint
            else:
                node.prelim = midpoint

    def _second_walk(self, node: TreeNode, modsum: float = 0.0):
        """
        Second pre-order walk to compute final x coordinates.

        Args:
            node: Current node
            modsum: Cumulative modifier from ancestors
        """
        node.x = node.prelim + modsum

        for child in node.children:
            self._second_walk(child, modsum + node.mod)

    def _extract_positions(self, root: TreeNode) -> Dict[str, Tuple[float, float]]:
        """
        Extract final positions from tree nodes.

        Returns:
            Dict mapping node IDs to (x, y) tuples
        """
        positions = {}

        def traverse(node: TreeNode):
            positions[node.id] = (node.x, node.y)
            for child in node.children:
                traverse(child)

        traverse(root)
        return positions
