# Changelog

All notable changes to this project are documented in this file.

## [1.2.1+37]

### Added
- feat(auth): new animated Welcome screen shown before login/signup — playful drifting map motif, glassmorphism CTA panel
- feat(auth): Apple Sign-In added alongside Google on the Welcome screen
- feat(map): coach mark tour for map-screen controls (filter chips, location button, nearby button), chained after the navbar tour
- feat(events): server-driven event category taxonomy — 16 categories with emoji, read from `event_categories` lookup table instead of hardcoded lists (Map + Discover filters both cut over)
- feat(explore): restructured Explore tabs to Discover / My Tickets / My Hangouts — Experiences merged into My Tickets behind a segmented Tickets/Experiences toggle

### Fixed
- fix(hangouts): "Open Chat" button after joining a hangout no longer silently fails (stale `BuildContext` from premature `Navigator.pop`)
- fix(tickets): My Tickets now displays seat number, section, and tier — `get_user_tickets` RPC was never returning `seat_info`/`tier` despite the data existing
- fix(host): organizer earnings now correctly subtract the Xendit processing fee from `organizer_payout` (previously overstated "Total Earned" and per-booking net)
- fix(host): payout withdrawal now reads the real Xendit sub-wallet balance instead of summing the transactions ledger (previously could allow requesting more than actually available)
- fix(scanner): ticket scan_ticket RPC was fully broken for all scanners (including owners) due to a `partner_role` enum mismatch on the `cashier` role — resolved server-side
- fix(search): result dates now show the year when it isn't the current year, so far-future/past items no longer look identical to recent ones
- fix(profile-setup): keyboard from the About step no longer stays stuck open through the Interests step — now dismisses on page change and on tap-outside

### Removed
- chore(profile): removed the XP/Level progress bar from the profile screen (and its now-unused gamification stats fetch)
- chore(feed): removed the Stories filter pill from the Feed header; shrunk filter/search/notification icons

### Chore
- chore(version): bumped to 1.2.1+37 (1.2.0 already approved on the App Store; Apple requires a strictly higher marketing version)
