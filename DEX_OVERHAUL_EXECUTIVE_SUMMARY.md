# Dex Overhaul - Executive Summary & Action Items

## Quick Start: Day 1 Critical Fix

**URGENT BUG FIX** (1 minute to implement):
```gdscript
# File: client/biologidex-client/api/services/dex_service.gd:171
# Change: response["results"] → response["entries"]
```
This sync bug prevents the entire feature from working. Fix immediately.

## Current System Analysis

### What's Working Well ✅
- Server has solid foundation (models, sync endpoint, checksums)
- Client has UI and local storage
- Image processing pipeline is robust

### Critical Gaps 🔴
1. **Can't view friends' dex** - Missing API endpoint
2. **No sync tracking** - Downloads everything every time
3. **Single-user storage** - Can't cache friends' data
4. **Sync response bug** - Wrong JSON key expected

## Recommended Architecture Decisions

### Decision 1: Sync Strategy
**Choose: Incremental Timestamp-Based Sync**
- ✅ Track `last_sync` per user/friend
- ✅ Only download changed entries
- ✅ Server remains source of truth
- Alternative considered: Full checksums (too expensive)

### Decision 2: Storage Architecture
**Choose: User-Partitioned Local Storage**
```
user://dex_data/
├── self_dex.json
├── friend1_id_dex.json
└── friend2_id_dex.json
```
- ✅ Clean separation of data
- ✅ Easy permission management
- ✅ Simple migration from v1
- Alternative considered: Single database (privacy concerns)

### Decision 3: Image Caching
**Choose: Shared Cache with Deduplication**
```
user://dex_cache/
├── user_id/
│   └── [hash].png
```
- ✅ Check all users' caches before downloading
- ✅ Use SHA256 hash as filename
- ✅ Saves bandwidth and storage
- Alternative considered: Separate caches (wasteful)

### Decision 4: API Design
**Choose: RESTful with Optional Batch Operations**
- Primary: Individual endpoints per user
- Optimization: Batch sync for multiple users
- ✅ Clear, maintainable
- ✅ Works with existing patterns
- Alternative considered: GraphQL (overkill)

## 5-Phase Implementation Roadmap

### Phase 1: Foundation 🚨 START HERE
- [ ] Fix sync response bug
- [ ] Implement SyncManager singleton 
- [ ] Add to autoload 
- [ ] Test sync with timestamps 
**Deliverable**: Working incremental sync for own dex

### Phase 2: Multi-User Storage 
- [ ] Refactor DexDatabase for multi-user 
- [ ] Implement migration from v1 
- [ ] Add image cache deduplication
- [ ] Update UI for user switching 
**Deliverable**: Can store multiple users' data locally

### Phase 3: Backend API 
- [ ] Add `/dex/user/{id}/entries/` endpoint 
- [ ] Implement permission checks
- [ ] Add friends_overview endpoint 
- [ ] Optional: batch_sync endpoint
**Deliverable**: API supports friend dex viewing

### Phase 4: Frontend Integration 
- [ ] Update DexService for friend sync 
- [ ] Add user selector to UI
- [ ] Implement progress tracking 
- [ ] Add retry logic 
**Deliverable**: Complete friend dex viewing

### Phase 5: Polish
- [ ] Add database indexes 
- [ ] Implement caching
- [ ] Add lazy loading
- [ ] Error handling improvements 
**Deliverable**: Production-ready system

## Risk Assessment

### High Priority Risks
1. **Large collections timeout**
   - Mitigation: Implement pagination early
   - Owner: Backend team

2. **Privacy breach (seeing private entries)**
   - Mitigation: Comprehensive permission tests
   - Owner: QA team

### Medium Priority Risks
1. **Storage costs for images**
   - Mitigation: Monitor usage, implement quotas
   - Owner: DevOps

2. **Sync conflicts**
   - Mitigation: Server as source of truth
   - Owner: Frontend team

## Success Criteria

### MVP Requirements (Must Have)
- ✅ Users can view their own dex
- ✅ Users can view friends' dex (respecting privacy)
- ✅ Incremental sync (not full re-download)
- ✅ Offline access to cached data
- ✅ Progress indication during sync

### Stretch Goals (Nice to Have)
- Batch sync multiple friends
- Background sync
- Sync queue for offline changes
- Data export

## Immediate Action Items
1. **Frontend Lead**: Fix sync bug (5 min)
2. **Frontend**: Start SyncManager implementation
3. **Backend**: Review friend permissions logic
4. **PM**: Schedule daily standup for sync

### Key Decisions Needed
1. **Sync frequency**: Manual only vs auto-sync?
2. **Cache limits**: Max storage per user?
3. **Batch size**: How many entries per sync request?
4. **Offline changes**: Queue for later or read-only?

## Communication Plan

### Stakeholders
- Product Owner: Weekly progress update
- Users: Announce friend dex feature when Phase 4 complete
- Team: Daily standup during implementation

### Documentation
- Update API docs after Phase 3
- Create user guide after Phase 4
- Add to CLAUDE.md throughout

## Future Enhancements (Post-MVP)

### Phase 6: Image Management 
- Multiple images per dex entry
- User can choose primary image
- Image history/versioning

### Phase 7: Collaborative Collections
- Shared dex collections
- Combine entries from multiple users
- Custom sorting/filtering

### Phase 8: Dex Pages 
- Scrapbook-style customization
- Rich text notes
- Layout templates
- Media attachments

## Monitoring & Metrics

### Track from Day 1
- Sync success rate
- Average sync duration
- Entries synced per user
- Storage used per user
- API response times
- Cache hit rates

### Alert Thresholds
- Sync failure rate >5%
- Sync duration >10 seconds
- Storage >100MB per user
- API response >1 second

## Final Recommendations

### Do Immediately ✅
1. Fix sync bug (literally 1 minute)
2. Implement sync tracking
3. Start multi-user storage refactor

### Don't Do Yet ❌
1. Don't optimize prematurely
2. Don't add features beyond MVP
3. Don't skip permission testing

### Technical Debt to Address
1. Add proper error handling
2. Implement retry logic
3. Add telemetry/monitoring
4. Create integration tests

