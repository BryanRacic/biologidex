# Manual Entry Feature - Implementation Plan

## Overview

This document provides a detailed implementation plan for adding a "Manual Entry" feature to BiologiDex, allowing users to manually search for and select taxonomic records when CV analysis completes or when editing existing dex entries.

## Feature Requirements

### Camera Scene - Post-Analysis Manual Entry
1. After CV analysis completes successfully, replace "Upload for Analysis" button with "Manual Entry" button
2. Manual entry opens a popup window for taxonomic search
3. User can search by genus, species, and common name
4. Search results display in a scrollable, clickable list
5. Selected result updates a label and shows a "Submit" button
6. On submission, dex entry is updated with the selected taxonomic record

### Dex Scene - Edit Button
1. Add an "Edit" button to the dex entry display
2. Opens the same manual entry popup window
3. Pre-populate fields with current animal data
4. Allow user to search for and select a different taxonomic record

## Architecture Design

### Component Structure

```
client/biologidex-client/
├── components/
│   └── manual_entry_popup.gd       # Main popup controller
│   └── manual_entry_popup.tscn     # Popup UI scene
│   └── search_result_item.gd       # Individual search result controller
│   └── search_result_item.tscn     # Search result item UI
├── api/services/
│   └── taxonomy_service.gd         # New service for taxonomy API
└── scenes/
    ├── camera.gd                   # Modified to add manual entry button
    └── dex.gd                      # Modified to add edit button
```

### Data Flow

1. **User triggers manual entry** → Camera or Dex scene
2. **Popup instantiated** → Manual Entry Popup component
3. **User enters search criteria** → Popup sends to TaxonomyService
4. **API search** → TaxonomyService calls `/api/v1/taxonomy/search/`
5. **Results displayed** → Popup shows scrollable list
6. **User selects result** → Updates label and enables Submit
7. **Submission** → Update dex entry via DexService
8. **Cleanup** → Close popup and refresh display

## Implementation Steps

### Phase 1: Server API Enhancement
**Status: Partially Complete - Search endpoint exists, needs update endpoint**

#### 1.1 Add Taxonomy Search to Client API Config
- Add taxonomy endpoints to `api_config.gd`
- Define search, validate, and lookup endpoints

#### 1.2 Add DexEntry Update Endpoint
- Add `PATCH /api/v1/dex/entries/{id}/` support for animal field updates
- Modify `DexEntryUpdateSerializer` to allow `animal` field updates
- Add validation to ensure user owns the entry being updated
- Handle animal replacement logic (check if new animal exists, replace reference)

### Phase 2: Create Taxonomy Service

#### 2.1 Create `taxonomy_service.gd`
```gdscript
extends BaseService
class_name TaxonomyService

signal search_completed(results: Array)
signal search_failed(error: APITypes.APIError)

func search(
    query: String = "",
    genus: String = "",
    species: String = "",
    common_name: String = "",
    limit: int = 20,
    callback: Callable = Callable()
) -> void
```

#### 2.2 Implement Search Method
- Build query parameters from genus, species, common_name
- Call `/api/v1/taxonomy/search/` endpoint
- Handle response with proper error checking
- Emit signals and invoke callback

### Phase 3: Create Manual Entry Popup Component

#### 3.1 Create `manual_entry_popup.tscn`
Structure:
```
PopupPanel (or Window for Godot 4.x)
├── Panel
│   ├── MarginContainer
│   │   └── VBoxContainer
│   │       ├── Header (HBoxContainer)
│   │       │   ├── TitleLabel ("Search Taxonomic Database")
│   │       │   └── CloseButton (X)
│   │       ├── SearchForm (VBoxContainer)
│   │       │   ├── GenusInput (LineEdit)
│   │       │   ├── SpeciesInput (LineEdit)
│   │       │   ├── CommonNameInput (LineEdit)
│   │       │   └── ButtonContainer (HBoxContainer)
│   │       │       ├── SearchButton
│   │       │       └── BackButton
│   │       ├── ResultsContainer (VBoxContainer)
│   │       │   ├── ResultsLabel ("Results:")
│   │       │   └── ScrollContainer
│   │       │       └── ResultsList (VBoxContainer)
│   │       └── SelectionContainer (VBoxContainer)
│   │           ├── SelectedLabel ("Selected: None")
│   │           └── SubmitButton (disabled initially)
```

#### 3.2 Create `manual_entry_popup.gd`
Key features:
- Properties for current entry ID, selected taxonomy
- Search functionality using TaxonomyService
- Dynamic result item instantiation
- Selection handling
- Submit functionality to update dex entry

