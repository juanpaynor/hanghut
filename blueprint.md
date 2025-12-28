# BiteMates - Complete Project Blueprint

## Project Overview

**BiteMates** is a social dining discovery app that combines the map-first approach of Nomad Table with the personality-based algorithmic matching of Timeleft. Users discover nearby dining experiences ("tables") on an interactive map, with visual indicators showing compatibility based on personality traits, interests, and preferences.

### Core Concept
- **Discovery**: Map shows profile photo markers of users hosting tables
- **Matching**: Visual glow effects indicate personality compatibility (>80% = neon glow, 60-80% = pulse, <60% = standard)
- **Flexible Modes**: Users can browse tables manually OR click center button to let BiteMates auto-match/create a table
- **Real Connections**: All interactions lead to real-life dining experiences with personality-matched groups

### Current Status
**Phase: Profile Setup & Data Infrastructure Complete**
- ✅ Full authentication flow with Nhost
- ✅ 5-step profile setup (photo, basics, vibe check, interests, preferences)
- ✅ Database schema with all tables
- ✅ GraphQL API with permissions
- ✅ Storage bucket for profile photos
- ✅ Map screen scaffolded with Mapbox
- ⏳ Next: Wire map to show real tables with match-based markers

---

## Technology Stack (IMPLEMENTED)

### Frontend - Flutter
- **SDK Version**: ^3.9.0
- **Platforms**: iOS, Android, Web
- **State Management**: Provider pattern
- **Dependencies** (see `pubspec.yaml`):
  - `cupertino_icons: ^1.0.8`
  - `google_fonts: ^6.3.2` - Typography
  - `provider: ^6.1.5+1` - State management
  - `flutter_svg: ^2.2.3` - SVG rendering
  - `flutter_animate: ^4.5.2` - UI animations
  - `mapbox_maps_flutter: ^2.12.0` - Map interface
  - `nhost_sdk: ^5.8.0` - Nhost client
  - `nhost_flutter_auth: ^4.2.1` - Authentication
  - `graphql: ^5.2.3` - GraphQL client
  - `graphql_flutter: ^5.2.1` - GraphQL Flutter integration
  - `image_picker: ^1.2.1` - Photo selection
  - `nhost_storage_dart: ^2.2.0` - File uploads

### Backend - Nhost Cloud
- **Instance**: 
  - Subdomain: `qxybjyshkyipgvgnasrk`
  - Region: `ap-southeast-1` (Singapore)
- **Database**: PostgreSQL 14.18
- **GraphQL**: Hasura v2.48.5-ce
- **Storage**: Nhost Storage v0.9.1
- **Auth**: Nhost Auth v0.43.0

### API Endpoints
- **GraphQL**: `https://qxybjyshkyipgvgnasrk.hasura.ap-southeast-1.nhost.run/v1/graphql`
- **Auth**: `https://qxybjyshkyipgvgnasrk.auth.ap-southeast-1.nhost.run/v1/auth`
- **Storage**: `https://qxybjyshkyipgvgnasrk.storage.ap-southeast-1.nhost.run/v1/storage`

### Third-Party Services (PLANNED)
- **Real-time Chat**: Ably (not yet integrated, user has key ready)
- **Geospatial**: H3 extension (in schema but not yet used)

---

## Complete Database Schema (IMPLEMENTED)

All tables created via `/nhost/migrations/default/20240522000000_init_schema/up.sql`

### Core Tables

#### `users` (public schema)
```sql
id              UUID PRIMARY KEY
email           TEXT UNIQUE NOT NULL
auth_provider   ENUM (email, google, apple)
display_name    TEXT NOT NULL
bio             TEXT
date_of_birth   DATE
gender_identity TEXT
created_at      TIMESTAMPTZ DEFAULT NOW()
updated_at      TIMESTAMPTZ DEFAULT NOW()
last_active_at  TIMESTAMPTZ
home_location_lat    DOUBLE PRECISION
home_location_lng    DOUBLE PRECISION
home_h3_res8    TEXT (H3 hex index)
home_h3_res9    TEXT (H3 hex index)
is_verified_email    BOOLEAN DEFAULT FALSE
is_verified_phone    BOOLEAN DEFAULT FALSE
is_verified_photo    BOOLEAN DEFAULT FALSE
trust_score     INTEGER DEFAULT 50 (0-100)
total_meetups_attended  INTEGER DEFAULT 0
total_no_shows  INTEGER DEFAULT 0
status          ENUM (active, suspended, banned)
```

#### `user_personality`
Big 5 personality traits from 10-question vibe check
```sql
user_id             UUID PRIMARY KEY -> users(id)
openness            INTEGER (1-5)
conscientiousness   INTEGER (1-5)
extraversion        INTEGER (1-5)
agreeableness       INTEGER (1-5)
neuroticism         INTEGER (1-5)
completed_at        TIMESTAMPTZ DEFAULT NOW()
```

#### `user_preferences`
```sql
user_id                     UUID PRIMARY KEY -> users(id)
budget_min                  INTEGER (in local currency)
budget_max                  INTEGER
primary_goal                ENUM (friends, romance, casual)
open_to_all_goals           BOOLEAN DEFAULT FALSE
preferred_meetup_mode       ENUM (matched, create_own, both)
gender_preference           ENUM (women_only, men_only, mix_preferred, no_preference)
preferred_group_size_min    INTEGER DEFAULT 3
preferred_group_size_max    INTEGER DEFAULT 6
```

#### `user_photos`
```sql
id              UUID PRIMARY KEY
user_id         UUID -> users(id)
photo_url       TEXT NOT NULL (Nhost storage URL)
is_primary      BOOLEAN DEFAULT FALSE
is_face_verified BOOLEAN DEFAULT FALSE
display_order   INTEGER DEFAULT 0
uploaded_at     TIMESTAMPTZ DEFAULT NOW()
```
**Constraint**: Only one primary photo per user

#### `interest_tags`
Pre-seeded with 50+ tags across categories
```sql
id          UUID PRIMARY KEY
name        TEXT UNIQUE NOT NULL
category    ENUM (food, activities, hobbies, music, sports, arts, tech, travel, other)
icon        TEXT (emoji or icon name)
created_at  TIMESTAMPTZ DEFAULT NOW()
```

