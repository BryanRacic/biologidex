# BiologiDex Client - Implementation Notes

## Architecture Overview

**Tech Stack**: Godot 4.5 (GL Compatibility), GDScript
**Target**: Web (primary), with mobile/desktop support
**Resolution**: 1280×720 base (16:9 aspect, canvas_items stretch)

## Core Systems

### Local Data Storage

**DexDatabase** (`dex_database.gd`):
- Singleton managing discovered animals collection
- Persistence: `user://dex_database.json` (auto-saves on changes)
- Record schema: `creation_index`, `scientific_name`, `common_name`, `cached_image_path`
- Navigation: Maintains sorted indices array for prev/next functionality
- Signals: `record_added`, `database_loaded`

**Image Caching**:
- Location: `user://dex_cache/` (PNG format only)
- Filename: MD5 hash of `dex_compatible_url`
- Populated after CV analysis completes

### Navigation Flow

1. **Login** → Token stored via TokenManager → Home
2. **Home** → Camera/Dex/Tree/Social buttons
3. **Camera** → Upload → CV Analysis → Auto-save to DexDatabase → Home
4. **Dex Gallery** → Browse collection with prev/next navigation

### CV Integration Workflow

1. User selects image (or auto-loads in editor)
2. Upload original format to `/api/v1/vision/jobs/`
3. Poll job status every 2s until complete/failed
4. Download `dex_compatible_url` (server-processed PNG)
5. Cache locally and extract `creation_index` from `animal_details`
6. Save to DexDatabase with all metadata
7. Display bordered image with scientific/common name

### Web Export Considerations

**HTTPRequest Gotcha**:
- Must set `accept_gzip = false` for web builds
- Browsers auto-decompress gzip; Godot would double-decompress
- Error: `stream_peer_gzip.cpp:118` if not disabled

**Single-Threaded Mode**:
- `thread_support=false` in export_presets.cfg
- Better compatibility across all browsers (Safari, iOS)
- No COOP/COEP headers required

## Testing Utilities

**Editor Mode Auto-Cycling**:
- Camera scene detects `OS.has_feature("editor")`
- Cycles through `TEST_IMAGES` array automatically
- Increments index after each successful upload
- 1-second delay between uploads for visibility

## UI Patterns

**RecordImage Component**:
- Dual display: simple preview vs bordered final
- Dynamic aspect ratio calculation from texture
- Sizing: `await get_tree().process_frame` before height calc
- Label overlay with scientific/common name

**Responsive Design**:
- Device classes: mobile (<800px), tablet (800-1280px), desktop (>1280px)
- Dynamic margins via ResponsiveContainer
- AspectRatioContainer for 16:9 maintenance

## Known Issues & Solutions

**GDScript Type Inference**:
- `min()`, `max()`, `Array.pop_back()` return Variant
- Always explicitly type: `var value: float = min(a, b)`

**Container Layout Modes**:
- Container children need `layout_mode = 2`
- AspectRatioContainer must use `layout_mode = 1` (anchors)

**Image Dimensions**:
- Update `current_image_width/height` when changing displayed image
- Required for proper aspect ratio calculations
