# Project Handover: HangHut / BiteMates Web Team

## 🚀 Overview
**HangHut** (Mobile App: BiteMates) is a social dining and hangout platform. The mobile app (Flutter) allows users to create dining tables, join them, chat, and "vibe check" with others.
**Goal:** We are building the **Web Admin Dashboard & CRM** (hanghut.com) to manage this ecosystem.

## 🏗️ Technical Architecture
*   **Mobile App:** Flutter (iOS/Android)
*   **Web Portal:** [Insert User's Web Tech Stack, e.g., React/Next.js]
*   **Backend & Database:** **Supabase** (Shared)
    *   **PostgreSQL:** Relational Data
    *   **Supabase Auth:** User Management
    *   **Supabase Storage:** Images/Assets
    *   **Edge Functions:** (Future use)

> [!IMPORTANT]
> The Web portal must connect to the **SAME Supabase Project** as the mobile app. Creating a new project will fragment the data.

## 🗄️ Database Schema (Key Tables)
The database uses standard PostgreSQL with Row Level Security (RLS).

### 1. User & Profiles
*   `auth.users`: Managed by Supabase Auth (Email/Pass, Social Login).
*   `public.users`: Public profile data.
    *   `id` (UUID, PK, References `auth.users`)
    *   `display_name`, `bio`, `date_of_birth` (Strict 18+), `gender_identity`, `trust_score`.
*   `public.user_photos`: User avatars.
*   `public.user_personality`: Personality quiz results (Big 5 traits).
*   `public.user_interests`: Tags/Interests.

### 2. Dining Tables (The Core "Event")
*   `public.tables`: The events themselves.
    *   `host_id`: Creator.
    *   `location_name`, `latitude`, `longitude`.
    *   `datetime`, `status` ('open', 'full', 'cancelled').
*   `public.table_participants`: Who has joined a table.
    *   `status`: 'pending', 'confirmed', 'declined'.
*   `public.messages`: Chat messages within a table group.

### 3. Safety & Moderation (Priority for Admin)
*   `public.reports`: User reports against other users or content.
    *   `reporter_id`: Who filed it.
    *   `reported_id`: Who/What is reported.
    *   `reason`: e.g., 'harassment', 'spam'.
    *   `status`: 'pending', 'investigating', 'resolved'.
    *   `screenshot_url`: Evidence.

## 🔐 Auth & Admin Strategy
See `admin_crm_plan.md` for the detailed roadmap.
1.  **Shared Auth:** Admins log in using the same Supabase Auth system.
2.  **Roles:** We will implement an `is_admin` flag or Role-Based Access Control (RBAC) in Postgres RLS policies.
    *   *Current State:* All users have basic read/write access to their own data.
    *   *Admin State:* Admins will bypass RLS to view all Reports and Users.

## 🛠️ Key Features Built (Mobile)
*   **Registration:** Multi-step demographics, strictly 18+, Country Picker.
*   **Map Interface:** 3D Mapbox integration showing Tables.
*   **Social:** "Vibe Check" matching algorithm, Group Chat.
*   **Reporting:** User-initiated reports with categories and screenshot uploads.

## 📦 Assets & Resources
*   **Supabase Project URL:** `[Get from User/Env]`
*   **Supabase Anon Key:** `[Get from User/Env]`
*   **Design Assets:** [Link to Figma/Assets if available]
*   **Admin Plan:** `admin_crm_plan.md` (See Artifacts)

## ⚠️ Critical Handover Notes
*   **Do not modify the Auth schema:** `auth.users` is managed internally by Supabase.
*   **RLS is Active:** If the web app returns "0 rows" for a query, it likely means an RLS policy is blocking access, not that the data is missing. Admins will need specific Policies to view data.
*   **Data Integrity:** The mobile app relies on specific constraints (e.g., age limit, table status). The web admin tools must respect these constraints when editing data.
