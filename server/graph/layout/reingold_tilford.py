"""
Reingold-Tilford tree layout algorithm for taxonomic trees.
Implements the Walker-Buchheim O(n) algorithm for aesthetically pleasing hierarchical layouts.

Based on:
- Reingold & Tilford (1981): "Tidier Drawings of Trees"
- Walker (1990): "A Node-Positioning Algorithm for General Trees"
- Buchheim, Jünger & Leipert (2002): "Improving Walker's Algorithm to Run in Linear Time"
"""
import logging
from typing import Dict, List, Tuple, Optional

logger = logging.getLogger(__name__)


class TreeNode:
    """
    Internal node representation for Walker-Buchheim layout algorithm.

    Attributes for layout computation:
        x, y: Final position coordinates
        prelim: Preliminary x coordinate (before modifiers applied)
        mod: Modifier to be applied to all descendants
        thread: Thread pointer for efficient contour traversal
        ancestor: Ancestor reference for conflict resolution
        change, shift: For distributing shifts among siblings
        number: Sibling index for O(1) access
    """
    def __init__(self, node_id: str, rank: str, name: str, children: Optional[List['TreeNode']] = None):
        self.id = node_id
        self.rank = rank
        self.name = name
        self.children = children or []

        # Position coordinates
        self.x = 0.0
        self.y = 0.0

        # Walker-Buchheim algorithm properties
        self.prelim = 0.0  # Preliminary x coordinate
        self.mod = 0.0  # Modifier for subtree positioning
        self.shift = 0.0  # Shift value for spacing adjustment
        self.change = 0.0  # Change in shift for subtree separation

        # Pointers for efficient traversal
        self.thread = None  # Thread pointer to next contour node
        self.ancestor = self  # Ancestor for conflict resolution
        self.parent = None  # Parent node reference
        self.number = -1  # Sibling index (0-based)

        # Cache for leftmost sibling (O(1) access)
        self._leftmost_sibling = None

    def is_leaf(self) -> bool:
        """Check if node is a leaf (no children)."""
        return len(self.children) == 0

    def left_sibling(self) -> Optional['TreeNode']:
        """Get left sibling in O(1) time using sibling index."""
        if self.parent and self.number > 0:
            return self.parent.children[self.number - 1]
        return None

    def leftmost_sibling(self) -> Optional['TreeNode']:
        """Get leftmost sibling in O(1) time."""
        if self._leftmost_sibling is None and self.parent and self.number > 0:
            self._leftmost_sibling = self.parent.children[0]
        return self._leftmost_sibling

    def next_left(self) -> Optional['TreeNode']:
        """Get next node on left contour (for traversal)."""
        if self.children:
            return self.children[0]
        return self.thread

    def next_right(self) -> Optional['TreeNode']:
        """Get next node on right contour (for traversal)."""
        if self.children:
            return self.children[-1]
        return self.thread