#### `user_interests`
Many-to-many junction table
```sql
id              UUID PRIMARY KEY
user_id         UUID -> users(id)
interest_tag_id UUID -> interest_tags(id)
added_at        TIMESTAMPTZ DEFAULT NOW()
UNIQUE(user_id, interest_tag_id)
```

#### `tables` (meetups/dining sessions)
```sql
id                  UUID PRIMARY KEY
host_user_id        UUID -> users(id)
title               TEXT NOT NULL
description         TEXT
activity_type       ENUM (dinner, drinks, coffee, brunch, activity, other)
venue_name          TEXT NOT NULL
venue_address       TEXT NOT NULL
location_lat        DOUBLE PRECISION NOT NULL
location_lng        DOUBLE PRECISION NOT NULL
h3_res8             TEXT (auto-generated)
h3_res9             TEXT (auto-generated)
scheduled_at        TIMESTAMPTZ NOT NULL
duration_minutes    INTEGER DEFAULT 120
budget_min_per_person    INTEGER
budget_max_per_person    INTEGER
max_capacity        INTEGER (2-20)
current_capacity    INTEGER DEFAULT 0
table_mode          ENUM (matched, public, private)
goal_type           ENUM (friends, romance, casual)
gender_filter       ENUM (women_only, men_only, mix, none)
requires_approval   BOOLEAN DEFAULT TRUE
status              ENUM (draft, open, full, in_progress, completed, cancelled)
ably_channel_id     TEXT (for chat)
created_at          TIMESTAMPTZ DEFAULT NOW()
updated_at          TIMESTAMPTZ DEFAULT NOW()
```

#### `table_members`
```sql
id              UUID PRIMARY KEY
table_id        UUID -> tables(id)
user_id         UUID -> users(id)
role            ENUM (host, member)
status          ENUM (pending, approved, joined, declined, left, no_show, attended)
requested_at    TIMESTAMPTZ DEFAULT NOW()
approved_at     TIMESTAMPTZ
joined_at       TIMESTAMPTZ
left_at         TIMESTAMPTZ
UNIQUE(table_id, user_id)
```

#### `matching_queue`
For "Surprise Me" auto-match feature
```sql
id                  UUID PRIMARY KEY
user_id             UUID -> users(id)
timeframe_preference ENUM (today, tomorrow, this_week, weekend, custom)
custom_date         TIMESTAMPTZ
requested_at        TIMESTAMPTZ DEFAULT NOW()
status              ENUM (pending, matched, expired)
matched_table_id    UUID -> tables(id)
matched_at          TIMESTAMPTZ
```

#### `messages`
```sql
id              UUID PRIMARY KEY
table_id        UUID -> tables(id)
sender_id       UUID -> users(id)
content         TEXT NOT NULL
message_type    ENUM (text, image, system)
sent_at         TIMESTAMPTZ DEFAULT NOW()
ably_message_id TEXT UNIQUE
```

#### `message_reads`
```sql
message_id  UUID -> messages(id)
user_id     UUID -> users(id)
read_at     TIMESTAMPTZ DEFAULT NOW()
PRIMARY KEY (message_id, user_id)
```

#### `ratings`
Post-meetup feedback system
```sql
id                  UUID PRIMARY KEY
table_id            UUID -> tables(id)
rater_user_id       UUID -> users(id)
rated_user_id       UUID -> users(id)
overall_score       INTEGER (1-5)
friendliness_score  INTEGER (1-5)
punctuality_score   INTEGER (1-5)
engagement_score    INTEGER (1-5)
review_text         TEXT
is_no_show          BOOLEAN DEFAULT FALSE
created_at          TIMESTAMPTZ DEFAULT NOW()
UNIQUE(table_id, rater_user_id, rated_user_id)
```

#### `travel_plans`
```sql
id                  UUID PRIMARY KEY
user_id             UUID -> users(id)
destination_city    TEXT NOT NULL
destination_country TEXT NOT NULL
destination_lat     DOUBLE PRECISION NOT NULL
destination_lng     DOUBLE PRECISION NOT NULL
destination_h3_res5 TEXT (city-level)
destination_h3_res7 TEXT (neighborhood-level)
start_date          DATE NOT NULL
end_date            DATE NOT NULL
trip_purpose        ENUM (vacation, work, moving, visiting, other)
status              ENUM (planning, confirmed, in_progress, completed)
created_at          TIMESTAMPTZ DEFAULT NOW()
```

#### `travel_matches`
```sql
id                  UUID PRIMARY KEY
travel_plan_id_1    UUID -> travel_plans(id)
travel_plan_id_2    UUID -> travel_plans(id)
match_score         INTEGER (0-100)
ably_channel_id     TEXT
matched_at          TIMESTAMPTZ DEFAULT NOW()
status              ENUM (active, archived)
UNIQUE(travel_plan_id_1, travel_plan_id_2)
```

#### `blocks`
```sql
blocker_user_id UUID -> users(id)
blocked_user_id UUID -> users(id)
blocked_at      TIMESTAMPTZ DEFAULT NOW()
PRIMARY KEY (blocker_user_id, blocked_user_id)
```

#### `reports`
```sql
id                  UUID PRIMARY KEY
reporter_user_id    UUID -> users(id)
reported_user_id    UUID -> users(id)
table_id            UUID -> tables(id) (optional)
reason              ENUM (harassment, fake_profile, no_show, inappropriate, other)
description         TEXT
status              ENUM (pending, reviewed, actioned, dismissed)
created_at          TIMESTAMPTZ DEFAULT NOW()
reviewed_at         TIMESTAMPTZ
reviewer_notes      TEXT
```

### Database Views (IMPLEMENTED)

