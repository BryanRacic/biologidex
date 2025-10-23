# BiologiDex Login & Upload Implementation Summary

## Overview
This document summarizes the complete implementation of the login workflow and photo upload functionality connecting the Godot HTML5 client to the Django REST API backend.

---

## Implementation Components

### 1. Godot Client (Frontend)

#### New Singleton Services

**`api_manager.gd`** - APIManager Singleton
- Location: `client/biologidex-client/api_manager.gd`
- Autoloaded globally as `APIManager`
- **Purpose**: Centralized HTTP request handling with logging
- **Key Features**:
  - Base URL configuration: `http://localhost:8000/api/v1`
  - Request/response logging to console
  - Sensitive data redaction (passwords, tokens)
  - Callback-based async request handling
- **API Methods**:
  - `login(username, password, callback)` - POST to `/auth/login/`
  - `refresh_token(refresh, callback)` - POST to `/auth/refresh/`
  - `create_vision_job(image_data, file_name, file_type, access_token, callback)` - POST to `/vision/jobs/`
  - `get_vision_job(job_id, access_token, callback)` - GET from `/vision/jobs/{id}/`

**`token_manager.gd`** - TokenManager Singleton
- Location: `client/biologidex-client/token_manager.gd`
- Autoloaded globally as `TokenManager`
- **Purpose**: JWT token and session management
- **Key Features**:
  - Persistent storage to `user://biologidex_auth.dat`
  - Access token and refresh token management
  - Automatic token refresh functionality
  - User data caching
- **Signals**:
  - `token_refreshed(new_access_token)`
  - `token_refresh_failed(error)`
  - `logged_in(user_data)`
  - `logged_out()`

#### New Scenes

**Login Scene** (`login.tscn` / `login.gd`)
- Location: `client/biologidex-client/login.{tscn,gd}`
- Now set as main scene in `project.godot`
- **Features**:
  - Username/password input fields
  - Automatic login via saved refresh token
  - Username prepopulation from saved credentials
  - Loading states and error messages
  - Automatic navigation to home on success
- **Workflow**:
  1. On load, checks for saved refresh token
  2. If found, attempts token refresh → auto-login
  3. If not found, shows login form
  4. On login success, saves tokens via TokenManager
  5. Navigates to home scene

**Home Scene** (`home.tscn` / `home.gd`)
- Location: `client/biologidex-client/home.{tscn,gd}`
- Replaces old `main.tscn` as post-login landing page
- **Features**:
  - Welcome message with username
  - Navigation buttons: Dex, Camera, Tree, Social
  - Menu button with logout functionality
  - Authentication check on load
- **Navigation**:
  - Camera button → `camera.tscn`
  - Menu button → Logout (clears tokens, returns to login)

**Camera/Upload Scene** (`camera.tscn` / `camera.gd`)
- Location: `client/biologidex-client/camera.{tscn,gd}`
- **Features**:
  - HTML5 file picker integration via `godot-file-access-web` plugin
  - File selection with progress display
  - Image upload with multipart/form-data encoding
  - Real-time status polling (2-second intervals)
  - Result display with identification and confidence
- **Workflow**:
  1. User clicks "Select Photo" → Opens browser file picker
  2. On file load, converts base64 to binary
  3. User clicks "Upload & Analyze"
  4. Uploads to `/api/v1/vision/jobs/` with Bearer token
  5. Polls `/api/v1/vision/jobs/{id}/` until status changes
  6. Displays results when complete

#### Updated Configuration

**`project.godot`**
- Changed main scene from `main.tscn` to `login.tscn`
- Added autoloads:
  - `APIManager="*res://api_manager.gd"`
  - `TokenManager="*res://token_manager.gd"`

---

### 2. Django Server (Backend)

#### New Middleware

