# Dex Entry Edit/Delete Feature Implementation Plan

## Executive Summary

This document outlines the implementation of a unified **Dex Entry Edit Scene** that replaces the current popup-based modification flow with a full-screen scene following the established PaperCameraScene UI pattern. The new scene supports:

- Editing animal identification (re-identification via taxonomic search)
- Uploading/replacing the image associated with an entry
- Deleting entries with confirmation
- Manual entry creation (new flow from camera scene)

---

## 1. Current State Audit

### 1.1 Client-Side Modification Points

| Component | Location | Current Function | Status |
|-----------|----------|-----------------|--------|
| **Edit Button** | `scenes/dex/dex.gd:219-233` | Opens popup to re-identify animal | Working |
| **Manual Entry Popup** | `features/ui/components/manual_entry_popup/` | PopupPanel for taxonomic search + animal update | Working (old UI style) |
| **Camera Manual Entry** | `scenes/camera/camera.gd:542-561` | Opens popup for manual animal identification | Working (old UI style) |
| **DexEntryManager.delete_entry()** | `features/dex/dex_entry_manager.gd:252-273` | Infrastructure exists | **NOT WIRED** - calls non-existent API |
| **DexService.delete_entry()** | `features/server_interface/api/services/dex_service.gd` | **MISSING** | Not implemented |

### 1.2 Server-Side Endpoints

| Endpoint | Method | Permission | Status |
|----------|--------|------------|--------|
| `DELETE /dex/entries/{id}/` | DELETE | Owner only | ✅ **Enhanced** - animal ownership transfer + image cleanup |
| `PUT /dex/entries/{id}/` | PUT | Owner only | ✅ **Enhanced** - supports image replacement via source_conversion |
| `PATCH /dex/entries/{id}/` | PATCH | Owner only | ✅ **Enhanced** - supports image replacement via source_conversion |
| `POST /dex/entries/` | POST | Authenticated | ✅ **Enhanced** - supports source_conversion for manual entry |
| `POST /images/convert/` | POST | Authenticated | Working |
| `GET /images/convert/{id}/download/` | GET | Authenticated | Working |

### 1.3 Missing Functionality

**Client:**
1. `DexService.delete_entry()` method not implemented
2. No delete confirmation UI
3. No image replacement workflow
4. Popup UI doesn't match PaperCameraScene style
5. No "Create Manual Entry" button on camera scene (skip analysis)

**Server:** (✅ ALL COMPLETED)
1. ✅ Animal ownership transfer logic when last discoverer deletes entry
2. ✅ Image file cleanup on DexEntry deletion (orphaned files)
3. ✅ Proper 204 No Content response for delete endpoint
4. ✅ Image replacement support via source_conversion field
5. ✅ Manual entry creation support via source_conversion field

---

## 2. Architecture Design

### 2.1 New Scene: `edit_entry.tscn`

Following the web export-safe pattern established in `tree_controller.gd` and `social.gd`:

```
edit_entry (Node2D)
├── PaperCameraScene (instance)
│   └── (background + camera - NO UI children due to GitHub #101975)
└── EditEntryUILayer (CanvasLayer, layer=10)
    └── UIContainer (Control, anchors full rect)
        └── VBoxContainer
            ├── Header
            │   ├── BackButton
            │   └── TitleLabel ("Edit Entry" / "New Entry")
            ├── ScrollContainer
            │   └── ContentVBox
            │       ├── ImageSection
            │       │   ├── DexRecordImage (current image preview)
            │       │   ├── ReplaceImageButton
            │       │   └── RotateImageButton
            │       ├── AnimalSection
            │       │   ├── CurrentAnimalLabel
            │       │   ├── ChangeAnimalButton
            │       │   └── TaxonomySearchPanel (expanded when searching)
            │       │       ├── SearchInputs (genus, species, common_name)
            │       │       ├── SearchResultsList
            │       │       └── SelectButton
            │       └── MetadataSection (optional future)
            │           └── VisibilityDropdown
            ├── ActionButtons
            │   ├── SaveButton (primary)
            │   └── CancelButton
            └── DangerZone (red background panel)
                └── DeleteButton ("Delete Entry")
```

### 2.2 State Machine

```
States:
- IDLE: Viewing entry data, no pending changes
- EDITING_ANIMAL: Taxonomy search panel expanded
- UPLOADING_IMAGE: Image conversion in progress
- SAVING: Submitting changes to server
- CONFIRMING_DELETE: Delete confirmation dialog shown
- ERROR: Error state with retry option
```

### 2.3 Navigation Context

The scene receives context via `NavigationManager`:

```gdscript
# From dex.gd when editing existing entry
NavigationManager.navigate_to("edit_entry", {
    "mode": "edit",  # or "create"
    "dex_entry_id": "uuid-string",
    "creation_index": 123,
    "return_scene": "dex",
    "return_context": {"creation_index": 123}  # for returning to same entry
})

# From camera.gd for manual entry creation
NavigationManager.navigate_to("edit_entry", {
    "mode": "create",
    "image_data": PackedByteArray,  # raw image bytes
    "converted_image": Image,  # if already converted
    "vision_job_id": "uuid" or "",  # if CV was run but rejected
    "return_scene": "camera"
})
```

---

## 3. Server Changes (✅ IMPLEMENTED)

### 3.1 Animal Ownership Transfer on Delete

When a DexEntry is deleted, if the associated Animal's `created_by` matches the deleting user, transfer ownership to the next earliest discoverer.

**File: `server/dex/views.py`** (lines 151-199)

Custom `destroy()` method added to `DexEntryViewSet`:

```python
def destroy(self, request, *args, **kwargs):
    """
    Delete dex entry with animal ownership transfer if needed.

    When the user who originally discovered an animal deletes their dex entry:
    1. Find next earliest dex entry for same animal by another user
    2. Transfer animal.created_by to that user
    3. If no other entries exist, set animal.created_by to NULL

    Returns:
        Response with 204 No Content on success
    """
    instance = self.get_object()
    animal = instance.animal
    user = request.user

    # Check if this user is the animal's original discoverer
    if animal.created_by == user:
        # Find next earliest dex entry for this animal by another user
        next_entry = DexEntry.objects.filter(
            animal=animal
        ).exclude(
            owner=user
        ).order_by('created_at').first()

        if next_entry:
            # Transfer ownership to next discoverer
            animal.created_by = next_entry.owner
            animal.save(update_fields=['created_by'])
            logger.info(
                f"Transferred animal {animal.id} ownership from {user.username} "
                f"to {next_entry.owner.username}"
            )
        else:
            # No other discoverers - clear created_by
            animal.created_by = None
            animal.save(update_fields=['created_by'])
            logger.info(
                f"Animal {animal.id} has no remaining discoverers, "
                f"cleared created_by field"
            )

    # Invalidate cache before deletion
    invalidate_user_dex_cache(str(user.id))

    # Perform the deletion (signals handle tree cache invalidation)
    self.perform_destroy(instance)

    return Response(status=status.HTTP_204_NO_CONTENT)
```

**API Usage:**
```bash
# Delete a dex entry
DELETE /api/v1/dex/entries/{entry_uuid}/

# Response: 204 No Content (empty body)
# Permissions: Owner only (enforced by IsOwnerOrReadOnly)
```

### 3.2 Image Replacement Endpoint Enhancement

The `PUT/PATCH /dex/entries/{id}/` endpoints support optional image replacement via two methods:
1. `source_vision_job` - Replace image from a new CV analysis job
2. `source_conversion` - Replace image from an ImageConversion (manual upload)

**File: `server/dex/serializers.py`** (lines 124-245)

Updated `DexEntryUpdateSerializer`:

```python
class DexEntryUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for updating dex entries.

    Supports:
    - Changing the animal (re-identification)
    - Updating notes, visibility, customizations
    - Replacing the image via source_conversion (from ImageConversion)
    - Replacing the image via source_vision_job (from new CV analysis)
    """
    # Optional image replacement fields (write-only)
    source_vision_job = serializers.UUIDField(
        required=False,
        allow_null=True,
        write_only=True,
        help_text="UUID of AnalysisJob to use for image replacement"
    )
    source_conversion = serializers.UUIDField(
        required=False,
        allow_null=True,
        write_only=True,
        help_text="UUID of ImageConversion to use for image replacement"
    )

    class Meta:
        model = DexEntry
        fields = [
            'animal',
            'notes',
            'customizations',
            'visibility',
            'is_favorite',
            'location_name',
            'source_vision_job',
            'source_conversion',
        ]
```

**Validation:**
- `source_vision_job`: Must exist, belong to current user, and have an associated image
- `source_conversion`: Must exist, belong to current user, and not be expired

**API Usage:**
```bash
# Update entry with new animal identification
PATCH /api/v1/dex/entries/{entry_uuid}/
Content-Type: application/json
{
    "animal": "new-animal-uuid"
}

# Update entry with new image from ImageConversion
PATCH /api/v1/dex/entries/{entry_uuid}/
Content-Type: application/json
{
    "source_conversion": "conversion-uuid"
}

# Update entry with new image from vision job
PATCH /api/v1/dex/entries/{entry_uuid}/
Content-Type: application/json
{
    "source_vision_job": "vision-job-uuid"
}

# Combine animal change with image replacement
PATCH /api/v1/dex/entries/{entry_uuid}/
Content-Type: application/json
{
    "animal": "new-animal-uuid",
    "source_conversion": "conversion-uuid"
}
```

### 3.3 Manual Entry Creation Support

The `POST /dex/entries/` endpoint now supports three image source modes:

**File: `server/dex/serializers.py`** (lines 59-177)

```python
class DexEntryCreateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating dex entries.

    Supports three image source modes:
    1. source_vision_job - From CV analysis (standard flow)
    2. source_conversion - From ImageConversion (manual entry without CV)
    3. original_image - Direct file upload (legacy/fallback)

    At least one of these must be provided.
    """
    source_vision_job = serializers.UUIDField(required=False, allow_null=True)
    source_conversion = serializers.UUIDField(
        required=False,
        allow_null=True,
        help_text="UUID of ImageConversion for manual entry creation"
    )
    original_image = serializers.ImageField(required=False, allow_null=True)
```

**API Usage:**
```bash
# Create entry from CV analysis (standard flow)
POST /api/v1/dex/entries/
Content-Type: application/json
{
    "animal": "animal-uuid",
    "source_vision_job": "vision-job-uuid",
    "visibility": "friends"
}

# Create entry manually without CV (using ImageConversion)
POST /api/v1/dex/entries/
Content-Type: application/json
{
    "animal": "animal-uuid",
    "source_conversion": "conversion-uuid",
    "visibility": "friends"
}

# Response (201 Created):
{
    "id": "new-entry-uuid"
}
```

### 3.4 Image File Cleanup Signal

**File: `server/dex/signals.py`** (lines 16-64)

Automatic cleanup of orphaned image files when DexEntry is deleted:

```python
@receiver(pre_delete, sender=DexEntry)
def cleanup_dex_entry_images(sender, instance, **kwargs):
    """
    Delete image files when DexEntry is deleted.
    Only deletes if no other entries reference the same file.

    Handles:
    - original_image: Direct upload field on DexEntry
    - processed_image: Processed version field on DexEntry

    Note: Images stored in source_vision_job are NOT deleted here since they
    may be referenced by other entries or needed for audit purposes.
    """
```

**Behavior:**
- Checks if other DexEntry records reference the same image file path
- Only deletes orphaned files (no other references)
- Logs successful deletions and warnings for failures
- Does NOT delete images stored in AnalysisJob (source_vision_job) to preserve audit trail

---

## 4. Client Changes

### 4.1 DexService - Add delete_entry Method

**File: `features/server_interface/api/services/dex_service.gd`**

Add after `update_entry()` method (around line 191):