#### `map_ready_tables`
Optimized view for Smart Map pins
```sql
SELECT
    t.*, -- all table columns
    u.id AS host_id,
    u.display_name AS host_name,
    u.bio AS host_bio,
    u.trust_score AS host_trust_score,
    up.openness, conscientiousness, extraversion, agreeableness, neuroticism,
    COALESCE(member_stats.member_count, 0) AS member_count,
    COALESCE(member_stats.approved_count, 0) AS approved_count,
    COALESCE(member_stats.pending_count, 0) AS pending_count,
    (t.max_capacity - approved_count) AS seats_left,
    CASE WHEN status = 'open' AND seats_left <= 1 THEN 'almost_full'
         WHEN status = 'open' THEN 'open'
         WHEN status = 'full' THEN 'full'
         ELSE 'other'
    END AS availability_state
FROM tables t
JOIN users u ON u.id = t.host_user_id
LEFT JOIN user_personality up ON up.user_id = u.id
LEFT JOIN (aggregated member stats) AS member_stats ON member_stats.table_id = t.id
WHERE t.status IN ('open', 'full')
ORDER BY t.scheduled_at;
```

### Storage Buckets (IMPLEMENTED)

#### `profile-photos`
Created via `/nhost/migrations/default/20240522000002_setup_storage/up.sql`
```sql
INSERT INTO storage.buckets (id, max_upload_file_size, download_expiration, 
                              min_upload_file_size, cache_control, presigned_urls_enabled)
VALUES ('profile-photos', 5242880, 30, 0, 'max-age=3600', true);
```
- **Max size**: 5MB
- **Allowed types**: JPEG, PNG, WebP
- **Access**: Private, presigned URLs for auth users

---

## Flutter App Structure (IMPLEMENTED)

```
lib/
├── main.dart                          # App entry point
├── core/
│   ├── config/
│   │   └── nhost_config.dart         # Nhost client singleton, endpoints
│   ├── services/
│   │   ├── profile_service.dart      # GraphQL: getInterestTags, createProfile
│   │   ├── table_service.dart        # GraphQL: getMapReadyTables (with distance filter)
│   │   └── matching_service.dart     # calculateMatch (score, label, color, glow)
│   └── theme/
│       └── app_theme.dart            # Colors, text styles
├── features/
│   ├── auth/
│   │   └── screens/
│   │       ├── login_screen.dart     # Email/password login
│   │       └── signup_screen.dart    # Email/password signup
│   ├── profile/
│   │   └── screens/
│   │       └── profile_setup_screen.dart  # 5-step wizard
│   ├── map/
│   │   └── screens/
│   │       └── map_screen.dart       # Mapbox map with placeholder markers
│   └── home/
│       └── screens/
│           └── main_navigation_screen.dart  # Bottom nav: Feed, Map, Host, Trips, Profile
└── providers/
    └── auth_provider.dart            # Nhost auth state, currentUser, signIn/Out/Up
```

### Key Files Detail

#### `main.dart`
- Initializes Nhost client
- Wraps app in `MultiProvider` (AuthProvider)
- Routes to Login or MainNavigation based on auth state

#### `core/config/nhost_config.dart`
```dart
class NhostConfig {
  static final NhostClient client = NhostClient(
    subdomain: Subdomain(subdomain: 'qxybjyshkyipgvgnasrk', region: 'ap-southeast-1'),
  );
  static String get graphqlEndpoint => 'https://qxybjyshkyipgvgnasrk.hasura.ap-southeast-1.nhost.run/v1/graphql';
  static String get authEndpoint => 'https://qxybjyshkyipgvgnasrk.auth.ap-southeast-1.nhost.run/v1/auth';
  static String get storageEndpoint => 'https://qxybjyshkyipgvgnasrk.storage.ap-southeast-1.nhost.run/v1/storage';
}
```

#### `providers/auth_provider.dart`
```dart
class AuthProvider extends ChangeNotifier {
  User? get currentUser => NhostConfig.client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;
  
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password, String displayName);
  Future<void> signOut();
}
```

#### `core/services/profile_service.dart`
- **`getInterestTags()`**: Queries `interest_tags` table
- **`createProfile(...)`**: Inserts user data into:
  - `public.users` (with email, display_name, bio, DOB, gender)
  - `user_personality` (5 trait scores)
  - `user_preferences` (budget, goals, group size)
  - `user_interests` (selected tag IDs)
  - `user_photos` (optional photo URL from storage)

#### `core/services/table_service.dart`
- **`getMapReadyTables(userLat, userLng, radiusKm)`**:
  - Queries `map_ready_tables` view via GraphQL
  - Returns all active tables with host vibe data
  - Optional client-side distance filtering using Haversine formula

