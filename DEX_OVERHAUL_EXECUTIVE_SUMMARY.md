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

### Phase 1: Foundation (Days 1-2) 🚨 START HERE
**Owner: Frontend Team**
- [ ] Fix sync response bug (1 min)
- [ ] Implement SyncManager singleton (2 hrs)
- [ ] Add to autoload (10 min)
- [ ] Test sync with timestamps (1 hr)
**Deliverable**: Working incremental sync for own dex

### Phase 2: Multi-User Storage (Days 3-5)
**Owner: Frontend Team**
- [ ] Refactor DexDatabase for multi-user (1 day)
- [ ] Implement migration from v1 (2 hrs)
- [ ] Add image cache deduplication (4 hrs)
- [ ] Update UI for user switching (4 hrs)
**Deliverable**: Can store multiple users' data locally

### Phase 3: Backend API (Days 6-8)
**Owner: Backend Team**
- [ ] Add `/dex/user/{id}/entries/` endpoint (4 hrs)
- [ ] Implement permission checks (2 hrs)
- [ ] Add friends_overview endpoint (2 hrs)
- [ ] Optional: batch_sync endpoint (4 hrs)
**Deliverable**: API supports friend dex viewing

### Phase 4: Frontend Integration (Days 9-11)
**Owner: Frontend Team**
- [ ] Update DexService for friend sync (1 day)
- [ ] Add user selector to UI (4 hrs)
- [ ] Implement progress tracking (4 hrs)
- [ ] Add retry logic (4 hrs)
**Deliverable**: Complete friend dex viewing

### Phase 5: Polish (Days 12-14)
**Owner: Both Teams**
- [ ] Add database indexes (Backend - 1 hr)
- [ ] Implement caching (Backend - 4 hrs)
- [ ] Add lazy loading (Frontend - 4 hrs)
- [ ] Error handling improvements (Both - 4 hrs)
**Deliverable**: Production-ready system

## Resource Requirements

### Frontend Team
- 1 senior developer (lead)
- 1 junior developer (support)
- ~8 days of effort

### Backend Team
- 1 backend developer
- ~3 days of effort

### Testing
- 2 days QA after Phase 4
- Focus on sync accuracy and permissions

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

### Today (Day 1)
1. **Frontend Lead**: Fix sync bug (5 min)
2. **Frontend**: Start SyncManager implementation
3. **Backend**: Review friend permissions logic
4. **PM**: Schedule daily standup for sync

### This Week
1. Complete Phase 1-2
2. Backend starts Phase 3 in parallel
3. Document API changes
4. Update CLAUDE.md with progress

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

### Phase 6: Image Management (3 days)
- Multiple images per dex entry
- User can choose primary image
- Image history/versioning

### Phase 7: Collaborative Collections (5 days)
- Shared dex collections
- Combine entries from multiple users
- Custom sorting/filtering

### Phase 8: Dex Pages (7 days)
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

## Questions for Product Owner

1. **Priority**: Is viewing friends' dex more important than performance optimization?
2. **Privacy**: Should users be notified when friends view their dex?
3. **Limits**: Max number of friends to sync?
4. **Offline**: Should the app work fully offline or read-only?
5. **Permissions**: Can users hide specific entries from friends?

---

**Bottom Line**: The dex overhaul is achievable in 10-14 days with the current team. The architecture is sound and scalable. Fix the critical bug today, then follow the phases sequentially. The system will support all planned future features without major refactoring.