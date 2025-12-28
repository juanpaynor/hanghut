# Profile Photo Upload Setup - Complete

## What Was Added

### 1. Dependencies
✅ `image_picker` - Native image picker for iOS/Android/Web
✅ `nhost_storage_dart` - Already included, now used for uploads

### 2. Profile Setup Flow Updated
- **5 steps total** (was 4):
  1. **Photo Upload** (NEW) - Optional, skip or add later
  2. **Basics** - Bio, DOB, Gender
  3. **Vibe Check** - 10 personality questions
  4. **Interests** - Select interest tags
  5. **Preferences** - Budget, goals

### 3. Storage Configuration
Created: `/nhost/config/storage.yaml`
- Defines `profile-photos` bucket
- 5MB max file size
- Allowed types: JPEG, PNG, WebP, HEIC

### 4. Code Changes

**ProfileService** (`lib/core/services/profile_service.dart`):
- Added `photoUrl` parameter to `createProfile()`
- Inserts photo record into `user_photos` table with `is_primary: true`

**ProfileSetupScreen** (`lib/features/profile/screens/profile_setup_screen.dart`):
- Added `_pickPhoto()` - Opens native image picker
- Added `_uploadPhoto()` - Uploads to Nhost storage, returns public URL
- Added `_buildPhotoStep()` - Beautiful circular photo preview UI
- Auto-uploads photo when user proceeds from Step 1

## Manual Setup Required

### Step 1: Create Storage Bucket in Nhost Console
1. Go to **https://app.nhost.io/**
2. Select your project: **qxybjyshkyipgvgnasrk**
3. Click **Storage** in left sidebar
4. Click **"+ Add Bucket"** (or similar create button)
5. Fill in:
   - **Bucket ID**: `profile-photos`
   - **Public access**: OFF (keep private)
   - **Max file size**: 5 MB
   - **Allowed file types**: Select `image/jpeg`, `image/png`, `image/webp`
6. Click **Save/Create**

That's it for storage! Nhost handles the rest automatically.

### Step 2: Set Hasura Permissions on user_photos Table

1. Go to **Hasura Console** (link from Nhost dashboard)
2. **Data** tab → **public** schema → **user_photos** table
3. Track the table if not already tracked
4. Go to **Permissions** tab
5. For **'user'** role, configure:

**INSERT**:
- Row insert check: `{ "user_id": { "_eq": "X-Hasura-User-Id" } }`
- Column insert permissions: `photo_url`, `is_primary`, `display_order`
- Column presets:
  - `user_id` → `X-Hasura-User-Id`

**SELECT**:
- Row select check (users can see their own + primary photos of others):
```json
{
  "_or": [
    { "user_id": { "_eq": "X-Hasura-User-Id" } },
    { "is_primary": { "_eq": true } }
  ]
}
```
- Select all columns

**UPDATE**:
- Row update check: `{ "user_id": { "_eq": "X-Hasura-User-Id" } }`
- Columns: `is_primary`, `display_order`

**DELETE**:
- Row delete check: `{ "user_id": { "_eq": "X-Hasura-User-Id" } }`

## Testing Flow

1. **Sign up** new user
2. **Step 1: Photo**
   - Tap circle to select photo from gallery
   - Preview appears
   - Can change photo or skip
   - Click "Next" → auto-uploads to Nhost
3. **Complete remaining steps** (Basics, Vibe, Interests, Preferences)
4. **Finish setup** → photo URL saved to `user_photos` table

## What's Next

Once photos are working, we can:
1. **Update MapScreen** to show profile photos on markers
2. **Fetch primary photo** from `user_photos` via GraphQL
3. **Use CircleAvatar** with NetworkImage for map pins
4. **Add glow/halo** effects based on match scores

## Notes

- Photos are **optional** - users can skip and add later
- Storage is **private** by default - only accessible via Nhost URLs
- `is_primary: true` ensures one main photo per user
- Photo URLs use Nhost's signed URL system for security