```gdscript
## Entry deletion signals
signal entry_deleted(entry_id: String)
signal entry_deletion_failed(error: APITypes.APIError)

## Delete a dex entry
func delete_entry(
    entry_id: String,
    callback: Callable = Callable()
) -> void:
    _log("Deleting dex entry: %s" % entry_id)

    var endpoint = config.ENDPOINTS_DEX["entries"] + entry_id + "/"
    var req_config = _create_request_config()
    var context = {"entry_id": entry_id, "callback": callback}

    api_client.delete(
        endpoint,
        _on_delete_entry_success.bind(context),
        _on_delete_entry_error.bind(context),
        req_config
    )

func _on_delete_entry_success(response: Dictionary, context: Dictionary) -> void:
    _log("Dex entry deleted successfully: %s" % context.entry_id)
    entry_deleted.emit(context.entry_id)
    if context.callback and context.callback.is_valid():
        # DELETE returns 204 No Content
        context.callback.call({}, 204)

func _on_delete_entry_error(error: APITypes.APIError, context: Dictionary) -> void:
    _handle_error(error, "delete_entry")
    entry_deletion_failed.emit(error)
    if context.callback and context.callback.is_valid():
        context.callback.call({"error": error.message}, error.code)
```

### 4.2 API Config - Add delete endpoint format

**File: `features/server_interface/api/core/api_config.gd`**

Update `ENDPOINTS_DEX`:

```gdscript
const ENDPOINTS_DEX = {
    "entries": "/dex/entries/",
    "entry_detail": "/dex/entries/%s/",  # NEW - for GET/PUT/DELETE with ID
    "my_entries": "/dex/entries/my_entries/",
    "favorites": "/dex/entries/favorites/",
    "toggle_favorite": "/dex/entries/%s/toggle_favorite/",
    "sync": "/dex/entries/sync_entries/",
}
```

### 4.3 New Scene: edit_entry.gd

**File: `scenes/edit_entry/edit_entry.gd`**