#### `core/services/matching_service.dart`
- **`calculateMatch(currentUser, table)`** returns:
  - `score` (0.0-1.0): Weighted compatibility
    - 40% personality (Euclidean distance on Big 5)
    - 30% interests (overlap count)
    - 20% budget fit (range overlap check)
    - 10% goal alignment
  - `label`: "Perfect Match", "Great Vibe", "Good Fit", "Worth Exploring"
  - `color`: Hex color for UI (#00FFD1, #FFB800, #8B5CF6, #6B7280)
  - `glowIntensity`: 0.0-1.0 for marker halo effect
  - `shouldPulse`: Boolean (true if score >= 0.6)

#### `features/profile/screens/profile_setup_screen.dart`
5-step PageView wizard:

**Step 1: Photo Upload**
- `_pickPhoto()`: Opens `image_picker` gallery
- `_uploadPhoto()`: Uploads to Nhost storage bucket `profile-photos`
- Optional: skip and add later
- UI: Circular preview with tap-to-select, blue info card

**Step 2: Basics**
- Bio (TextField, 3 lines, max TBD)
- Date of Birth (DatePicker)
- Gender Identity (Dropdown: Male, Female, Non-binary, Prefer not to say, Other)

**Step 3: Vibe Check (Personality Assessment)**
- 10 multiple-choice questions, 3 options each (scores 1, 3, 5)
- Questions map to Big 5 traits:
  - Questions 1, 6, 9 → Extraversion
  - Questions 2, 7 → Openness
  - Questions 3, 8 → Conscientiousness
  - Question 4 → Agreeableness
  - Questions 5, 10 → Neuroticism
- `_calculatePersonalityScores()`: Averages answers per trait, returns integers 1-5
- UI: Question cards with emoji-enhanced options, black selection styling

**Step 4: Interests**
- Fetches all `interest_tags` via `ProfileService.getInterestTags()`
- Displays as grid of tappable chips
- Users select multiple interests
- Saves to `user_interests` junction table

**Step 5: Preferences**
- Budget range slider (min/max)
- Primary goal (friends/romance/casual)
- Future: group size, meetup mode, gender preference

**Completion**: 
- Calls `ProfileService.createProfile()` with all collected data
- Navigates to `MainNavigationScreen`

#### `features/home/screens/main_navigation_screen.dart`
Bottom nav with 5 tabs:
1. **Feed** (placeholder)
2. **Map** → `MapScreen`
3. **Host** (center button, larger icon) - Future: "Let BiteMates plan it" flow
4. **Trips** (placeholder)
5. **Profile** (placeholder)

Uses `IndexedStack` to preserve state when switching tabs.

#### `features/map/screens/map_screen.dart`
- Mapbox dark theme
- Center: New York (placeholder)
- `_addProfileMarkers()`: Creates sample circle markers
- Future: Wire to `TableService.getMapReadyTables()` and render actual table hosts

---

## Hasura Permissions (IMPLEMENTED)

All permissions set manually via Hasura Console for `user` role.

### `public.users` (tracked as `public_users` to avoid conflict with auth.users)
**Custom GraphQL root fields**: All operations prefixed with `public_users_*`

**Select**: Row check `true` (all users can see each other)
**Insert**: 
- Row check: `{"id":{"_eq":"X-Hasura-User-Id"}}`
- Columns: `id`, `email`, `display_name`, `bio`, `date_of_birth`, `gender_identity`
- Column preset: `id` = `X-Hasura-User-Id`
**Update**:
- Row check: `{"id":{"_eq":"X-Hasura-User-Id"}}`
- Columns: `bio`, `date_of_birth`, `gender_identity`

### `interest_tags`
**Select**: Row check `true` (public data)

### `user_personality`
**Select**: Row check `true` (needed for matching)
**Insert/Update/Delete**: Row check `{"user_id":{"_eq":"X-Hasura-User-Id"}}`
- Column preset on insert: `user_id` = `X-Hasura-User-Id`

### `user_preferences`
**Select**: Row check `{"user_id":{"_eq":"X-Hasura-User-Id"}}` (own data only)
**Insert/Update/Delete**: Same as above
- Column preset on insert: `user_id` = `X-Hasura-User-Id`

### `user_interests`
**Select**: Row check `true` (needed for matching/discovery)
**Insert/Delete**: Row check `{"user_id":{"_eq":"X-Hasura-User-Id"}}`
- Column preset on insert: `user_id` = `X-Hasura-User-Id`

### `user_photos`
**Select**: Row check:
```json
{
  "_or": [
    {"user_id":{"_eq":"X-Hasura-User-Id"}},
    {"is_primary":{"_eq":true}}
  ]
}
```
(Users see own photos + primary photos of others)

**Insert**: 
- Row check: `{"user_id":{"_eq":"X-Hasura-User-Id"}}`
- Columns: `photo_url`, `is_primary`, `display_order`
- Column preset: `user_id` = `X-Hasura-User-Id`
**Update**: Row check `{"user_id":{"_eq":"X-Hasura-User-Id"}}`
- Columns: `is_primary`, `display_order`
**Delete**: Row check `{"user_id":{"_eq":"X-Hasura-User-Id"}}`

### `map_ready_tables` (view)
**Select**: Row check `true` (public discovery view)
- All columns accessible

### Storage Permissions (Future)
Files in `profile-photos` bucket:
- Users can upload their own photos
- Users can view any photo (for map markers)
- Users can only delete their own photos

---

## Authentication Flow (IMPLEMENTED)

### Sign Up Flow
1. User enters email, password, display name on `SignupScreen`
2. `AuthProvider.signUp()` calls `NhostConfig.client.auth.signUp()`
3. Nhost creates user in `auth.users` table
4. **Email verification required** (set in `nhost.toml`)
5. User receives verification email, clicks link
6. User returns to app, logs in
7. Redirects to `ProfileSetupScreen`

### Sign In Flow
1. User enters email/password on `LoginScreen`
2. `AuthProvider.signIn()` calls `NhostConfig.client.auth.signInEmailPassword()`
3. Nhost returns JWT access token
4. Token stored automatically by Nhost SDK
5. `AuthProvider` notifies listeners
6. App checks if profile complete:
   - If no profile → `ProfileSetupScreen`
   - If profile exists → `MainNavigationScreen`

### Profile Setup Flow
See "Step-by-step" under ProfileSetupScreen above.

### Session Management
- Access token expires: 15 minutes (900 seconds)
- Refresh token expires: 30 days (2,592,000 seconds)
- Nhost SDK auto-refreshes tokens
- On refresh failure → redirects to Login

### Sign Out
- `AuthProvider.signOut()` calls `NhostConfig.client.auth.signOut()`
- Clears tokens from secure storage
- Navigates to `LoginScreen`

---

## Smart Map Discovery (PLANNED - Next Phase)

### Marker System Design
**Profile Photo Markers**:
- Circular avatar cropped from `user_photos.photo_url` (primary photo)
- Halo color indicates match compatibility:
  - **Neon Teal (#00FFD1)**: 80-100% match (full glow)
  - **Amber (#FFB800)**: 60-79% match (medium glow)
  - **Purple (#8B5CF6)**: 40-59% match (subtle glow)
  - **Gray (#6B7280)**: 0-39% match (no glow)
- Pulse animation for scores >= 60%
- Drop shadow for depth
- Caption bubble below: "Amanda • Coffee ☕"

**Clustering** (when many markers overlap):
- Show stacked avatars (top 3 faces)
- Count badge: "+5 more"

**Marker Data Flow**:
1. `MapScreen` calls `TableService.getMapReadyTables(userLat, userLng, 10km)`
2. Receives list of tables with host personality scores
3. For each table:
   - Fetch host primary photo URL
   - Pass current user + table to `MatchingService.calculateMatch()`
   - Get match score, color, glow intensity
4. Create Mapbox `PointAnnotation` with:
   - Circular image from photo URL
   - Custom halo layer with color & opacity
   - Position at `table.location_lat/lng`
5. On tap → open bottom sheet with table details

**Bottom Sheet UI**:
- Host photo + name + trust score
- Match score badge: "87% Creative Match"
- Table details: venue, time, seats left, activity type
- Shared interests tags (intersection)
- Buttons: "Request Seat" / "Ping Host"

### "Let BiteMates Plan It" Flow
Center button in bottom nav triggers guided modal:

**Step 1: Mood Selector**
- Slider: "Chill chat" ↔ "High-energy night"
- Quick presets: Coffee chat, Dinner party, Adventure night

**Step 2: Group Size**
- Slider: 2-6 people
- Quick presets: Duo (2), Small (3-4), Group (5-6)

**Step 3: Timing**
- Radio: Today, Tomorrow, This Weekend, Custom date

**Step 4: Budget**
- Slider: $ to $$$$
- Uses user's saved preferences as default

**Submit → Matching Logic**:
1. Check if existing table matches criteria (location, time, seats, vibe)
2. If match found:
   - Show table details
   - "We found your vibe!" animation
   - Auto-request to join (or auto-join if approval not required)
3. If no match:
   - "Let's create your table!" screen
   - Pre-fill form with selected criteria
   - Suggest nearby venues (Google Places API)
   - User confirms → table created
   - Added to `matching_queue` to fill remaining seats

---

## Implementation Status & Roadmap

### ✅ PHASE 1: COMPLETE - Foundation & Authentication
**Goal**: User can sign up, complete profile, and access main navigation

**Completed**:
- [x] Nhost project configured (region: ap-southeast-1)
- [x] Database schema created (all 20+ tables)
- [x] Storage bucket `profile-photos` created
- [x] All Hasura permissions set for `user` role
- [x] Flutter app structure scaffolded
- [x] Theme configuration (`AppTheme`)
- [x] Auth flow: Login, Signup, Session management
- [x] Profile setup wizard (5 steps):
  - [x] Photo upload with `image_picker`
  - [x] Basics (bio, DOB, gender)
  - [x] Vibe Check (10 questions → Big 5 traits)
  - [x] Interests (50+ tags across 9 categories)
  - [x] Preferences (budget, goals)
- [x] GraphQL services:
  - [x] `ProfileService`: getInterestTags, createProfile
  - [x] `TableService`: getMapReadyTables (with distance filter)
  - [x] `MatchingService`: calculateMatch algorithm
- [x] Main navigation with 5 tabs
- [x] Mapbox map initialized with placeholder markers

**Known Issues**:
- None currently

---

### 🚧 PHASE 2: IN PROGRESS - Smart Map Discovery
**Goal**: Users see real tables on map with photo markers and match-based glows

**To Do**:
- [ ] Create marker widget from profile photos
  - [ ] Fetch host primary photo from `user_photos`
  - [ ] Circular crop with border
  - [ ] Add colored halo based on match score
  - [ ] Caption bubble with name + activity icon
- [ ] Wire map to live data
  - [ ] Call `TableService.getMapReadyTables()` on map load
  - [ ] Calculate match scores for each table
  - [ ] Render markers at table locations
  - [ ] Handle clustering when markers overlap
- [ ] Implement bottom sheet
  - [ ] Show on marker tap
  - [ ] Display table details + host info
  - [ ] Show match score and shared interests
  - [ ] "Request Seat" / "View Chat" buttons
- [ ] Add map controls
  - [ ] Current location button
  - [ ] Filter chips (activity type, time, price)
  - [ ] Refresh button

**Blockers**: None

---

### 📋 PHASE 3: PLANNED - Table Creation & Management
**Goal**: Users can create and manage their own tables

**Features**:
- [ ] Create table form
  - [ ] Location picker (current, search, map pin)
  - [ ] Date/time selector
  - [ ] Activity type dropdown
  - [ ] Venue name/address (Google Places autocomplete)
  - [ ] Description field
  - [ ] Budget range
  - [ ] Max capacity slider
  - [ ] Approval mode toggle
- [ ] GraphQL mutations
  - [ ] `createTable` → inserts into `tables`
  - [ ] Auto-generate H3 indices via trigger
  - [ ] Create Ably channel ID
- [ ] Host dashboard
  - [ ] View pending join requests
  - [ ] Approve/decline members
  - [ ] Edit table details
  - [ ] Cancel table
  - [ ] Send group message
- [ ] Join flow
  - [ ] "Request Seat" button
  - [ ] Insert into `table_members` with status=pending
  - [ ] Notification to host
  - [ ] Auto-join if `requires_approval = false`

**Dependencies**: Phase 2 complete

---

### 📋 PHASE 4: PLANNED - "Let BiteMates Plan It" Auto-Match
**Goal**: Center nav button opens wizard to auto-match or create table

**Features**:
- [ ] Wizard modal (4 steps)
  - [ ] Mood selector
  - [ ] Group size
  - [ ] Timing
  - [ ] Budget confirmation
- [ ] Matching algorithm
  - [ ] Query `map_ready_tables` with filters
  - [ ] Calculate compatibility scores
  - [ ] Sort by score + distance
  - [ ] Present top 3 matches
- [ ] Auto-create flow
  - [ ] If no matches found
  - [ ] Suggest venues via Google Places
  - [ ] Pre-fill form with wizard selections
  - [ ] Add to `matching_queue` to auto-fill seats
- [ ] Queue matching logic
  - [ ] Background job (Nhost function?)
  - [ ] Pair users in queue with similar criteria
  - [ ] Notify all when table fills

**Dependencies**: Phase 3 complete

---

### 📋 PHASE 5: PLANNED - Real-Time Chat (Ably)
**Goal**: Group chat for table coordination

**Features**:
- [ ] Integrate Ably SDK
  - [ ] Initialize client with user key
  - [ ] Subscribe to `table:{id}:chat` channel
- [ ] Chat screen UI
  - [ ] Message list (reverse chronological)
  - [ ] Input bar with send button
  - [ ] Typing indicators
  - [ ] Member list sidebar
  - [ ] Online/offline presence badges
- [ ] Message mutations
  - [ ] Insert into `messages` table
  - [ ] Publish to Ably channel
  - [ ] Store `ably_message_id` for deduplication
- [ ] Read receipts
  - [ ] Insert into `message_reads` on view
  - [ ] Show checkmarks in chat
- [ ] Push notifications
  - [ ] FCM integration
  - [ ] Trigger on new message when user offline
  - [ ] Deep link to chat screen

**Dependencies**: Phase 3 complete

---

### 📋 PHASE 6: PLANNED - Travel Connections
**Goal**: Users can find dining partners while traveling

**Features**:
- [ ] Add travel plan form
  - [ ] Destination search (Google Places)
  - [ ] Date range picker
  - [ ] Purpose dropdown
- [ ] Travel matching
  - [ ] Query `travel_plans` by H3 res5/7 + date overlap
  - [ ] Calculate compatibility scores
  - [ ] Insert into `travel_matches`
- [ ] Travel matches list
  - [ ] Show matched travelers with scores
  - [ ] Chat button → Ably channel
  - [ ] "Meet for dinner" → create table in destination city
- [ ] Travel notifications
  - [ ] Alert when new match found
  - [ ] Reminder 3 days before trip

**Dependencies**: Phase 5 complete

---

### 📋 PHASE 7: PLANNED - Post-Meetup Ratings
**Goal**: Trust system to improve matching quality

**Features**:
- [ ] Post-meetup prompt
  - [ ] Trigger 1 hour after table ends
  - [ ] Rate each attendee (5 stars)
  - [ ] Optional text review
  - [ ] Mark no-shows
- [ ] GraphQL mutation
  - [ ] Insert into `ratings` table
  - [ ] Update `users.trust_score` via trigger
  - [ ] Increment `total_meetups_attended`
- [ ] Trust score display
  - [ ] Show on user profiles
  - [ ] Badge for high-trust users
  - [ ] Filter low-trust from matching
- [ ] Reputation effects
  - [ ] Boost high-trust users in matching
  - [ ] Limit low-trust users (e.g., max 1 table/week)
  - [ ] Auto-suspend if trust < 20

**Dependencies**: Phase 5 complete

---

### 📋 PHASE 8: PLANNED - Safety & Moderation
**Goal**: Block/report system for bad actors

**Features**:
- [ ] Block functionality
  - [ ] Block button on user profiles
  - [ ] Insert into `blocks` table
  - [ ] Filter blocked users from map/search
- [ ] Report system
  - [ ] Report button with reason dropdown
  - [ ] Insert into `reports` table
  - [ ] Admin dashboard (Nhost Console)
- [ ] Content moderation
  - [ ] Profanity filter on bios/messages
  - [ ] Auto-flag suspicious behavior
  - [ ] Manual review queue
- [ ] Account actions
  - [ ] Suspend users (set status=suspended)
  - [ ] Ban users (set status=banned)
  - [ ] Appeal process

**Dependencies**: Phase 7 complete

---

### 📋 PHASE 9: PLANNED - Polish & Testing
**Goal**: Production-ready quality

**Features**:
- [ ] Error handling
  - [ ] Network error screens
  - [ ] Retry logic
  - [ ] Offline mode (cache recent tables)
- [ ] Loading states
  - [ ] Skeleton screens
  - [ ] Shimmer effects
  - [ ] Progress indicators
- [ ] Animations
  - [ ] Page transitions
  - [ ] Marker appear/disappear
  - [ ] Bottom sheet slide
  - [ ] Button press feedback
- [ ] Accessibility
  - [ ] Screen reader labels
  - [ ] High contrast mode
  - [ ] Font scaling support
- [ ] Testing
  - [ ] Unit tests for services
  - [ ] Widget tests for screens
  - [ ] Integration tests for flows

**Dependencies**: All phases complete

---

### 📋 PHASE 10: PLANNED - Launch Prep
**Goal**: Submit to app stores

**Features**:
- [ ] App store assets
  - [ ] Icon (1024x1024)
  - [ ] Screenshots (all device sizes)
  - [ ] Feature graphic
  - [ ] Store description
- [ ] Legal documents
  - [ ] Privacy policy
  - [ ] Terms of service
  - [ ] Community guidelines
- [ ] Analytics
  - [ ] Firebase Analytics
  - [ ] Mixpanel or Amplitude
  - [ ] Event tracking
- [ ] Marketing site
  - [ ] Landing page
  - [ ] Features list
  - [ ] FAQ
  - [ ] Contact form
- [ ] Beta testing
  - [ ] TestFlight (iOS)
  - [ ] Google Play Console (Android)
  - [ ] Feedback collection

**Dependencies**: Phase 9 complete

---

## Design System

### Visual Identity
- Modern, friendly, approachable aesthetic
- Food-focused iconography and imagery
- Warm color palette (oranges, reds, yellows)
- Clean typography with Google Fonts
- Subtle shadows and depth for card elements

### Material Design 3 Theme
- Seed color: Warm orange/coral
- Light and dark mode support
- Custom component theming:
  - Cards with elevation
  - Rounded buttons
  - Floating Action Button for "Create Table"
  - Bottom navigation for main sections

### Key Screens
1. **Map View** (Home)
   - Full-screen Mapbox map
   - Floating search bar
   - Create Table FAB
   - Bottom sheet for pin details
   
2. **My Tables**
   - List of joined/hosted tables
   - Tabs: Upcoming, Past
   - Quick access to chat
   
3. **Travel Connections**
   - Upcoming trips
   - Matched travelers
   - Add new trip
   
4. **Profile**
   - User info & stats
   - Trust score & ratings
   - Settings & preferences
   
5. **Chat**
   - Group message thread
   - Member list sidebar
   - Media sharing

### Accessibility
- High contrast ratios (WCAG AA compliant)
- Screen reader support
- Large tap targets (min 48x48dp)
- Alternative text for images
- Keyboard navigation for web

---

## Current Implementation Status

### Phase: Initial Setup
- ✅ Flutter project initialized
- ✅ Project structure created
- ⏳ Dependencies not yet added
- ⏳ Backend not configured
- ⏳ No features implemented yet

---

## Development Roadmap

### Phase 1: Foundation (Current Plan)
**Goal:** Set up core infrastructure and basic app skeleton

#### Step 1: Project Configuration
- [ ] Update `pubspec.yaml` with project branding
  - Change name from "myapp" to "bitemates"
  - Update description
  - Add version and build info

#### Step 2: Dependencies Installation
- [ ] Add core packages:
  - `provider` - State management
  - `http` or `graphql_flutter` - API communication
  - `nhost_flutter_auth` - Nhost authentication
  - `nhost_graphql_adapter` - Nhost GraphQL integration
  - `mapbox_maps_flutter` - Mapbox SDK
  - `ably_flutter` - Real-time messaging
  - `h3_dart` - Geospatial indexing
  - `google_fonts` - Typography
  - `shared_preferences` - Local storage
  - `flutter_secure_storage` - Secure token storage
  - `image_picker` - Profile photos
  - `permission_handler` - Location permissions
  - `geolocator` - GPS access
  - `intl` - Date/time formatting

#### Step 3: Project Structure
- [ ] Create folder structure:
  ```
  lib/
    ├── main.dart
    ├── app.dart (MaterialApp setup)
    ├── core/
    │   ├── config/
    │   ├── constants/
    │   ├── theme/
    │   └── utils/
    ├── features/
    │   ├── auth/
    │   ├── map/
    │   ├── tables/
    │   ├── chat/
    │   ├── profile/
    │   └── travel/
    ├── shared/
    │   ├── models/
    │   ├── widgets/
    │   └── services/
    └── providers/
  ```

#### Step 4: Theme Setup
- [ ] Create Material Design 3 theme
- [ ] Implement light/dark mode with Provider
- [ ] Configure Google Fonts
- [ ] Define color schemes
- [ ] Create custom component themes

#### Step 5: Backend Configuration
- [ ] Set up Nhost project
- [ ] Configure database schema in Nhost console
- [ ] Enable h3-pg extension in Postgres
- [ ] Set up GraphQL permissions
- [ ] Create initial tables (users, meetups, messages, ratings)

#### Step 6: Service Layer Foundation
- [ ] Create Nhost service wrapper
- [ ] Create Ably service wrapper
- [ ] Create H3 utility functions
- [ ] Create location service
- [ ] Set up error handling and logging

#### Step 7: Authentication Flow
- [ ] Design auth UI screens (login, signup, verification)
- [ ] Implement Nhost auth integration
- [ ] Add auth state management with Provider
- [ ] Create protected route wrapper
- [ ] Add token refresh logic

#### Step 8: Basic Navigation
- [ ] Implement bottom navigation bar
- [ ] Create placeholder screens for main sections
- [ ] Add basic routing structure
- [ ] Set up splash screen

---

### Phase 2: Core Map Experience
- Mapbox integration
- H3-based meetup discovery
- Pin rendering and clustering
- Location permissions
- Map controls and interactions

### Phase 3: Table Creation & Management
- Create table form and validation
- H3 indexing on table creation
- GraphQL mutations for CRUD operations
- Real-time table updates via Ably
- Host controls UI

### Phase 4: Matching & Joining
- Matching algorithm implementation
- Join table flow
- Approval system (if required)
- Member management
- Notifications

### Phase 5: Real-time Chat
- Ably chat integration
- Message UI components
- Presence tracking
- Push notifications
- Media sharing

### Phase 6: Travel Features
- Add travel plans UI
- Destination matching logic
- Travel-specific chat rooms
- Trip management

### Phase 7: Trust & Safety
- Rating system after meetups
- No-show tracking
- Report/block functionality
- Trust score calculation
- Verification flows

### Phase 8: Polish & Optimization
- Performance tuning
- Animation and micro-interactions
- Error handling improvements
- Offline support
- Analytics integration

### Phase 9: Testing & Launch Prep
- Unit tests for core logic
- Integration tests
- User acceptance testing
- App store assets
- Privacy policy & terms

---

## Open Questions & Decisions Needed

1. **Personality Matching Algorithm**
   - What personality framework? (Big Five, MBTI, custom quiz?)
   - How heavily weight personality vs. location/interests?

2. **Table Capacity**
   - Min/max group sizes?
   - What happens if someone doesn't show up?

3. **Monetization**
   - Free tier limitations?
   - Premium features?
   - Business model?

4. **Content Moderation**
   - Automated filtering?
   - Manual review process?
   - Community guidelines enforcement?

5. **Notification Strategy**
   - How often to notify users about new nearby tables?
   - Quiet hours?
   - Customization options?

---

## Notes & Considerations

- Keep UI simple and intuitive - reduce friction to joining
- Privacy-first approach with H3 and minimal data collection
- Real-time features should feel instant (< 100ms perceived latency)
- Graceful degradation when offline or in poor connectivity
- Consider push notification limits and user preferences
- Plan for horizontal scaling as user base grows
- Monitor H3 query performance and adjust resolution if needed
- Build trust system carefully to prevent gaming/abuse

---

## Testing Strategy

### Current Coverage
**Status**: No tests written yet (Phase 1-2 focused on implementation)

**Planned Approach**:

#### Unit Tests (`test/unit/`)
- **Services** (`*_service_test.dart`):
  - `ProfileService`: Mock GraphQL responses, test createProfile with/without photo
  - `TableService`: Test distance calculation, H3 filtering
  - `MatchingService`: Test score calculation with various inputs
- **Utils** (`*_util_test.dart`):
  - Date formatting helpers
  - Distance calculations (Haversine)
  - Validation functions
- **Target Coverage**: 80%+

#### Widget Tests (`test/widgets/`)
- **Screens** (`*_screen_test.dart`):
  - `ProfileSetupScreen`: Test navigation between steps, form validation
  - `MapScreen`: Test marker rendering, bottom sheet opening
  - `LoginScreen`: Test input validation, error states
- **Components** (`*_test.dart`):
  - Custom buttons, cards, input fields
  - Test loading/error/success states
- **Target Coverage**: 70%+

#### Integration Tests (`integration_test/`)
- **User Flows** (`*_flow_test.dart`):
  - `auth_flow_test.dart`: Sign up → verify → profile setup → login
  - `table_flow_test.dart`: Create table → join → chat → rate
  - `matching_flow_test.dart`: "Let BiteMates Plan It" wizard → auto-match
- **Mocking Strategy**:
  - Mock Nhost backend with test fixtures
  - Use test database with seeded data
  - Mock location services
- **Target Coverage**: Key flows only (5-10 tests)

---

## Deployment Configuration

### Development Environment
**Status**: ACTIVE (current working environment)

- **Backend**: Nhost cloud (subdomain: qxybjyshkyipgvgnasrk)
  - Database: PostgreSQL 14.18 (ap-southeast-1)
  - Hasura: v2.48.5-ce
  - Storage: v0.9.1
  - Auth: v0.43.0
- **Frontend**: Local Flutter dev server
  - Hot reload enabled
  - Debug mode
  - Android emulator + iOS simulator
- **API Keys**:
  - Mapbox: (stored in `.env`, not committed)
  - Ably: (not yet configured)

### Staging Environment (Planned)
- Separate Nhost project (`bitemates-staging`)
- Seeded with test data
- Connected to TestFlight/Google Play Internal Testing
- Used for pre-release validation

### Production Environment (Planned)
- Separate Nhost project (`bitemates-prod`)
- Real user data
- Backup strategy: daily DB snapshots
- CDN for profile photos (Nhost Storage)
- Monitoring: Sentry for error tracking

### CI/CD Pipeline (Planned)
**Tools**: GitHub Actions or Codemagic

**Workflow**:
1. On push to `main`:
   - Run linter (`flutter analyze`)
   - Run unit tests
   - Build APK/IPA
2. On push to `staging`:
   - Deploy to TestFlight/Internal Testing
   - Run integration tests
   - Notify team
3. On git tag (`v*`):
   - Deploy to production
   - Submit to app stores
   - Create GitHub release

### Environment Variables
**File**: `.env` (not committed, template in `.env.example`)

```bash
# Nhost
NHOST_SUBDOMAIN=qxybjyshkyipgvgnasrk
NHOST_REGION=ap-southeast-1

# Mapbox
MAPBOX_ACCESS_TOKEN=pk.ey...

# Ably (future)
ABLY_API_KEY=xxx

# Sentry (future)
SENTRY_DSN=https://...
```

**Loading**: Use `flutter_dotenv` package in `main.dart`

---

## Known Issues & Technical Debt

### Current Issues
**None blocking development**

### Technical Debt
1. **Map Screen**: Still using placeholder markers instead of real data
   - **Priority**: HIGH
   - **Fix**: Wire to `TableService` and `MatchingService` (Phase 2)

2. **No Tests**: Zero test coverage currently
   - **Priority**: MEDIUM
   - **Fix**: Add unit tests for services in Phase 9

3. **Hardcoded Strings**: Some UI text not localized
   - **Priority**: LOW
   - **Fix**: Extract to `l10n` before multi-language support

4. **Error Handling**: Generic error messages, no retry logic
   - **Priority**: MEDIUM
   - **Fix**: Improve in Phase 9 (polish)

5. **No Caching**: App requires network for all data
   - **Priority**: LOW
   - **Fix**: Add Hive/SharedPreferences cache for offline mode

6. **Profile Photo Compression**: No image optimization before upload
   - **Priority**: MEDIUM
   - **Fix**: Use `flutter_image_compress` to reduce file sizes

7. **Personality Questions**: English only, not culturally adapted
   - **Priority**: LOW
   - **Fix**: Localize and adapt scenarios for different cultures

### Future Enhancements
- **AI-Powered Matching**: Use ML model to improve compatibility scores
- **Voice Messages**: Add voice notes in chat
- **Video Profiles**: Short intro videos instead of just photos
- **Event Integration**: Sync with calendar apps, Eventbrite
- **Restaurant Reservations**: Partner with OpenTable for direct booking
- **Group Payments**: Split bill feature via Stripe

---

## Key Design Decisions

### Why Big Five Personality Model?
- **Research-backed**: 50+ years of psychological research
- **Comprehensive**: Captures major personality dimensions
- **Interpretable**: Easy to explain to users
- **Actionable**: Clear patterns for matching (e.g., high openness → adventurous eaters)

### Why H3 for Location?
- **Privacy**: Hexagons hide exact coordinates
- **Scalability**: Efficient spatial queries without PostGIS overhead
- **Flexibility**: Multi-resolution (res 9 for neighborhoods, res 11 for precise matching)
- **Standard**: Used by Uber, Foursquare, others

### Why Nhost?
- **All-in-one**: Auth + DB + Storage + Functions in one platform
- **GraphQL-first**: Clean API, easy to query complex relationships
- **Self-hostable**: Can migrate to own servers if needed
- **Cost-effective**: Free tier generous for MVP

### Why Ably for Chat?
- **Reliability**: 99.999% uptime SLA
- **Scale**: Handles millions of concurrent connections
- **Features**: Presence, typing indicators, message history
- **Fallback**: HTTP streaming if WebSockets blocked

---

## Architecture Principles

1. **Privacy by Design**: H3 hexagons, presigned URLs, no location tracking
2. **Fail Gracefully**: Offline mode, retry logic, error boundaries
3. **Performance First**: Lazy loading, pagination, image compression
4. **Security by Default**: JWT auth, RLS, rate limiting
5. **User Control**: Block/report, data export, account deletion
6. **Scalability**: Stateless backend, CDN for assets, connection pooling

---

**Last Updated:** January 2025
**Version:** 0.2.0 (Phase 1 Complete - Auth & Profile Setup)
**Status:** Phase 2 In Progress - Smart Map Discovery
