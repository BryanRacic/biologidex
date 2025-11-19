# Deployment Notes - Admin Friendship & Friend Code Display

## Changes Made

### Backend Changes

#### 1. Auto-Friendship with Admin on User Creation
- **File**: `server/accounts/signals.py`
- **Change**: Added `create_admin_friendship()` signal handler that automatically creates an accepted friendship between new users and the admin account
- **Behavior**:
  - When a new user registers, they are automatically friended with the first superuser (admin)
  - Admin can now see all user dex entries, trees, etc.
  - This friendship is created in 'accepted' state (no request needed)

#### 2. Filter Admin from User-Facing Friend Lists
- **File**: `server/social/models.py`
- **Changes**:
  - `get_friends()`: Now excludes superusers (admin) from returned queryset
  - `get_friend_ids()`: Excludes admin from both sent and received friend IDs
  - `get_pending_requests()`: Excludes friend requests from admin users
- **Behavior**:
  - Users will never see admin in their friends list
  - Users will never see admin in pending requests
  - Admin friendships are invisible to users but functional for admin

### Client Changes

#### 1. Display Friend Code in Social Tab
- **Files**:
  - `client/biologidex-client/social.tscn`: Added UI elements for friend code display
  - `client/biologidex-client/social.gd`: Added `_load_friend_code()` function
  - `client/biologidex-client/api/services/auth_service.gd`: Added `get_friend_code()` method
- **Behavior**:
  - Friend code now displays at the top of the social tab
  - Shows "Your Friend Code: [CODE]" prominently above the "Add Friend" section

## Deployment Steps

### 1. Server Deployment

Since no database schema changes were made, no migrations are needed. Simply:

```bash
cd server

# If using production Docker:
docker-compose -f docker-compose.production.yml build web celery_worker celery_beat
docker-compose -f docker-compose.production.yml up -d

# Or if using local development:
poetry run python manage.py check
poetry run python manage.py runserver
```

### 2. Create Admin-to-Existing-Users Friendships (One-Time)

For existing users who registered before this change, you'll need to create friendships with admin:

```python
# Run in Django shell: python manage.py shell
from django.contrib.auth import get_user_model
from social.models import Friendship

User = get_user_model()

# Get admin user
admin = User.objects.filter(is_superuser=True).first()

if admin:
    # Get all non-admin users
    users = User.objects.filter(is_superuser=False)

    for user in users:
        # Check if friendship already exists
        existing = Friendship.objects.filter(
            from_user=admin,
            to_user=user
        ).first()

        if not existing:
            Friendship.objects.create(
                from_user=admin,
                to_user=user,
                status='accepted'
            )
            print(f"Created friendship with {user.username}")
        else:
            print(f"Friendship already exists with {user.username}")
```

### 3. Client Deployment

Export the Godot client as usual:

```bash
./scripts/export-to-prod.sh
```

## Testing

### Test Admin Functionality (as Admin)
1. Log in as admin user
2. Navigate to dex view - should see all users' entries
3. Navigate to tree view with "friends" mode - should see all users' animals
4. Verify friends list works normally

### Test User Functionality (as Regular User)
1. Create a new user account
2. Navigate to social tab
3. **Verify**: Friend code displays at top of screen
4. **Verify**: Admin does NOT appear in friends list
5. **Verify**: Can view own dex and tree normally
6. Add another regular user as friend
7. **Verify**: Can see that friend's dex and tree
8. **Verify**: Still cannot see admin in any list

### Test Friend Code Display
1. Navigate to social tab
2. **Verify**: "Your Friend Code:" section appears below header
3. **Verify**: 8-character code displays in large text
4. **Verify**: Code matches the one returned by `/api/v1/users/friend-code/`

## Affected Endpoints

The following endpoints now automatically filter out admin users:

- `GET /api/v1/social/friends/` - Friends list
- `GET /api/v1/social/pending/` - Pending friend requests
- `GET /api/v1/dex/friends_overview/` - Friends dex overview
- `GET /api/v1/graph/tree/` (with mode=friends) - Friend trees

Admin users can still access all user data through:
- Direct user ID endpoints
- Django admin panel
- Their own friend list (which includes all users)

## Rollback Plan

If issues arise:

1. **Remove signal**: Comment out `create_admin_friendship()` in `server/accounts/signals.py`
2. **Remove filters**: Restore original `get_friends()`, `get_friend_ids()`, and `get_pending_requests()` methods in `server/social/models.py`
3. **Delete admin friendships**:
   ```python
   admin = User.objects.filter(is_superuser=True).first()
   if admin:
       Friendship.objects.filter(from_user=admin).delete()
       Friendship.objects.filter(to_user=admin).delete()
   ```
4. Rebuild and restart server

## Notes

- No database migrations required (only code changes)
- Signal runs automatically for new users going forward
- Existing users need one-time script (see step 2 above)
- Admin visibility is one-way: admin sees users, users don't see admin
- Client changes are backward compatible