```gdscript
extends BaseSceneNode
## EditEntry - Full-screen scene for editing/creating dex entries
##
## Modes:
## - "edit": Modify existing entry (animal ID, image, delete)
## - "create": Manual entry creation without CV analysis

const DexRecordImage = preload("res://features/ui/components/dex_record_image/dex_record_image.gd")
const FileSelector = preload("res://features/ui/components/file_selector/file_selector.gd")

# ============================================================================
# State
# ============================================================================

enum State { IDLE, EDITING_ANIMAL, UPLOADING_IMAGE, SAVING, CONFIRMING_DELETE, ERROR }

var current_state: State = State.IDLE
var mode: String = "edit"  # "edit" or "create"

# Entry data
var dex_entry_id: String = ""
var creation_index: int = -1
var current_animal_id: String = ""
var current_animal_data: Dictionary = {}
var original_entry_data: Dictionary = {}

# Pending changes
var pending_animal_id: String = ""
var pending_animal_data: Dictionary = {}
var pending_image_conversion_id: String = ""
var pending_image_texture: Texture2D = null
var has_unsaved_changes: bool = false

# Navigation
var return_scene: String = "dex"
var return_context: Dictionary = {}

# ============================================================================
# UI References (initialized via explicit paths for web export)
# ============================================================================

var _paper_camera: PaperCameraScene = null

# UI Layer nodes
var back_button: Button = null
var title_label: Label = null
var record_image: DexRecordImage = null
var replace_image_button: Button = null
var rotate_image_button: Button = null
var current_animal_label: Label = null
var change_animal_button: Button = null
var taxonomy_search_panel: Control = null
var search_inputs_container: Control = null
var genus_input: LineEdit = null
var species_input: LineEdit = null
var common_name_input: LineEdit = null
var search_button: Button = null
var search_results_list: VBoxContainer = null
var search_results_scroll: ScrollContainer = null
var select_animal_button: Button = null
var save_button: Button = null
var cancel_button: Button = null
var delete_button: Button = null
var delete_confirmation_panel: Control = null
var confirm_delete_button: Button = null
var cancel_delete_button: Button = null

# Components
var file_selector: FileSelector = null
var cv_workflow: CVAnalysisWorkflow = null

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
    scene_name = "EditEntry"
    print("[EditEntry] Scene ready")

    # Initialize PaperCameraScene (created programmatically for web safety)
    _paper_camera = $PaperCameraScene

    # Initialize UI nodes using explicit paths (web export workaround)
    _init_ui_references()

    # Connect UI signals
    _connect_ui_signals()

    # Create file selector component
    file_selector = FileSelector.new()
    add_child(file_selector)
    file_selector.file_selected.connect(_on_file_selected)
    file_selector.file_load_error.connect(_on_file_load_error)

    # Handle navigation context
    _handle_navigation_context()

    # Load entry data if editing
    if mode == "edit" and not dex_entry_id.is_empty():
        _load_entry_data()
    elif mode == "create":
        _setup_create_mode()


func _init_ui_references() -> void:
    """Initialize UI node references using explicit paths (web export safe)"""
    var ui_container = $EditEntryUILayer/UIContainer/ContentVBox

    # Header
    back_button = $EditEntryUILayer/UIContainer/Header/BackButton
    title_label = $EditEntryUILayer/UIContainer/Header/TitleLabel

    # Image section
    record_image = ui_container.get_node("ImageSection/RecordImage")
    replace_image_button = ui_container.get_node("ImageSection/ButtonsHBox/ReplaceImageButton")
    rotate_image_button = ui_container.get_node("ImageSection/ButtonsHBox/RotateImageButton")

    # Animal section
    current_animal_label = ui_container.get_node("AnimalSection/CurrentAnimalLabel")
    change_animal_button = ui_container.get_node("AnimalSection/ChangeAnimalButton")
    taxonomy_search_panel = ui_container.get_node("AnimalSection/TaxonomySearchPanel")
    genus_input = taxonomy_search_panel.get_node("SearchInputs/GenusInput")
    species_input = taxonomy_search_panel.get_node("SearchInputs/SpeciesInput")
    common_name_input = taxonomy_search_panel.get_node("SearchInputs/CommonNameInput")
    search_button = taxonomy_search_panel.get_node("SearchInputs/SearchButton")
    search_results_scroll = taxonomy_search_panel.get_node("SearchResultsScroll")
    search_results_list = search_results_scroll.get_node("SearchResultsList")
    select_animal_button = taxonomy_search_panel.get_node("SelectAnimalButton")

    # Action buttons
    save_button = $EditEntryUILayer/UIContainer/ActionButtons/SaveButton
    cancel_button = $EditEntryUILayer/UIContainer/ActionButtons/CancelButton

    # Danger zone
    delete_button = $EditEntryUILayer/UIContainer/DangerZone/DeleteButton
    delete_confirmation_panel = $EditEntryUILayer/UIContainer/DangerZone/DeleteConfirmationPanel
    confirm_delete_button = delete_confirmation_panel.get_node("ConfirmDeleteButton")
    cancel_delete_button = delete_confirmation_panel.get_node("CancelDeleteButton")


func _connect_ui_signals() -> void:
    """Connect all UI button signals"""
    back_button.pressed.connect(_on_back_pressed)
    replace_image_button.pressed.connect(_on_replace_image_pressed)
    rotate_image_button.pressed.connect(_on_rotate_image_pressed)
    change_animal_button.pressed.connect(_on_change_animal_pressed)
    search_button.pressed.connect(_on_search_pressed)
    select_animal_button.pressed.connect(_on_select_animal_pressed)
    save_button.pressed.connect(_on_save_pressed)
    cancel_button.pressed.connect(_on_cancel_pressed)
    delete_button.pressed.connect(_on_delete_pressed)
    confirm_delete_button.pressed.connect(_on_confirm_delete_pressed)
    cancel_delete_button.pressed.connect(_on_cancel_delete_pressed)

    # Search input enter key
    genus_input.text_submitted.connect(_on_search_input_submitted)
    species_input.text_submitted.connect(_on_search_input_submitted)
    common_name_input.text_submitted.connect(_on_search_input_submitted)


func _handle_navigation_context() -> void:
    """Extract navigation context from NavigationManager"""
    if not NavigationManager.has_context():
        return

    var context: Dictionary = NavigationManager.get_context()

    mode = context.get("mode", "edit")
    dex_entry_id = context.get("dex_entry_id", "")
    creation_index = context.get("creation_index", -1)
    return_scene = context.get("return_scene", "dex")
    return_context = context.get("return_context", {})

    # For create mode with pre-loaded image
    if mode == "create":
        var image_data: PackedByteArray = context.get("image_data", PackedByteArray())
        var converted_image: Image = context.get("converted_image", null)
        if converted_image:
            pending_image_texture = ImageTexture.create_from_image(converted_image)

    NavigationManager.clear_context()


# ============================================================================
# Mode Setup
# ============================================================================

func _load_entry_data() -> void:
    """Load existing entry data from local database and server"""
    title_label.text = "Edit Entry"
    delete_button.visible = true

    # First try local database
    var local_record: Dictionary = DexDatabase.get_record_for_user(creation_index, "self")
    if not local_record.is_empty():
        _populate_from_record(local_record)
        return

    # Fall back to server fetch
    show_loading("Loading entry...")
    APIManager.dex.get_my_entries(_on_entries_loaded)


func _on_entries_loaded(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200:
        show_error("Load failed", "Could not load entry data")
        return

    for entry in response.get("results", []):
        if str(entry.get("id", "")) == dex_entry_id:
            _populate_from_server_entry(entry)
            return

    show_error("Entry not found", "The entry could not be found")


func _populate_from_record(record: Dictionary) -> void:
    """Populate UI from local DexDatabase record"""
    current_animal_id = record.get("animal_id", "")
    current_animal_data = {
        "scientific_name": record.get("scientific_name", ""),
        "common_name": record.get("common_name", ""),
        "genus": record.get("genus", ""),
        "species": record.get("species", "")
    }
    original_entry_data = record.duplicate()

    # Update UI
    _update_animal_display()
    record_image.set_entry_data(record, "self")
    record_image.load_image_from_entry()
    record_image.show_bordered()


func _populate_from_server_entry(entry: Dictionary) -> void:
    """Populate UI from server entry data"""
    current_animal_id = str(entry.get("animal", ""))
    var animal_details = entry.get("animal_details", {})
    current_animal_data = {
        "scientific_name": animal_details.get("scientific_name", ""),
        "common_name": animal_details.get("common_name", ""),
        "genus": animal_details.get("genus", ""),
        "species": animal_details.get("species", "")
    }
    original_entry_data = entry.duplicate()

    _update_animal_display()
    # Load image from URL
    var image_url = entry.get("display_image_url", "")
    if not image_url.is_empty():
        record_image.load_image_from_url(image_url)
    record_image.show_bordered()


func _setup_create_mode() -> void:
    """Setup UI for manual entry creation"""
    title_label.text = "New Entry"
    delete_button.visible = false
    save_button.text = "Create Entry"

    # Show taxonomy search immediately
    taxonomy_search_panel.visible = true
    change_animal_button.visible = false
    current_animal_label.text = "Select an animal below"

    # Show pending image if provided
    if pending_image_texture:
        record_image.set_simple_texture(pending_image_texture)
        record_image.show_simple()
        record_image.visible = true


# ============================================================================
# Animal Editing
# ============================================================================

func _update_animal_display() -> void:
    """Update the current animal label"""
    var display_animal = pending_animal_data if not pending_animal_data.is_empty() else current_animal_data
    var sci_name = display_animal.get("scientific_name", "Unknown")
    var common = display_animal.get("common_name", "")

    if common.is_empty():
        current_animal_label.text = sci_name
    else:
        current_animal_label.text = "%s (%s)" % [sci_name, common]

    # Show indicator if changed
    if not pending_animal_id.is_empty() and pending_animal_id != current_animal_id:
        current_animal_label.text += " [Changed]"
        has_unsaved_changes = true


func _on_change_animal_pressed() -> void:
    """Show taxonomy search panel"""
    _set_state(State.EDITING_ANIMAL)
    taxonomy_search_panel.visible = true
    change_animal_button.visible = false

    # Pre-fill with current data
    genus_input.text = current_animal_data.get("genus", "")
    species_input.text = current_animal_data.get("species", "")
    common_name_input.text = current_animal_data.get("common_name", "")


func _on_search_input_submitted(_text: String) -> void:
    _on_search_pressed()


func _on_search_pressed() -> void:
    """Perform taxonomy search"""
    var genus = genus_input.text.strip_edges()
    var species = species_input.text.strip_edges()
    var common = common_name_input.text.strip_edges()

    if genus.is_empty() and species.is_empty() and common.is_empty():
        show_error("Search Error", "Enter at least one search term")
        return

    show_loading("Searching...")
    _clear_search_results()

    APIManager.taxonomy.search("", genus, species, common, "", "", 20, _on_search_completed)


func _on_search_completed(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200:
        show_error("Search Failed", response.get("error", "Unknown error"))
        return

    var results = response.get("results", [])
    if results.is_empty():
        show_error("No Results", "No matching species found. Try different terms.")
        return

    _display_search_results(results)


func _display_search_results(results: Array) -> void:
    """Display taxonomy search results"""
    _clear_search_results()
    search_results_scroll.visible = true

    var item_scene = preload("res://scenes/social/components/search_result_item.tscn")

    for result in results:
        var item = item_scene.instantiate()
        search_results_list.add_child(item)
        item.set_taxonomy_data(result)
        item.result_selected.connect(_on_search_result_selected)


func _clear_search_results() -> void:
    for child in search_results_list.get_children():
        child.queue_free()
    search_results_scroll.visible = false


func _on_search_result_selected(taxonomy_data: Dictionary) -> void:
    """Handle selection of a taxonomy search result"""
    # Highlight selected
    for child in search_results_list.get_children():
        child.set_selected(child.taxonomy_data == taxonomy_data)

    pending_animal_data = taxonomy_data
    select_animal_button.disabled = false


func _on_select_animal_pressed() -> void:
    """Confirm animal selection and lookup/create Animal record"""
    if pending_animal_data.is_empty():
        return

    show_loading("Looking up animal...")

    var scientific_name = pending_animal_data.get("scientific_name", "")
    var common_names = pending_animal_data.get("common_names", [])
    var common_name = ""

    if common_names is Array and common_names.size() > 0:
        var first = common_names[0]
        if typeof(first) == TYPE_DICTIONARY:
            common_name = first.get("name", "")
        else:
            common_name = str(first)

    var additional = {
        "kingdom": pending_animal_data.get("kingdom", ""),
        "phylum": pending_animal_data.get("phylum", ""),
        "class_name": pending_animal_data.get("class_name", ""),
        "order": pending_animal_data.get("order", ""),
        "family": pending_animal_data.get("family", ""),
        "genus": pending_animal_data.get("genus", ""),
        "species": pending_animal_data.get("specific_epithet", "")
    }

    APIManager.animals.lookup_or_create(scientific_name, common_name, additional, _on_animal_lookup_completed)


func _on_animal_lookup_completed(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200:
        show_error("Error", response.get("error", "Failed to find/create animal"))
        return

    var animal = response.get("animal", {})
    pending_animal_id = str(animal.get("id", ""))
    pending_animal_data["id"] = pending_animal_id
    pending_animal_data["scientific_name"] = animal.get("scientific_name", "")
    pending_animal_data["common_name"] = animal.get("common_name", "")

    # Collapse search panel
    taxonomy_search_panel.visible = false
    change_animal_button.visible = true

    _update_animal_display()
    _set_state(State.IDLE)


# ============================================================================
# Image Editing
# ============================================================================

func _on_replace_image_pressed() -> void:
    """Open file picker to select new image"""
    file_selector.open_file_picker()


func _on_file_selected(file_name: String, file_type: String, file_data: PackedByteArray) -> void:
    """Handle new image selection"""
    print("[EditEntry] New image selected: %s (%d bytes)" % [file_name, file_data.size()])

    # Upload for conversion
    _set_state(State.UPLOADING_IMAGE)
    show_loading("Converting image...")

    APIManager.images.convert(file_data, file_type, _on_image_converted)


func _on_image_converted(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200 and code != 201:
        show_error("Upload Failed", response.get("error", "Image conversion failed"))
        _set_state(State.IDLE)
        return

    pending_image_conversion_id = str(response.get("id", ""))
    var download_url = response.get("converted_image_url", "")

    if download_url.is_empty():
        # Build URL from ID
        download_url = APIConfig.BASE_URL + "/images/convert/%s/download/" % pending_image_conversion_id

    # Download converted image for preview
    APIManager.images.download(pending_image_conversion_id, _on_converted_image_downloaded)


func _on_converted_image_downloaded(response: Dictionary, code: int) -> void:
    if code != 200:
        show_error("Download Failed", "Could not download converted image")
        _set_state(State.IDLE)
        return

    var image_data: PackedByteArray = response.get("data", PackedByteArray())
    if image_data.is_empty():
        _set_state(State.IDLE)
        return

    var image = Image.new()
    if image.load_png_from_buffer(image_data) == OK:
        pending_image_texture = ImageTexture.create_from_image(image)
        record_image.set_simple_texture(pending_image_texture)
        record_image.show_simple()
        has_unsaved_changes = true

    _set_state(State.IDLE)


func _on_file_load_error(error: String) -> void:
    show_error("File Error", error)


func _on_rotate_image_pressed() -> void:
    """Rotate the current image 90 degrees clockwise"""
    if pending_image_texture == null:
        # Get current texture from record_image
        pending_image_texture = record_image.get_simple_texture()

    if pending_image_texture:
        var image = pending_image_texture.get_image()
        image.rotate_90(CLOCKWISE)
        pending_image_texture = ImageTexture.create_from_image(image)
        record_image.set_simple_texture(pending_image_texture)
        record_image.show_simple()
        has_unsaved_changes = true


# ============================================================================
# Save/Cancel/Delete
# ============================================================================

func _on_save_pressed() -> void:
    """Save all pending changes"""
    if mode == "create":
        _create_new_entry()
    else:
        _update_existing_entry()


func _create_new_entry() -> void:
    """Create a new dex entry (manual entry mode)"""
    if pending_animal_id.is_empty():
        show_error("No Animal", "Please select an animal first")
        return

    _set_state(State.SAVING)
    show_loading("Creating entry...")

    var data = {
        "animal": pending_animal_id,
        "visibility": "friends"
    }

    # Add image source if we have one
    if not pending_image_conversion_id.is_empty():
        data["source_conversion"] = pending_image_conversion_id

    APIManager.dex.create_entry(
        pending_animal_id,
        "",  # No vision job
        "",  # No notes
        "friends",
        _on_entry_created
    )


func _on_entry_created(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200 and code != 201:
        show_error("Create Failed", response.get("error", "Could not create entry"))
        _set_state(State.IDLE)
        return

    print("[EditEntry] Entry created successfully")

    # Trigger sync and navigate back
    APIManager.dex.sync_user_dex("self")
    _navigate_back()


func _update_existing_entry() -> void:
    """Update the existing dex entry"""
    if not has_unsaved_changes:
        _navigate_back()
        return

    _set_state(State.SAVING)
    show_loading("Saving changes...")

    var update_data: Dictionary = {}

    # Include animal change if different
    if not pending_animal_id.is_empty() and pending_animal_id != current_animal_id:
        update_data["animal"] = pending_animal_id

    # Include image change if we have a new conversion
    if not pending_image_conversion_id.is_empty():
        update_data["source_conversion"] = pending_image_conversion_id

    if update_data.is_empty():
        hide_loading()
        _navigate_back()
        return

    APIManager.dex.update_entry(dex_entry_id, update_data, _on_entry_update_completed)


func _on_entry_update_completed(response: Dictionary, code: int) -> void:
    hide_loading()

    if code != 200:
        show_error("Save Failed", response.get("error", "Could not save changes"))
        _set_state(State.IDLE)
        return

    print("[EditEntry] Entry updated successfully")

    # Store the dex_entry_id so we can navigate back to it
    return_context["dex_entry_id"] = dex_entry_id

    # Trigger sync to update local database
    APIManager.dex.sync_user_dex("self")

    _navigate_back()


func _on_cancel_pressed() -> void:
    """Cancel changes and go back"""
    if has_unsaved_changes:
        # TODO: Show "discard changes?" confirmation
        pass
    _navigate_back()


func _on_back_pressed() -> void:
    """Handle back button (same as cancel)"""
    _on_cancel_pressed()


# ============================================================================
# Delete Functionality
# ============================================================================

func _on_delete_pressed() -> void:
    """Show delete confirmation"""
    _set_state(State.CONFIRMING_DELETE)
    delete_confirmation_panel.visible = true
    delete_button.visible = false


func _on_cancel_delete_pressed() -> void:
    """Cancel deletion"""
    _set_state(State.IDLE)
    delete_confirmation_panel.visible = false
    delete_button.visible = true


func _on_confirm_delete_pressed() -> void:
    """Execute deletion"""
    show_loading("Deleting entry...")

    APIManager.dex.delete_entry(dex_entry_id, _on_delete_completed)


func _on_delete_completed(response: Dictionary, code: int) -> void:
    hide_loading()

    # 204 No Content is success for DELETE
    if code != 204 and code != 200:
        show_error("Delete Failed", response.get("error", "Could not delete entry"))
        _set_state(State.IDLE)
        delete_confirmation_panel.visible = false
        delete_button.visible = true
        return

    print("[EditEntry] Entry deleted successfully")

    # Remove from local database
    if creation_index >= 0:
        DexDatabase.remove_record(creation_index, "self")

    # Clear return context so we don't try to navigate to deleted entry
    return_context = {}

    _navigate_back()


# ============================================================================
# Navigation
# ============================================================================

func _navigate_back() -> void:
    """Navigate back to the return scene with appropriate context"""
    var context: Dictionary = {}

    # For edit mode, try to return to the same entry (if it still exists)
    if mode == "edit" and not return_context.is_empty():
        context = return_context

    NavigationManager.navigate_to(return_scene, context)


# ============================================================================
# State Management
# ============================================================================

func _set_state(new_state: State) -> void:
    current_state = new_state

    # Update UI based on state
    match new_state:
        State.IDLE:
            save_button.disabled = false
            cancel_button.disabled = false
        State.EDITING_ANIMAL:
            save_button.disabled = true
        State.UPLOADING_IMAGE, State.SAVING:
            save_button.disabled = true
            cancel_button.disabled = true
        State.CONFIRMING_DELETE:
            save_button.disabled = true
            cancel_button.disabled = true
        State.ERROR:
            save_button.disabled = false
            cancel_button.disabled = false
```