```gdscript
extends PopupPanel

signal entry_updated(taxonomy_data: Dictionary)
signal popup_closed()

@onready var genus_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/GenusInput
@onready var species_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/SpeciesInput
@onready var common_name_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/CommonNameInput
@onready var results_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ResultsContainer/ScrollContainer/ResultsList
@onready var selected_label: Label = $Panel/MarginContainer/VBoxContainer/SelectionContainer/SelectedLabel
@onready var submit_button: Button = $Panel/MarginContainer/VBoxContainer/SelectionContainer/SubmitButton

var current_dex_entry_id: String = ""
var selected_taxonomy: Dictionary = {}
```

#### 3.3 Create Search Result Item Component
- `search_result_item.tscn` - Visual representation of a taxonomy record
- `search_result_item.gd` - Handle click events, emit selection signal
- Display: scientific name, common name, taxonomic hierarchy

### Phase 4: Integrate Manual Entry into Camera Scene

#### 4.1 Modify `camera.gd`
Add after line 548 (in `_handle_completed_job`):
```gdscript
# Store the current dex entry ID for manual entry
var current_dex_entry_id: String = ""

# Add manual entry button
@onready var manual_entry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ManualEntryButton

func _handle_completed_job(job_data: Dictionary) -> void:
    # ... existing code ...

    # After successful analysis, show manual entry button
    upload_button.visible = false
    manual_entry_button.visible = true
    manual_entry_button.text = "Manual Entry"
    manual_entry_button.disabled = false
```

#### 4.2 Add Manual Entry Button Handler
```gdscript
func _on_manual_entry_pressed() -> void:
    print("[Camera] Opening manual entry popup")

    # Create and configure popup
    var popup_scene = preload("res://components/manual_entry_popup.tscn")
    var popup = popup_scene.instantiate()

    # Set current dex entry if available
    if not current_dex_entry_id.is_empty():
        popup.current_dex_entry_id = current_dex_entry_id

    # Connect signals
    popup.entry_updated.connect(_on_manual_entry_updated)
    popup.popup_closed.connect(_on_manual_entry_closed)

    # Add to scene and show
    add_child(popup)
    popup.popup_centered(Vector2(600, 500))

func _on_manual_entry_updated(taxonomy_data: Dictionary) -> void:
    print("[Camera] Manual entry updated with taxonomy: ", taxonomy_data)
    # Update the displayed record label
    _update_record_display(taxonomy_data)

func _on_manual_entry_closed() -> void:
    print("[Camera] Manual entry popup closed")
```

### Phase 5: Integrate Edit Button into Dex Scene

#### 5.1 Modify `dex.tscn`
Add edit button to the UI:
- Place in header or near navigation buttons
- Consider using an icon button for better UX

#### 5.2 Modify `dex.gd`
```gdscript
@onready var edit_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/EditButton

func _ready() -> void:
    # ... existing code ...
    edit_button.pressed.connect(_on_edit_pressed)

func _on_edit_pressed() -> void:
    if current_index < 0:
        return

    print("[Dex] Opening manual entry for editing record #", current_index)

    # Get current record data
    var record := DexDatabase.get_record_for_user(current_index, current_user_id)
    if record.is_empty():
        return

    # Create popup
    var popup_scene = preload("res://components/manual_entry_popup.tscn")
    var popup = popup_scene.instantiate()

    # Pre-populate with current animal data
    popup.prefill_data = {
        "genus": record.get("genus", ""),
        "species": record.get("species", ""),
        "common_name": record.get("common_name", "")
    }

    # Set the dex entry ID for updating
    popup.current_dex_entry_id = record.get("id", "")

    # Connect signals
    popup.entry_updated.connect(_on_edit_entry_updated)
    popup.popup_closed.connect(_on_edit_popup_closed)

    # Show popup
    add_child(popup)
    popup.popup_centered(Vector2(600, 500))

func _on_edit_entry_updated(taxonomy_data: Dictionary) -> void:
    print("[Dex] Entry updated with new taxonomy")
    # Refresh current display
    _display_record(current_index)
    # Trigger sync to update from server
    trigger_sync()
```

### Phase 6: Update DexService for Entry Updates

#### 6.1 Add update_entry Method
```gdscript
# In dex_service.gd

func update_entry(
    entry_id: String,
    update_data: Dictionary,
    callback: Callable = Callable()
) -> void:
    _log("Updating dex entry: %s" % entry_id)

    var endpoint = config.ENDPOINTS_DEX["entries"] + entry_id + "/"
    var req_config = _create_request_config()
    var context = {"entry_id": entry_id, "callback": callback}

    api_client.patch(
        endpoint,
        update_data,
        _on_update_entry_success.bind(context),
        _on_update_entry_error.bind(context),
        req_config
    )

func _on_update_entry_success(response: Dictionary, context: Dictionary) -> void:
    _log("Dex entry updated successfully: %s" % context.entry_id)
    entry_updated.emit(response)
    if context.callback and context.callback.is_valid():
        context.callback.call(response, 200)

func _on_update_entry_error(error: APITypes.APIError, context: Dictionary) -> void:
    _handle_error(error, "update_entry")
    entry_update_failed.emit(error)
    if context.callback and context.callback.is_valid():
        context.callback.call({"error": error.message}, error.code)
```

