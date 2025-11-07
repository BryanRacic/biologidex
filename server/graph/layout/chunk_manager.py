"""
Spatial chunking manager for progressive tree loading.
Divides the tree layout into chunks for efficient data transfer.
"""
import logging
import math
from typing import Dict, List, Tuple, Set
from collections import defaultdict

logger = logging.getLogger(__name__)


class ChunkManager:
    """
    Manages spatial chunking of tree layout for progressive loading.

    Divides the world space into fixed-size chunks and distributes
    nodes and edges accordingly.
    """

    def __init__(self, chunk_size: int = 2048):
        """
        Initialize chunk manager.

        Args:
            chunk_size: Size of each chunk in world units (width and height)
        """
        self.chunk_size = chunk_size
        self.world_bounds = None

    def generate_chunks(
        self,
        nodes: List[Dict],
        edges: List[Dict],
        positions: Dict[str, Tuple[float, float]]
    ) -> Dict:
        """
        Generate chunk metadata from nodes and edges.

        Args:
            nodes: List of node dicts
            edges: List of edge dicts
            positions: Dict mapping node IDs to (x, y) positions

        Returns:
            Dict containing chunk metadata and distribution
        """
        logger.info(f"Generating chunks with size {self.chunk_size}")

        # Calculate world bounds
        self._calculate_world_bounds(positions)

        # Build node-to-chunk mapping
        node_chunks = self._assign_nodes_to_chunks(nodes, positions)

        # Build edge-to-chunk mapping
        edge_chunks = self._assign_edges_to_chunks(edges, positions, node_chunks)

        # Build chunk metadata
        chunk_metadata = self._build_chunk_metadata(node_chunks, edge_chunks)

        logger.info(f"Generated {len(chunk_metadata)} chunks")

        return {
            'chunks': chunk_metadata,
            'world_bounds': self.world_bounds,
            'chunk_size': self.chunk_size,
            'total_chunks': len(chunk_metadata)
        }

    def _calculate_world_bounds(self, positions: Dict[str, Tuple[float, float]]):
        """
        Calculate the bounding box of all node positions.

        Sets self.world_bounds to (min_x, min_y, max_x, max_y)
        """
        if not positions:
            self.world_bounds = (0, 0, 0, 0)
            return

        xs = [pos[0] for pos in positions.values()]
        ys = [pos[1] for pos in positions.values()]

        min_x = min(xs)
        max_x = max(xs)
        min_y = min(ys)
        max_y = max(ys)

        # Add padding
        padding = self.chunk_size * 0.1
        self.world_bounds = (
            min_x - padding,
            min_y - padding,
            max_x + padding,
            max_y + padding
        )

        logger.info(f"World bounds: {self.world_bounds}")

    def get_world_bounds(self) -> Tuple[float, float, float, float]:
        """Get the world bounds (min_x, min_y, max_x, max_y)."""
        return self.world_bounds or (0, 0, 0, 0)

    def _position_to_chunk_coords(self, x: float, y: float) -> Tuple[int, int]:
        """
        Convert world position to chunk coordinates.

        Args:
            x, y: World position

        Returns:
            (chunk_x, chunk_y) tuple
        """
        chunk_x = math.floor(x / self.chunk_size)
        chunk_y = math.floor(y / self.chunk_size)
        return (chunk_x, chunk_y)

    def _assign_nodes_to_chunks(
        self,
        nodes: List[Dict],
        positions: Dict[str, Tuple[float, float]]
    ) -> Dict[Tuple[int, int], List[str]]:
        """
        Assign each node to its containing chunk.

        Returns:
            Dict mapping chunk coords to list of node IDs
        """
        node_chunks = defaultdict(list)

        for node in nodes:
            node_id = node['id']
            if node_id not in positions:
                logger.warning(f"Node {node_id} has no position")
                continue

            x, y = positions[node_id]
            chunk_coords = self._position_to_chunk_coords(x, y)
            node_chunks[chunk_coords].append(node_id)

        return dict(node_chunks)

    def _assign_edges_to_chunks(
        self,
        edges: List[Dict],
        positions: Dict[str, Tuple[float, float]],
        node_chunks: Dict[Tuple[int, int], List[str]]
    ) -> Dict[Tuple[int, int], List[Dict]]:
        """
        Assign edges to chunks based on their endpoints.

        An edge is included in a chunk if either endpoint is in that chunk.

        Returns:
            Dict mapping chunk coords to list of edge dicts
        """
        edge_chunks = defaultdict(list)

        # Build reverse mapping: node_id -> chunk_coords
        node_to_chunk = {}
        for chunk_coords, node_ids in node_chunks.items():
            for node_id in node_ids:
                node_to_chunk[node_id] = chunk_coords

        for edge in edges:
            source_id = edge['source']
            target_id = edge['target']

            # Get chunks for both endpoints
            source_chunk = node_to_chunk.get(source_id)
            target_chunk = node_to_chunk.get(target_id)

            if not source_chunk or not target_chunk:
                logger.warning(f"Edge {source_id}->{target_id} has missing endpoint chunk")
                continue

            # Add edge to all chunks it crosses
            chunks_to_add = self._get_chunks_for_edge(
                positions.get(source_id),
                positions.get(target_id)
            )

            for chunk_coords in chunks_to_add:
                edge_chunks[chunk_coords].append(edge)

        return dict(edge_chunks)

    def _get_chunks_for_edge(
        self,
        pos1: Tuple[float, float],
        pos2: Tuple[float, float]
    ) -> Set[Tuple[int, int]]:
        """
        Get all chunks that an edge passes through.

        Uses simple line rasterization.

        Returns:
            Set of chunk coordinates
        """
        if not pos1 or not pos2:
            return set()

        x1, y1 = pos1
        x2, y2 = pos2

        chunk1 = self._position_to_chunk_coords(x1, y1)
        chunk2 = self._position_to_chunk_coords(x2, y2)

        # If edge is within single chunk, return that chunk
        if chunk1 == chunk2:
            return {chunk1}

        # Otherwise, get all chunks the line passes through
        chunks = {chunk1, chunk2}

        # Sample points along the edge
        num_samples = int(max(abs(chunk2[0] - chunk1[0]), abs(chunk2[1] - chunk1[1])) * 2) + 1
        for i in range(1, num_samples):
            t = i / num_samples
            x = x1 + (x2 - x1) * t
            y = y1 + (y2 - y1) * t
            chunks.add(self._position_to_chunk_coords(x, y))

        return chunks

    def _build_chunk_metadata(
        self,
        node_chunks: Dict[Tuple[int, int], List[str]],
        edge_chunks: Dict[Tuple[int, int], List[Dict]]
    ) -> List[Dict]:
        """
        Build metadata for each chunk.

        Returns:
            List of chunk metadata dicts
        """
        # Get all unique chunk coordinates
        all_chunk_coords = set(node_chunks.keys()) | set(edge_chunks.keys())

        chunk_metadata = []
        for chunk_x, chunk_y in sorted(all_chunk_coords):
            node_count = len(node_chunks.get((chunk_x, chunk_y), []))
            edge_count = len(edge_chunks.get((chunk_x, chunk_y), []))

            # Calculate world bounds for this chunk
            world_x = chunk_x * self.chunk_size
            world_y = chunk_y * self.chunk_size

            chunk_metadata.append({
                'chunk_x': chunk_x,
                'chunk_y': chunk_y,
                'node_count': node_count,
                'edge_count': edge_count,
                'world_bounds': {
                    'min_x': world_x,
                    'min_y': world_y,
                    'max_x': world_x + self.chunk_size,
                    'max_y': world_y + self.chunk_size
                }
            })

        return chunk_metadata

    def get_chunk(
        self,
        chunk_x: int,
        chunk_y: int,
        tree_data: Dict
    ) -> Dict:
        """
        Extract data for a specific chunk.

        Args:
            chunk_x, chunk_y: Chunk coordinates
            tree_data: Full tree data from DynamicTaxonomicTreeService

        Returns:
            Dict containing nodes and edges for this chunk
        """
        positions = tree_data['layout']['positions']
        all_nodes = tree_data['nodes']
        all_edges = tree_data['edges']

        # Filter nodes in this chunk
        chunk_nodes = []
        for node in all_nodes:
            node_id = node['id']
            if node_id in positions:
                x, y = positions[node_id]
                node_chunk = self._position_to_chunk_coords(x, y)
                if node_chunk == (chunk_x, chunk_y):
                    chunk_nodes.append(node)

        # Filter edges in this chunk
        chunk_edges = []
        for edge in all_edges:
            source_id = edge['source']
            target_id = edge['target']

            if source_id in positions and target_id in positions:
                # Check if edge crosses this chunk
                chunks = self._get_chunks_for_edge(
                    positions[source_id],
                    positions[target_id]
                )
                if (chunk_x, chunk_y) in chunks:
                    chunk_edges.append(edge)

        return {
            'chunk_x': chunk_x,
            'chunk_y': chunk_y,
            'nodes': chunk_nodes,
            'edges': chunk_edges,
            'node_count': len(chunk_nodes),
            'edge_count': len(chunk_edges)
        }