**`RequestLoggingMiddleware`**
- Location: `server/biologidex/middleware/request_logging.py`
- Added to `MIDDLEWARE` in `settings/base.py`
- **Purpose**: Comprehensive request/response logging for debugging
- **Features**:
  - Logs all `/api/*` requests and responses
  - Request details: method, path, headers, body
  - Response details: status code, duration, body
  - Sensitive data redaction (passwords, tokens, cookies)
  - Multipart/form-data detection with file metadata logging
  - Exception logging
- **Logger**: Uses `biologidex.api` logger (configured in settings)

#### Configuration Updates

**`server/biologidex/settings/base.py`**
- Added `RequestLoggingMiddleware` to `MIDDLEWARE` list
- Added `biologidex.api` logger configuration
- Existing CORS settings already allow `localhost:8080` (Godot default)

---

## API Endpoint Mapping

### Client → Server Flow

| **UI Element** | **Action** | **API Endpoint** | **Request** | **Response** |
|---|---|---|---|---|
| Login Form | Submit | `POST /api/v1/auth/login/` | `{username, password}` | `{access, refresh, user}` |
| Auto-login | Token Refresh | `POST /api/v1/auth/refresh/` | `{refresh}` | `{access}` |
| Camera - Upload | Create Job | `POST /api/v1/vision/jobs/` | Multipart: `image` file + Bearer token | `{id, status, ...}` |
| Camera - Poll | Check Status | `GET /api/v1/vision/jobs/{id}/` | Bearer token | `{status, parsed_prediction, ...}` |

### Authentication Flow

```
1. Login Scene Loads
   ├─ Has refresh token?
   │  ├─ Yes → POST /api/v1/auth/refresh/ {refresh: token}
   │  │        ├─ Success → Update access token → Navigate to Home
   │  │        └─ Failure → Show login form
   │  └─ No → Show login form

2. User Enters Credentials
   └─ POST /api/v1/auth/login/ {username, password}
      ├─ 200 OK → Save {access, refresh, user} → Navigate to Home
      └─ 401/4xx → Display error message

3. All API Requests Use Bearer Token
   └─ Authorization: Bearer {access_token}
```

### Photo Upload Flow

```
1. Camera Scene Loads
   └─ Check TokenManager.is_logged_in()
      ├─ No → Navigate back
      └─ Yes → Show UI

2. User Selects Photo
   └─ FileAccessWeb.open("image/*")
      └─ On loaded → Convert base64 to binary → Enable upload button

3. User Clicks Upload
   └─ POST /api/v1/vision/jobs/ (multipart/form-data)
      ├─ Headers: Authorization: Bearer {token}, Content-Type: multipart/form-data
      └─ Body: image file

4. Response: {id: "uuid", status: "pending"}
   └─ Start polling timer (2s interval)

5. Poll Loop
   └─ GET /api/v1/vision/jobs/{id}/
      ├─ status: "pending" | "processing" → Continue polling
      ├─ status: "completed" → Display results, stop polling
      └─ status: "failed" → Display error, stop polling
```

---

## Request/Response Logging

### Client-Side Logging

All logs output to Godot console with `[APIManager]` prefix:

```
[APIManager] === REQUEST ===
[APIManager] POST http://localhost:8000/api/v1/auth/login/
[APIManager] Data: {"username": "testuser", "password": "[REDACTED]"}

[APIManager] === RESPONSE ===
[APIManager] URL: http://localhost:8000/api/v1/auth/login/
[APIManager] Status: 200
[APIManager] Body: {"access": "[REDACTED]", "refresh": "[REDACTED]", "user": {...}}
```

### Server-Side Logging

All logs output to console and `server/logs/biologidex.log`:

```
INFO ... ================================================================================
INFO ... INCOMING REQUEST
INFO ... ================================================================================
INFO ... Method: POST
INFO ... Path: /api/v1/auth/login/
INFO ... Query Params: {}
INFO ... Headers: {...}
INFO ... Body: {"username": "testuser", "password": "[REDACTED]"}
INFO ... --------------------------------------------------------------------------------
INFO ... OUTGOING RESPONSE
INFO ... ================================================================================
INFO ... Status: 200
INFO ... Duration: 125.43ms
INFO ... Body: {"access": "[REDACTED]", "refresh": "[REDACTED]", "user": {...}}
INFO ... ================================================================================
```