### 4.4 Scene File: edit_entry.tscn

**File: `scenes/edit_entry/edit_entry.tscn`**

Create new scene following PaperCameraScene sibling UI pattern:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scenes/edit_entry/edit_entry.gd" id="1"]
[ext_resource type="PackedScene" path="res://features/camera_system/paper_camera_scene.tscn" id="2"]
[ext_resource type="PackedScene" path="res://features/ui/components/dex_record_image/dex_record_image.tscn" id="3"]

[node name="EditEntry" type="Node2D"]
script = ExtResource("1")

[node name="PaperCameraScene" parent="." instance=ExtResource("2")]
zoom_enabled = false
scroll_limits_enabled = false

[node name="EditEntryUILayer" type="CanvasLayer" parent="."]
layer = 10

[node name="UIContainer" type="Control" parent="EditEntryUILayer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

# ... (full scene structure with all UI elements)
```

### 4.5 Camera Scene - Add Manual Entry Button

**File: `scenes/camera/camera.gd`**

Add "Create Without Analysis" button to skip CV and go directly to edit_entry in create mode:

```gdscript
# Add to UI Elements section
@onready var skip_analysis_button: Button = get_node("%SkipAnalysisButton")

# Add to _on_scene_ready()
skip_analysis_button.pressed.connect(_on_skip_analysis_pressed)

# Add new function
func _on_skip_analysis_pressed() -> void:
    """Skip CV analysis and create entry manually"""
    if selected_file_data.is_empty():
        show_error("No Image", "Please select an image first")
        return

    # Navigate to edit_entry in create mode with the image
    NavigationManager.navigate_to("edit_entry", {
        "mode": "create",
        "image_data": selected_file_data,
        "converted_image": converted_image,
        "return_scene": "camera"
    })
```

### 4.6 Dex Scene - Update Edit Flow

**File: `scenes/dex/dex.gd`**

Update `_on_edit_pressed()` to navigate to new scene instead of popup:

```gdscript
func _on_edit_pressed() -> void:
    if current_index < 0:
        show_error("No record selected", "Please select a dex entry to edit")
        return

    if current_user_id != "self":
        show_error("Cannot edit", "You can only edit your own dex entries")
        return

    var record: Dictionary = DexDatabase.get_record_for_user(current_index, current_user_id)
    if record.is_empty():
        show_error("Record not found", "Could not find record")
        return

    # Navigate to edit_entry scene
    NavigationManager.navigate_to("edit_entry", {
        "mode": "edit",
        "dex_entry_id": record.get("dex_entry_id", ""),
        "creation_index": current_index,
        "return_scene": "dex",
        "return_context": {
            "creation_index": current_index,
            "user_id": "self"
        }
    })
```

---

## 5. Permission Model

### 5.1 Client-Side Checks

| Action | Check | Location |
|--------|-------|----------|
| Edit button visibility | `current_user_id == "self"` | dex.gd |
| Delete button visibility | `mode == "edit"` | edit_entry.gd |
| Save enabled | Valid animal + (mode == "create" OR has_unsaved_changes) | edit_entry.gd |

### 5.2 Server-Side Enforcement

| Action | Permission Class | Check |
|--------|------------------|-------|
| `PUT /dex/entries/{id}/` | `IsOwnerOrReadOnly` | `obj.owner == request.user` |
| `DELETE /dex/entries/{id}/` | `IsOwnerOrReadOnly` | `obj.owner == request.user` |
| `POST /dex/entries/` | `IsAuthenticated` | Auto-sets owner to request.user |

**Important**: Even superusers cannot modify other users' entries via the API. Admin panel only.

---

## 6. UX Flow Diagrams

### 6.1 Edit Existing Entry

```
┌─────────────────┐
│   Dex Scene     │
│ [Edit Button]   │
└────────┬────────┘
         │ NavigationManager.navigate_to("edit_entry", {...})
         ▼
┌─────────────────────────────────────────────────┐
│              Edit Entry Scene                   │
│  ┌─────────────────────────────────────────┐   │
│  │ [Back]           Edit Entry             │   │
│  ├─────────────────────────────────────────┤   │
│  │  ┌────────────────────┐                 │   │
│  │  │   [Image Preview]  │  [Replace]      │   │
│  │  │                    │  [Rotate]       │   │
│  │  └────────────────────┘                 │   │
│  │                                         │   │
│  │  Current: Canis lupus (Gray Wolf)       │   │
│  │  [Change Animal]                        │   │
│  │                                         │   │
│  │  ┌────────────────────┐ (when expanded) │   │
│  │  │ Genus:  [________] │                 │   │
│  │  │ Species:[________] │                 │   │
│  │  │ Common: [________] │                 │   │
│  │  │        [Search]    │                 │   │
│  │  │ ┌────────────────┐ │                 │   │
│  │  │ │ • Result 1     │ │                 │   │
│  │  │ │ • Result 2 [x] │ │                 │   │
│  │  │ │ • Result 3     │ │                 │   │
│  │  │ └────────────────┘ │                 │   │
│  │  │   [Select Animal]  │                 │   │
│  │  └────────────────────┘                 │   │
│  │                                         │   │
│  │  [Save Changes]  [Cancel]               │   │
│  │                                         │   │
│  │  ─────── Danger Zone ───────            │   │
│  │  [Delete Entry]                         │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 6.2 Delete Confirmation

```
┌─────────────────────────────────────────────────┐
│              Delete Confirmation                │
│  ┌─────────────────────────────────────────┐   │
│  │  ⚠️ Delete "Canis lupus"?               │   │
│  │                                         │   │
│  │  This action cannot be undone.          │   │
│  │  The image and all data will be         │   │
│  │  permanently removed.                   │   │
│  │                                         │   │
│  │  [Cancel]        [Delete Forever]       │   │
│  │                  (red button)           │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 6.3 Manual Entry Creation (from Camera)

```
┌─────────────────┐
│  Camera Scene   │
│ [Select Photo]  │
│                 │
│ (photo preview) │
│                 │
│ [Upload & CV]   │
│ [Manual Entry]  │  ← NEW BUTTON
└────────┬────────┘
         │ NavigationManager.navigate_to("edit_entry", {mode: "create", ...})
         ▼
┌─────────────────────────────────────────────────┐
│              Edit Entry Scene                   │
│  ┌─────────────────────────────────────────┐   │
│  │ [Back]           New Entry              │   │
│  ├─────────────────────────────────────────┤   │
│  │  ┌────────────────────┐                 │   │
│  │  │   [Image Preview]  │  [Replace]      │   │
│  │  │   (pre-loaded)     │  [Rotate]       │   │
│  │  └────────────────────┘                 │   │
│  │                                         │   │
│  │  Select an animal below:                │   │
│  │  ┌────────────────────┐ (auto-expanded) │   │
│  │  │ Genus:  [________] │                 │   │
│  │  │ Species:[________] │                 │   │
│  │  │ Common: [________] │                 │   │
│  │  │        [Search]    │                 │   │
│  │  │ ...results...      │                 │   │
│  │  └────────────────────┘                 │   │
│  │                                         │   │
│  │  [Create Entry]  [Cancel]               │   │
│  │  (no delete button in create mode)      │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## 7. Implementation Steps

### Phase 1: Server Backend (✅ COMPLETED)

1. ✅ **Implement animal ownership transfer** [server/dex/views.py:151-199]
   - Override `destroy()` in DexEntryViewSet
   - Transfers `animal.created_by` to next earliest discoverer on delete
   - Clears `created_by` if no other discoverers exist
   - Invalidates user dex cache before deletion

2. ✅ **Add image cleanup signal** [server/dex/signals.py:16-64]
   - Added `pre_delete` signal handler `cleanup_dex_entry_images`
   - Checks for orphaned `original_image` and `processed_image` files
   - Only deletes files not referenced by other entries
   - Preserves images in `source_vision_job` for audit purposes

3. ✅ **Update serializer for image replacement** [server/dex/serializers.py:124-245]
   - Added `source_vision_job` and `source_conversion` fields to DexEntryUpdateSerializer
   - Full validation for ownership, existence, and expiration
   - Handles image replacement in `update()` method

4. ✅ **Update serializer for manual entry creation** [server/dex/serializers.py:59-177]
   - Added `source_conversion` field to DexEntryCreateSerializer
   - Supports three image source modes: vision_job, conversion, or direct upload
   - Full validation for conversion ownership and expiration

### Phase 2: Client Scene Creation (Estimated: Core feature)

5. **Create edit_entry.tscn scene file**
   - Follow PaperCameraScene sibling UI pattern
   - Create all UI elements (header, image section, animal section, buttons)
   - Wire up unique names with explicit paths for web export

6. **Create edit_entry.gd script**
   - Implement state machine
   - Handle navigation context
   - Implement all button handlers
   - Wire up DexRecordImage component

7. **Register scene with NavigationManager**
   - Add scene to navigation registry
   - Configure transitions

### Phase 3: Integration (Estimated: Connections)

8. **Update dex.gd**
   - Change `_on_edit_pressed()` to navigate to new scene
   - Remove popup-related code
   - Handle return navigation with context

9. **Update camera.gd**
   - Add "Manual Entry" button to UI
   - Implement `_on_skip_analysis_pressed()`
   - Pass image data through navigation context

10. **Update api_config.gd**
    - Add `entry_detail` endpoint format string



---

## 8. File Changes Summary

### New Files

| File | Description |
|------|-------------|
| `scenes/edit_entry/edit_entry.tscn` | New scene file |
| `scenes/edit_entry/edit_entry.gd` | Scene controller script |

### Modified Files

| File | Changes |
|------|---------|
| `features/server_interface/api/services/dex_service.gd` | Add delete_entry() method |
| `features/server_interface/api/core/api_config.gd` | Add entry_detail endpoint |
| `scenes/dex/dex.gd` | Navigate to edit scene instead of popup |
| `scenes/camera/camera.gd` | Add manual entry button |
| `scenes/camera/camera.tscn` | Add SkipAnalysisButton UI element |
| `server/dex/views.py` | Override destroy() for ownership transfer |
| `server/dex/signals.py` | Add image cleanup signal |
| `server/dex/serializers.py` | Add source_conversion to update serializer |

### Deprecated (remove)

| File | Reason |
|------|--------|
| `features/ui/components/manual_entry_popup/` | Replaced by edit_entry scene |

---


## 10. References

### UX Best Practices Sources

- [Delete Dialog UX Design Guide - Almax Agency](https://almaxagency.com/blog/the-ultimate-guide-to-delete-dialog-ux-design/)
- [Better UX for Deleting Records - Lee Munroe](https://www.leemunroe.com/best-practice-deleting-records/)
- [Mastering CRUD Operations UX - Ola Mishina](https://medium.com/design-bootcamp/mastering-crud-operations-a-framework-for-seamless-product-design-2630affbc1e5)
- [Confirmation Dialog Best Practices - LogRocket](https://blog.logrocket.com/ux-design/double-check-user-actions-confirmation-dialog/)

### Django REST Framework Sources

- [DRF Authentication & Permissions Tutorial](https://www.django-rest-framework.org/tutorial/4-authentication-and-permissions/)
- [Django on_delete Behavior - Glinteco](https://glinteco.com/en/post/what-does-on_delete-do-on-django-models/)
- [Soft Delete Patterns - Medium](https://medium.com/@dryalcinmehmet/drf-part-2-mastering-django-rest-framework-how-to-applied-concurrency-and-safedelete-to-products-789c428ba7ae)

### Existing Codebase References

- PaperCameraScene pattern: `features/camera_system/paper_camera_scene.gd`
- Web export workarounds: `CLAUDE.md` (Web Export section)
- Existing edit flow: `scenes/dex/dex.gd:219-297`
- Manual entry popup: `features/ui/components/manual_entry_popup/manual_entry_popup.gd`
- Tree scene structure: `scenes/tree/tree_controller.gd`

---

## Appendix A: Delete Confirmation Dialog Copy

**Title:** Delete Entry?

**Body:**
> Are you sure you want to delete this entry?
>
> **"Canis lupus" (Gray Wolf)**
>
> This will permanently remove the entry and its image from your dex. This action cannot be undone.

**Buttons:**
- [Cancel] (secondary, gray)
- [Delete Forever] (destructive, red)

---

## Appendix B: Error Messages

| Scenario | Title | Message |
|----------|-------|---------|
| No animal selected (create) | "No Animal Selected" | "Please search for and select an animal before creating the entry." |
| Search no results | "No Results Found" | "No matching species found. Try different search terms or check spelling." |
| Delete failed | "Delete Failed" | "Could not delete entry. Please try again." |
| Save failed | "Save Failed" | "Could not save changes. Please check your connection and try again." |
| Load failed | "Load Error" | "Could not load entry data. Please go back and try again." |
| Image upload failed | "Upload Failed" | "Could not upload image. Please try a different file." |
| Non-owner edit | "Cannot Edit" | "You can only edit your own dex entries." |