class ReingoldTilfordLayout:
    """
    Implements the Walker-Buchheim O(n) tree layout algorithm.

    Features:
    - O(n) time complexity for n nodes
    - Proper handling of m-ary trees (nodes with any number of children)
    - Efficient contour threading
    - Subtree conflict resolution
    - Aesthetically pleasing, compact layouts

    Aesthetic properties:
    1. Nodes at same depth on same horizontal line
    2. Parent nodes centered over children
    3. Subtrees as narrow as possible without overlap
    4. Identical subtrees have identical layouts
    5. Left-to-right ordering preserved
    """

    def __init__(self, h_spacing: float = 100.0, v_spacing: float = 150.0, min_distance: float = 100.0):
        """
        Initialize Walker-Buchheim layout engine.

        Args:
            h_spacing: Horizontal spacing between sibling nodes (deprecated, use min_distance)
            v_spacing: Vertical spacing between tree levels
            min_distance: Minimum horizontal distance between nodes
        """
        self.distance = min_distance if min_distance else h_spacing
        self.v_spacing = v_spacing
        self.node_counter = 0

    def calculate_layout(self, hierarchy: Dict) -> Dict[str, Tuple[float, float]]:
        """
        Calculate positions for all nodes in the tree using Walker-Buchheim algorithm.

        Time complexity: O(n) where n is the number of nodes
        Space complexity: O(n)

        Args:
            hierarchy: Tree structure from DynamicTaxonomicTreeService

        Returns:
            Dict mapping node IDs to (x, y) position tuples
        """
        logger.info("Calculating Walker-Buchheim layout (O(n) linear time)")

        # Build internal tree structure with proper parent/sibling references
        root = self._build_tree_nodes(hierarchy)

        if not root:
            logger.warning("Empty tree hierarchy provided")
            return {}

        # Execute Walker-Buchheim algorithm
        self._first_walk(root)
        self._second_walk(root, -root.prelim)

        # Extract final positions
        positions = self._extract_positions(root)

        logger.info(f"Layout calculated for {len(positions)} nodes")
        return positions

    def _build_tree_nodes(self, node_dict: Dict, parent: Optional[TreeNode] = None,
                         sibling_index: int = 0, depth: int = 0) -> Optional[TreeNode]:
        """
        Recursively build TreeNode structure with proper parent and sibling references.

        Args:
            node_dict: Node from hierarchy
            parent: Parent TreeNode
            sibling_index: Index among siblings (0-based)
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

        # Create node with proper references
        tree_node = TreeNode(node_id, rank, name)
        tree_node.y = depth * self.v_spacing
        tree_node.parent = parent
        tree_node.number = sibling_index

        # Process taxonomic children
        children = node_dict.get('children', {})
        child_index = 0
        for child_name, child_dict in children.items():
            child_node = self._build_tree_nodes(child_dict, tree_node, child_index, depth + 1)
            if child_node:
                tree_node.children.append(child_node)
                child_index += 1

        # Process animal leaves with proper parent references (FIX FOR BUG)
        animals = node_dict.get('animals', [])
        for animal in animals:
            animal_id = str(animal.id)
            animal_node = TreeNode(animal_id, 'species', animal.scientific_name)
            animal_node.y = (depth + 1) * self.v_spacing
            animal_node.parent = tree_node  # CRITICAL: Set parent for proper spacing
            animal_node.number = child_index
            tree_node.children.append(animal_node)
            child_index += 1

        return tree_node

    def _first_walk(self, node: TreeNode):
        """
        First post-order walk: compute preliminary x coordinates and modifiers.

        This is the core of the Walker-Buchheim algorithm. It processes the tree
        bottom-up, positioning each node and resolving conflicts between subtrees.

        Time complexity: O(n) with threading optimization
        """
        if node.is_leaf():
            # Leaf nodes: position relative to left sibling
            left_sib = node.left_sibling()
            if left_sib:
                node.prelim = left_sib.prelim + self.distance
            else:
                node.prelim = 0.0
        else:
            # Internal nodes: process children first, then position based on them
            default_ancestor = node.children[0]

            for child in node.children:
                self._first_walk(child)
                default_ancestor = self._apportion(child, default_ancestor)

            # Execute accumulated shifts
            self._execute_shifts(node)

            # Center parent over children
            leftmost = node.children[0]
            rightmost = node.children[-1]
            midpoint = (leftmost.prelim + rightmost.prelim) / 2.0

            left_sib = node.left_sibling()
            if left_sib:
                node.prelim = left_sib.prelim + self.distance
                node.mod = node.prelim - midpoint
            else:
                node.prelim = midpoint

    def _apportion(self, node: TreeNode, default_ancestor: TreeNode) -> TreeNode:
        """
        Resolve conflicts between subtrees by shifting them apart.

        This is the key to achieving O(n) complexity. It uses threading to traverse
        contours efficiently and distributes shifts among siblings.

        Args:
            node: Current node being positioned
            default_ancestor: Ancestor to use for conflict resolution

        Returns:
            Updated default_ancestor
        """
        left_sib = node.left_sibling()
        if not left_sib:
            return default_ancestor

        # Track both contours simultaneously
        # Inner: contours between the two subtrees
        # Outer: contours on outside edges
        vip = node  # Inner right (current subtree)
        vop = node  # Outer right
        vim = left_sib  # Inner left (previous subtree)
        vom = node.leftmost_sibling()  # Outer left

        # Track cumulative modifiers
        sip = vip.mod
        sop = vop.mod
        sim = vim.mod
        som = vom.mod if vom else 0.0

        # Traverse down both contours until one ends
        nr = vim.next_right()
        nl = vip.next_left()

        while nr and nl:
            vim = nr
            vip = nl
            vom = vom.next_left() if vom else None
            vop = vop.next_right()

            # Update ancestor pointers
            vop.ancestor = node

            # Calculate required shift
            shift = (vim.prelim + sim) - (vip.prelim + sip) + self.distance

            if shift > 0:
                # Move subtree to avoid overlap
                self._move_subtree(
                    self._ancestor(vim, node, default_ancestor),
                    node,
                    shift
                )
                sip += shift
                sop += shift

            # Update modifier sums
            sim += vim.mod
            sip += vip.mod
            som += vom.mod if vom else 0.0
            sop += vop.mod

            nr = vim.next_right()
            nl = vip.next_left()

        # Set threads for efficient future traversals
        if nr and not vop.next_right():
            vop.thread = nr
            vop.mod += sim - sop

        if nl and not vom.next_left() if vom else True:
            if vom:
                vom.thread = nl
                vom.mod += sip - som
            default_ancestor = node

        return default_ancestor

    def _move_subtree(self, wl: TreeNode, wr: TreeNode, shift: float):
        """
        Move subtree wr to the right by shift amount, relative to wl.

        Distributes the shift among intermediate siblings for smooth spacing.

        Args:
            wl: Left subtree
            wr: Right subtree to shift
            shift: Amount to shift right
        """
        subtrees = wr.number - wl.number
        if subtrees > 0:
            wr.change -= shift / subtrees
            wr.shift += shift
            wl.change += shift / subtrees
            wr.prelim += shift
            wr.mod += shift

    def _execute_shifts(self, node: TreeNode):
        """
        Execute accumulated shifts on all children of node.

        This distributes the spacing adjustments computed during apportioning.

        Args:
            node: Parent node whose children need shift execution
        """
        shift = 0.0
        change = 0.0

        # Process children right to left
        for child in reversed(node.children):
            child.prelim += shift
            child.mod += shift
            change += child.change
            shift += child.shift + change

    def _ancestor(self, vim: TreeNode, node: TreeNode, default_ancestor: TreeNode) -> TreeNode:
        """
        Get the correct ancestor for conflict resolution.

        Args:
            vim: Node from left subtree contour
            node: Current node being positioned
            default_ancestor: Fallback ancestor

        Returns:
            Appropriate ancestor for move_subtree operation
        """
        if vim.ancestor.parent == node.parent:
            return vim.ancestor
        return default_ancestor

    def _second_walk(self, node: TreeNode, modsum: float = 0.0, depth: int = 0):
        """
        Second pre-order walk: compute final x coordinates by applying modifiers.

        Args:
            node: Current node
            modsum: Cumulative modifier from ancestors
            depth: Current depth (for y coordinate)
        """
        node.x = node.prelim + modsum
        node.y = depth * self.v_spacing

        for child in node.children:
            self._second_walk(child, modsum + node.mod, depth + 1)

    def _extract_positions(self, root: TreeNode) -> Dict[str, Tuple[float, float]]:
        """
        Extract final (x, y) positions from all nodes in the tree.

        Args:
            root: Root of the positioned tree

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