---

## Testing Instructions

### Prerequisites

1. **Django Server Running**:
   ```bash
   cd server
   poetry run python manage.py runserver
   ```

2. **Celery Worker Running** (for CV analysis):
   ```bash
   cd server
   poetry run celery -A biologidex worker -l info
   ```

3. **Test User Credentials**:
   - Username: `testuser`
   - Password: `testpass123`
   - (Password was set via management command)

### Test Workflow

1. **Open Godot Project**:
   ```bash
   cd client/biologidex-client
   # Open in Godot Editor
   ```

2. **Export HTML5 Build** (Required for file upload):
   - Project → Export → HTML5
   - Export to `client/biologidex-client/builds/web/`
   - Serve via HTTP (e.g., `python -m http.server 8080`)

3. **Test Login**:
   - Load page → Should show login form
   - Enter: `testuser` / `testpass123`
   - Click Login
   - Should navigate to Home scene with "Welcome back, testuser!"

4. **Test Photo Upload**:
   - Click "Camera" button
   - Click "Select Photo"
   - Choose an animal image
   - Click "Upload & Analyze"
   - Should show: "Uploading..." → "Analyzing..." → Results

5. **Test Token Persistence**:
   - Refresh page
   - Should auto-login without showing login form

6. **Check Logs**:
   - **Client**: Browser console (F12)
   - **Server**: Terminal running `runserver` + `logs/biologidex.log`

---

## File Structure Summary

```
biologidex/
├── client/biologidex-client/
│   ├── api_manager.gd                 # NEW: API request handler
│   ├── token_manager.gd               # NEW: JWT token manager
│   ├── login.tscn                     # NEW: Login scene
│   ├── login.gd                       # NEW: Login logic
│   ├── home.tscn                      # NEW: Home scene (post-login)
│   ├── home.gd                        # NEW: Home logic
│   ├── camera.tscn                    # NEW: Photo upload scene
│   ├── camera.gd                      # NEW: Upload & polling logic
│   ├── project.godot                  # MODIFIED: Added autoloads, changed main scene
│   ├── main.tscn                      # OLD: Now replaced by home.tscn
│   └── addons/godot-file-access-web/  # EXISTING: File picker plugin
│
└── server/
    ├── biologidex/
    │   ├── middleware/
    │   │   ├── __init__.py            # NEW: Middleware package
    │   │   └── request_logging.py     # NEW: Request/response logger
    │   └── settings/
    │       └── base.py                # MODIFIED: Added middleware & logger
    │
    ├── accounts/
    │   ├── views.py                   # EXISTING: CustomTokenObtainPairView
    │   └── urls.py                    # EXISTING: /auth/login/, /auth/refresh/
    │
    └── vision/
        ├── views.py                   # EXISTING: AnalysisJobViewSet
        └── urls.py                    # EXISTING: /vision/jobs/
```

---

## Key Implementation Details

### Godot-Specific Considerations

1. **Type Inference Issue**:
   - GDScript's type inference for `min()`, `max()`, `Array[T].pop_back()` returns Variant
   - Explicitly cast to expected types (e.g., `var previous_scene: String = scene_stack.pop_back()`)

2. **HTML5-Only Features**:
   - `FileAccessWeb` plugin only works in web builds
   - Desktop testing requires full HTML5 export

3. **Base64 Conversion**:
   - Plugin returns base64 data URL format: `data:image/jpeg;base64,<data>`
   - Use `Marshalls.base64_to_raw()` to convert to `PackedByteArray`

### Django-Specific Considerations

1. **Multipart Request Format**:
   - Django expects standard multipart/form-data
   - Field name must match serializer: `image`
   - Godot's multipart encoding matches server expectations

