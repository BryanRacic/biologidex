# Dynamic Taxonomic Tree - Implementation Checklist

## Overview
This checklist outlines all files that need to be created or modified to implement the dynamic user-specific taxonomic tree feature. Each user will see a unique tree based on their dex entries and those of their friends.

## Server Implementation (Django)

### 1. Core Service Updates

#### **CREATE** `server/graph/services_dynamic.py`
```python
# New service class: DynamicTaxonomicTreeService
# - Supports modes: personal, friends, selected, global (admin)
# - User-specific caching with proper invalidation
# - Optimized queries with prefetch_related/select_related
# - True parent-child hierarchy (not same_family)
```

#### **CREATE** `server/graph/layout/reingold_tilford.py`
```python
# Tree layout algorithm implementation
# - Calculate x,y positions for nodes
# - Support for 100k+ nodes
# - Hierarchical layout with proper spacing
```

#### **CREATE** `server/graph/layout/chunk_manager.py`
```python
# Spatial chunking for progressive loading
# - 2048x2048 chunk size
# - Efficient node/edge distribution
# - Chunk metadata generation
```

#### **UPDATE** `server/graph/services.py`
```python
# Keep existing service but mark as deprecated
# Add migration helper methods
# Update to use new edge type (parent_child vs same_family)
```

### 2. API Views & URLs

#### **UPDATE** `server/graph/views.py`
```python
# Add new view classes:
# - DynamicTreeView (main endpoint with mode support)
# - TreeChunkView (chunk loading)
# - TreeSearchView (scoped search)
# - TreeInvalidateView (cache management)
# - FriendTreeCombinationView (friend selection UI)
```

#### **UPDATE** `server/graph/urls.py`
```python
# Add new URL patterns:
# - /tree/ (main dynamic tree)
# - /tree/chunk/<x>/<y>/ (chunk loading)
# - /tree/search/ (search within scope)
# - /tree/invalidate/ (cache management)
# - /tree/friends/ (friend selection)
```

### 3. Model Updates

#### **UPDATE** `server/animals/models.py`
```python
# Add database indexes:
# - Composite index on taxonomic fields
# - Index on creation_index
# - Index on created_by
# Add helper method: get_taxonomic_path()
```

#### **UPDATE** `server/dex/models.py`
```python
# Add signals for cache invalidation:
# - post_save: invalidate user and friends' caches
# - post_delete: invalidate user and friends' caches
# Add model field tracker for change detection
```

#### **CREATE** `server/graph/models.py` (optional)
```python
# TreeCacheStatus model for monitoring
# - Track cache status per user/mode
# - Last invalidation time
# - Node/edge counts
```

### 4. Admin Interface

#### **CREATE** `server/graph/admin.py`
```python
# Admin interface for:
# - TreeCacheStatus monitoring
# - Manual cache invalidation
# - Global tree statistics
# - Performance metrics
```

### 5. Migrations

#### **CREATE** `server/animals/migrations/00XX_add_taxonomic_indexes.py`
```python
# Add database indexes for performance
# - Composite indexes on taxonomic fields
# - Single field indexes for common queries
```

#### **CREATE** `server/graph/migrations/0001_initial.py` (if adding models)
```python
# Create TreeCacheStatus model
# Add any tracking tables
```

### 6. Tests

#### **CREATE** `server/graph/tests/test_dynamic_tree_service.py`
```python
# Test cases:
# - Personal mode filtering
# - Friend mode inclusion
# - Selected friends filtering
# - Admin global mode permissions
# - Cache invalidation cascading
# - Performance with 10k+ animals
```

#### **CREATE** `server/graph/tests/test_tree_api.py`
```python
# API endpoint tests:
# - Mode parameter validation
# - Permission checks
# - Chunk loading
# - Search within scope
# - Cache invalidation
```

### 7. Settings & Configuration

#### **UPDATE** `server/biologidex/settings/base.py`
```python
# Add new cache settings:
# - TREE_CACHE_TTL_PERSONAL = 300 (5 minutes)
# - TREE_CACHE_TTL_FRIENDS = 120 (2 minutes)
# - TREE_CACHE_TTL_SELECTED = 60 (1 minute)
# - TREE_CACHE_TTL_GLOBAL = 300 (5 minutes)
# - TREE_MAX_CHUNK_SIZE = 2048
```

## Client Implementation (Godot)

### 8. Core Tree System

#### **UPDATE** `client/biologidex-client/tree_controller.gd`
```gdscript
# Add mode support:
# - enum TreeMode {PERSONAL, FRIENDS, SELECTED, GLOBAL}
# - Mode switching logic
# - Friend selection handling
# - Dynamic API parameter building
```

