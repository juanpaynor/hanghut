# Admin & CRM Strategy (HangHut Web)

## 🎯 Objective
Create a web-based Admin Dashboard & CRM for **HangHut** to manage users, handle reports, and oversee platform activity. This system will connect to the **same Supabase backend** as the Flutter mobile app, ensuring a single source of truth.

## 🤝 Supabase & Web Dev Access
**Yes, you absolutely need to give the web developer access to your Supabase project.**
*   **Why?** The website and the app must share the *exact same* database (Users, Reports, Tables). If user A reports something on the app, the Admin on the web needs to see it instantly.
*   **What to give them:**
    *   **Project URL & Anon Key:** For the frontend website.
    *   **Team Access:** Invite them to the Supabase Dashboard (Settings -> Team) so they can see diagrams, logs, and manage edge functions if needed.

---

## 📅 Phased Roadmap

### Phase 1: Foundation & Security (The "Bouncer")
Before building features, we need to ensure only *actual* admins can see this data.
*   **Admin Role:** Create an `app_admin` role or a boolean `is_admin` flag in the `public.users` table.
*   **RLS Policies:** Update Database policies so that "Regular Users" can strictly *never* read the `reports` table or sensitive user data, but "Admins" have full access.
*   **Web Auth:** The web dev will implement Supabase Auth (same login system). Admins log in just like users, but get redirected to the Dashboard.

### Phase 2: Report & Issue Management (The "Judge")
This is the immediate priority for handling user issues.
*   **Report Queue:** A table view of all rows from `public.reports` (the table we just made).
*   **Status Workflow:** Admins can change status: `Open` ➝ `Investigating` ➝ `Resolved` / `Dismissed`.
*   **Actionable Context:** When viewing a report, the admin needs to see:
    *   Who reported it? (Link to Reporter Profile)
    *   Who is being reported? (Link to Reported Profile)
    *   Evidence (Screenshots/Logs).
*   **Resolution Actions:** Buttons to "Warn User", "Delete Content", or "Ban User".

### Phase 3: User CRM (The "Rolodex")
A Customer Relationship Management view to see your user base.
*   **User Directory:** Searchable list of all users. Filter by Join Date, Country, Trust Score.
*   **User Profile View:** Admin view of a specific user:
    *   Their photos, bio, details.
    *   History of tables they hosted or joined.
    *   History of reports against them (critical for banning decisions).
*   **Manual Override:** Ability to edit user details if they need help (e.g., specific support requests).

### Phase 4: Analytics & God Mode (The "Overseer")
High-level overview of app health (Future Scope).
*   **Dashboard:** Graphs showing Daily Active Users (DAU), Signups per week, Tables created.
*   **Heatmap:** Where are tables happening? (Web version of the Map).
*   **Broadcasts:** Send a push notification to ALL users (e.g., "Server maintenance in 1 hour").

## ⚠️ Key Considerations for Web Dev
1.  **Shared Types:** If they use TypeScript, they can generate types directly from your Supabase schema so the data structures match perfectly.
2.  **No Direct DB Access:** The web dashboard should interact via the Supabase Client (API), not by connecting directly to the Postgres port, to maintain security rules.