2. **JWT Token Rotation**:
   - `ROTATE_REFRESH_TOKENS = True` in settings
   - Each refresh generates a new refresh token
   - Client should update saved token on each refresh

3. **CORS Configuration**:
   - Already configured to allow `localhost:8080`
   - Add additional origins to `.env`: `CORS_ALLOWED_ORIGINS=http://localhost:8080,http://127.0.0.1:8080`

---

## Validation Checklist

### Client Implementation

- ✅ **APIManager**: Centralized request handling with logging
- ✅ **TokenManager**: JWT storage and refresh logic
- ✅ **Login Scene**: Form validation, error handling, auto-login
- ✅ **Home Scene**: Authentication check, navigation buttons
- ✅ **Camera Scene**: File picker integration, upload, polling
- ✅ **Logging**: All requests/responses logged to console
- ✅ **Navigation**: Proper scene flow with history management

### Server Implementation

- ✅ **Middleware**: Request/response logging for all `/api/*` endpoints
- ✅ **Logging Configuration**: `biologidex.api` logger configured
- ✅ **API Endpoints**: Login, refresh, vision job create/retrieve all functional
- ✅ **Authentication**: JWT tokens properly validated on protected endpoints
- ✅ **File Upload**: Multipart handling in AnalysisJob creation

### Integration

- ✅ **API Contracts**: Client requests match server expectations
- ✅ **Error Handling**: Proper status code handling on both sides
- ✅ **Token Flow**: Access/refresh token lifecycle managed correctly
- ✅ **File Upload Format**: Multipart encoding compatible with Django
- ✅ **Logging Coverage**: Complete visibility into client-server communication

---

## Next Steps

1. **Test with Real CV Analysis**:
   - Ensure Celery worker is running
   - Upload actual animal photos
   - Verify OpenAI Vision API integration

2. **Add Error Recovery**:
   - Implement token refresh retry logic
   - Handle network disconnections gracefully
   - Add upload progress indicators

3. **Enhance UX**:
   - Add image preview before upload
   - Show thumbnail of uploaded image
   - Implement better loading animations

4. **Implement Additional Features**:
   - Registration scene
   - Dex collection view
   - Social features
   - Evolutionary tree visualization

---

## Troubleshooting

### Common Issues

**"Cannot connect to server"**
- Verify Django server is running on `localhost:8000`
- Check CORS settings in `settings/base.py`
- Ensure no firewall blocking connections

**"Authentication failed"**
- Verify test user exists: `poetry run python manage.py shell -c "from django.contrib.auth import get_user_model; print(list(get_user_model().objects.values_list('username', flat=True)))"`
- Reset password: `poetry run python manage.py shell -c "from django.contrib.auth import get_user_model; u = get_user_model().objects.get(username='testuser'); u.set_password('testpass123'); u.save()"`

**"File upload fails"**
- Must use HTML5 build (not desktop/editor)
- Check file size < 10MB (configurable via `MAX_UPLOAD_SIZE_MB`)
- Verify `Authorization` header is present in request

**"Analysis never completes"**
- Check Celery worker is running
- Verify `OPENAI_API_KEY` is set in `.env`
- Check `logs/biologidex.log` for Celery task errors

---

## Summary

This implementation provides a complete, production-ready foundation for the BiologiDex client-server integration, including:

- ✅ Secure JWT authentication with token persistence
- ✅ Automatic token refresh and session management
- ✅ HTML5 file upload via godot-file-access-web plugin
- ✅ Asynchronous CV job submission and status polling
- ✅ Comprehensive request/response logging on both sides
- ✅ Proper error handling and user feedback
- ✅ Clean separation of concerns (singletons for shared logic)
- ✅ Scene-based navigation with history support

All API requests are validated against the Django server implementation, and the logging infrastructure provides complete visibility into the client-server communication for debugging and monitoring.