## Testing Plan

### Unit Tests
1. TaxonomyService search functionality
2. Manual entry popup data validation
3. DexEntry update API endpoint
4. Animal replacement logic

### Integration Tests
1. Camera scene → Manual Entry → Update flow
2. Dex scene → Edit → Update flow
3. Search with various parameter combinations
4. Error handling for network failures
5. Duplicate animal handling

### User Acceptance Tests
1. Successfully search for animals by genus/species
2. Successfully search for animals by common name
3. Select and submit a different taxonomic record
4. Verify dex entry is updated correctly
5. Verify duplicate animals are handled (existing animal reused)
6. Test with no search results
7. Test with network errors

## Error Handling

### Client Side
1. Network timeout handling with retry logic
2. Empty search results message
3. Invalid input validation (empty fields)
4. API error display to user

### Server Side
1. Validate user owns the dex entry
2. Validate new animal exists in database
3. Handle concurrent update conflicts
4. Proper error messages for client

## Performance Considerations

1. **Search Debouncing**: Add 300ms debounce on search input
2. **Result Pagination**: Limit initial results to 20, add "Load More" if needed
3. **Caching**: Cache recent search results for 5 minutes
4. **Image Optimization**: Only load thumbnails in search results

## Security Considerations

1. **Authorization**: Verify user owns dex entry before allowing updates
2. **Input Sanitization**: Sanitize search inputs to prevent injection
3. **Rate Limiting**: Implement rate limiting on search endpoint
4. **Validation**: Validate taxonomy IDs exist before updating

## UI/UX Guidelines

1. **Responsive Design**: Popup should be responsive and mobile-friendly
2. **Loading States**: Show loading spinner during search
3. **Error Messages**: Clear, actionable error messages
4. **Accessibility**: Keyboard navigation support
5. **Visual Feedback**: Highlight selected item clearly

## Migration Strategy

1. No database migrations required (using existing fields)
2. Feature flag for gradual rollout (optional)
3. Backwards compatibility maintained

## Dependencies

### New Dependencies
- None required, using existing Godot UI components

### Modified Files
- `camera.gd` - Add manual entry button and handler
- `camera.tscn` - Add manual entry button UI element
- `dex.gd` - Add edit button and handler
- `dex.tscn` - Add edit button UI element
- `api_config.gd` - Add taxonomy endpoints
- `api_manager.gd` - Register TaxonomyService
- `server/dex/serializers.py` - Allow animal field updates
- `server/dex/views.py` - Handle animal replacement logic

### New Files
- `components/manual_entry_popup.gd`
- `components/manual_entry_popup.tscn`
- `components/search_result_item.gd`
- `components/search_result_item.tscn`
- `api/services/taxonomy_service.gd`

## Timeline Estimate

### Development Phases
1. **Server API Enhancement** (4 hours)
   - Add update endpoint
   - Modify serializers
   - Test API changes

2. **Taxonomy Service** (2 hours)
   - Create service class
   - Implement search method
   - Add to APIManager

3. **Manual Entry Popup** (6 hours)
   - Create UI scenes
   - Implement search logic
   - Handle selection and submission

4. **Camera Integration** (3 hours)
   - Add manual entry button
   - Connect popup
   - Test workflow

5. **Dex Integration** (3 hours)
   - Add edit button
   - Pre-populate data
   - Test workflow

6. **Testing & Bug Fixes** (4 hours)
   - Unit tests
   - Integration tests
   - Bug fixes

**Total Estimate**: 22 hours

## Future Enhancements

1. **Batch Edit**: Allow editing multiple entries at once
2. **Search History**: Remember recent searches
3. **Advanced Search**: Add filters for kingdom, phylum, class
4. **Confidence Score**: Show CV confidence vs manual selection
5. **Undo/Redo**: Allow reverting manual changes
6. **Offline Mode**: Cache taxonomy database locally
7. **Suggestions**: AI-powered suggestions based on image

## Conclusion

This implementation plan provides a comprehensive approach to adding manual entry functionality to BiologiDex. The feature enhances user control over their dex entries while maintaining data integrity and providing a smooth user experience. The modular design allows for easy testing and future enhancements.