#### **UPDATE** `client/biologidex-client/api_manager.gd`
```gdscript
# Add new API methods:
# - get_dynamic_tree(mode, friend_ids)
# - get_tree_chunk(x, y, mode)
# - search_tree(query, mode)
# - invalidate_tree_cache()
# - get_friend_list_for_tree()
```

### 9. UI Updates

#### **UPDATE** `client/biologidex-client/tree.tscn`
```gdscript
# Add UI elements:
# - Mode selector (OptionButton)
# - Friend selector (ItemList)
# - Admin toggle (if user is admin)
# - Cache refresh button
```

#### **UPDATE** `client/biologidex-client/tree.gd`
```gdscript
# Handle UI interactions:
# - Mode selection changes
# - Friend selection for SELECTED mode
# - Cache refresh requests
# - Display mode-specific stats
```

## Implementation Order

### Phase 1: Backend Foundation (8-10 hours)
1. ✅ Create `services_dynamic.py` with DynamicTaxonomicTreeService
2. ✅ Create layout algorithm classes
3. ✅ Update models with indexes
4. ✅ Add cache invalidation signals

### Phase 2: API Layer (4-6 hours)
1. ✅ Create new view classes
2. ✅ Update URL patterns
3. ✅ Add permission checks
4. ✅ Test endpoints manually

### Phase 3: Testing (4-6 hours)
1. ✅ Write service unit tests
2. ✅ Write API integration tests
3. ✅ Performance testing with large datasets
4. ✅ Cache invalidation testing

### Phase 4: Client Integration (6-8 hours)
1. ✅ Update tree_controller.gd
2. ✅ Update api_manager.gd
3. ✅ Add UI mode selector
4. ✅ Test all modes

### Phase 5: Optimization (4-6 hours)
1. ✅ Query optimization
2. ✅ Cache warming strategies
3. ✅ Memory profiling
4. ✅ Performance tuning

### Phase 6: Documentation & Deployment (2-3 hours)
1. ✅ API documentation
2. ✅ Migration guide
3. ✅ Deployment scripts
4. ✅ Monitoring setup

## Total Estimated Time: 28-39 hours

## Critical Success Factors

### Performance Requirements
- ✅ Initial load < 2 seconds
- ✅ Chunk load < 100ms
- ✅ 60 FPS with 100k nodes
- ✅ Memory usage < 500MB

### Data Integrity
- ✅ Accurate user scoping
- ✅ Proper friend filtering
- ✅ Cache consistency
- ✅ Permission enforcement

### User Experience
- ✅ Smooth mode switching
- ✅ Clear visual feedback
- ✅ Intuitive friend selection
- ✅ Responsive interactions

## Testing Checklist

### Unit Tests
- [ ] Service initialization with different modes
- [ ] Scope computation for each mode
- [ ] Cache key generation
- [ ] Animal filtering by user scope
- [ ] Hierarchy building
- [ ] Edge generation (parent-child)
- [ ] Cache invalidation cascading

### Integration Tests
- [ ] API endpoint responses
- [ ] Permission checks (admin mode)
- [ ] Friend ID validation
- [ ] Chunk loading boundaries
- [ ] Search within scope
- [ ] Cache hit/miss scenarios

### Performance Tests
- [ ] 10,000 animals across 100 users
- [ ] 100,000 nodes rendering
- [ ] Cache memory usage
- [ ] Query execution time
- [ ] Network payload size

### User Acceptance Tests
- [ ] Personal mode shows only user's animals
- [ ] Friends mode includes all friends
- [ ] Selected mode filters correctly
- [ ] Admin sees all users' data
- [ ] Mode switching preserves state
- [ ] Friend selection UI works

## Rollback Plan

If issues arise during deployment:

1. **Keep legacy endpoints active** during transition
2. **Feature flag** for new tree system
3. **Gradual rollout** to subset of users
4. **Cache clearing** procedure ready
5. **Database backup** before migration
6. **Monitoring alerts** for performance degradation

## Notes

- The `same_family` edge type in the current implementation creates a fully connected graph within families, which isn't a true tree structure. The new implementation uses `parent_child` relationships to create a proper hierarchical tree.

- User-specific caching is critical for performance. Each mode/user combination gets its own cache key to prevent data leakage between users.

- The admin global view will be expensive to compute with many users. Consider implementing pagination or limiting the initial load to a subset of the tree.

- Friend selection for the SELECTED mode should be limited to a reasonable number (e.g., max 10 friends) to prevent performance issues.

- Consider implementing a "tree growth animation" on the client when new animals are discovered, making the dynamic nature of the tree more engaging.