# Support Tickets System - Admin Team Guide

**Date:** January 17, 2026  
**Feature:** In-App Support Appeals  
**Status:** ✅ Ready for Integration

---

## Overview

Users who are suspended or banned can now submit appeals directly from the app. These appeals are stored in the `support_tickets` table and can be reviewed/responded to from the admin panel.

---

## Database Schema

### Table: `support_tickets`

```sql
CREATE TABLE support_tickets (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  ticket_type TEXT, -- 'account_appeal', 'bug_report', 'feature_request', 'other'
  subject TEXT,
  message TEXT,
  status TEXT, -- 'open', 'in_progress', 'resolved', 'closed'
  priority TEXT, -- 'low', 'normal', 'high', 'urgent'
  
  -- User info snapshot
  user_email TEXT,
  user_display_name TEXT,
  
  -- Account status at time of ticket
  account_status TEXT, -- 'suspended', 'banned', etc.
  account_status_reason TEXT,
  
  -- Admin response
  admin_response TEXT,
  admin_id UUID REFERENCES users(id),
  resolved_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
);
```

---

## Migration Required

**File:** `create_support_tickets.sql`

Run this migration in Supabase Dashboard → SQL Editor:

```bash
# Location
/Users/rich/Documents/bitemates/supabase_migrations/create_support_tickets.sql
```

This creates:
- ✅ `support_tickets` table
- ✅ Indexes for performance
- ✅ RLS policies (users see own tickets, admins see all)
- ✅ Auto-update timestamp trigger

---

## Admin Panel Integration

### 1. Support Tickets List View

**Query to fetch all tickets:**

```sql
SELECT 
  st.id,
  st.subject,
  st.message,
  st.status,
  st.priority,
  st.ticket_type,
  st.user_display_name,
  st.user_email,
  st.account_status,
  st.account_status_reason,
  st.admin_response,
  st.created_at,
  st.updated_at,
  st.resolved_at,
  admin.display_name as admin_name
FROM support_tickets st
LEFT JOIN users admin ON admin.id = st.admin_id
ORDER BY 
  CASE st.priority
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'normal' THEN 3
    WHEN 'low' THEN 4
  END,
  st.created_at DESC;
```

**Recommended UI:**
- Table with columns: Subject, User, Status, Priority, Created
- Filter by: Status (open/in_progress/resolved/closed)
- Filter by: Type (account_appeal/bug_report/etc.)
- Sort by: Priority, Date
- Click row to view details

### 2. Ticket Detail View

**Display:**
- User info (name, email, user ID)
- Account status at time of ticket
- Original suspension/ban reason
- User's appeal message
- Timestamp
- Admin response (if any)

**Actions:**
- Update status (open → in_progress → resolved)
- Add admin response
- Approve appeal (reactivate account)
- Deny appeal (keep suspended/banned)

### 3. Responding to a Ticket

**Update ticket with admin response:**

```typescript
// Example TypeScript code for admin panel
async function respondToTicket(
  ticketId: string,
  adminId: string,
  response: string,
  newStatus: 'in_progress' | 'resolved' | 'closed'
) {
  const { error } = await supabase
    .from('support_tickets')
    .update({
      admin_response: response,
      admin_id: adminId,
      status: newStatus,
      resolved_at: newStatus === 'resolved' ? new Date().toISOString() : null,
    })
    .eq('id', ticketId);

  if (error) throw error;
}
```

### 4. Approving an Appeal (Reactivate Account)

**Steps:**
1. Review the appeal
2. If approved, reactivate the user account
3. Update ticket status to 'resolved'
4. Optionally send notification to user

**Code example:**

```typescript
async function approveAppeal(ticketId: string, userId: string, adminId: string) {
  // 1. Reactivate user account
  await supabase
    .from('users')
    .update({
      status: 'active',
      status_reason: null,
      status_changed_at: new Date().toISOString(),
      status_changed_by: adminId,
    })
    .eq('id', userId);

  // 2. Log admin action
  await supabase
    .from('admin_actions')
    .insert({
      admin_id: adminId,
      action_type: 'activate',
      target_user_id: userId,
      reason: 'Appeal approved',
    });

  // 3. Update ticket
  await supabase
    .from('support_tickets')
    .update({
      status: 'resolved',
      admin_response: 'Your appeal has been approved. Your account has been reactivated.',
      admin_id: adminId,
      resolved_at: new Date().toISOString(),
    })
    .eq('id', ticketId);
}
```

### 5. Denying an Appeal

```typescript
async function denyAppeal(ticketId: string, adminId: string, reason: string) {
  await supabase
    .from('support_tickets')
    .update({
      status: 'resolved',
      admin_response: `Appeal denied. Reason: ${reason}`,
      admin_id: adminId,
      resolved_at: new Date().toISOString(),
    })
    .eq('id', ticketId);
}
```

---

## Recommended Admin Panel UI

### Support Tickets Dashboard

```
┌─────────────────────────────────────────────────────────────┐
│ Support Tickets                                    [Filters] │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ Status: [All] [Open] [In Progress] [Resolved] [Closed]      │
│ Type:   [All] [Account Appeals] [Bug Reports] [Other]       │
│                                                               │
├──────┬──────────────┬──────────┬──────────┬──────────────────┤
│ Pri  │ Subject      │ User     │ Status   │ Created          │
├──────┼──────────────┼──────────┼──────────┼──────────────────┤
│ 🔴   │ Account BAN  │ John D.  │ Open     │ 2 hours ago      │
│ 🟠   │ Account SUS  │ Jane S.  │ Open     │ 5 hours ago      │
│ 🟢   │ Bug Report   │ Mike R.  │ Resolved │ 1 day ago        │
└──────┴──────────────┴──────────┴──────────┴──────────────────┘
```

### Ticket Detail Modal

```
┌─────────────────────────────────────────────────────────────┐
│ Ticket #abc123                                      [Close X]│
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ User: John Doe (john@example.com)                           │
│ User ID: 45543070-4a8b-4bcb-9ef0-31a27afa8fdf               │
│                                                               │
│ Account Status: SUSPENDED                                    │
│ Original Reason: "Multiple spam reports"                     │
│                                                               │
│ ─────────────────────────────────────────────────────────    │
│                                                               │
│ User's Appeal:                                               │
│ "I apologize for the spam. I was testing the app and        │
│  didn't realize I was annoying other users. I promise        │
│  to follow the community guidelines going forward."          │
│                                                               │
│ ─────────────────────────────────────────────────────────    │
│                                                               │
│ Admin Response:                                              │
│ [Text area for response]                                     │
│                                                               │
│ ─────────────────────────────────────────────────────────    │
│                                                               │
│ Actions:                                                     │
│ [Approve Appeal & Reactivate] [Deny Appeal] [Mark Resolved] │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Workflow Example

### Scenario: User Appeals Suspension

1. **User submits appeal** (from mobile app)
   - Ticket created with status = 'open'
   - Priority = 'normal' (or 'high' if banned)

2. **Admin sees ticket in dashboard**
   - Reviews user's message
   - Checks original suspension reason
   - Checks user's history (past violations, reports)

3. **Admin makes decision:**

   **Option A: Approve**
   - Click "Approve Appeal & Reactivate"
   - User's status → 'active'
   - Ticket status → 'resolved'
   - User can log back in immediately

   **Option B: Deny**
   - Click "Deny Appeal"
   - Add reason in admin response
   - Ticket status → 'resolved'
   - User remains suspended/banned

   **Option C: Need More Info**
   - Update status to 'in_progress'
   - Add response asking for clarification
   - (Future: Send notification to user)

---

## SQL Queries for Admin Panel

### Get Open Tickets Count
```sql
SELECT COUNT(*) as open_tickets
FROM support_tickets
WHERE status = 'open';
```

### Get Tickets by Status
```sql
SELECT *
FROM support_tickets
WHERE status = 'open'
ORDER BY 
  CASE priority
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'normal' THEN 3
    WHEN 'low' THEN 4
  END,
  created_at DESC;
```

### Get User's Ticket History
```sql
SELECT *
FROM support_tickets
WHERE user_id = 'user-uuid-here'
ORDER BY created_at DESC;
```

### Get Tickets Resolved by Admin
```sql
SELECT 
  st.*,
  admin.display_name as admin_name
FROM support_tickets st
JOIN users admin ON admin.id = st.admin_id
WHERE st.admin_id = 'admin-uuid-here'
  AND st.status = 'resolved'
ORDER BY st.resolved_at DESC;
```

---

## Best Practices

### 1. Response Time
- **Account appeals:** Respond within 24 hours
- **Bug reports:** Acknowledge within 48 hours
- **Feature requests:** Review weekly

### 2. Appeal Review Guidelines
- Check user's account history
- Review original suspension reason
- Look for repeat offenders
- Consider severity of violation
- Give benefit of doubt for first-time offenders

### 3. Communication
- Be professional and respectful
- Explain decisions clearly
- Provide specific reasons for denials
- Offer guidance on how to avoid future issues

### 4. Tracking
- Log all admin actions (already implemented in `admin_actions` table)
- Monitor appeal approval/denial rates
- Track repeat offenders

---

## Statistics & Reporting

### Useful Metrics to Track

```sql
-- Appeal approval rate
SELECT 
  COUNT(*) FILTER (WHERE admin_response LIKE '%approved%') as approved,
  COUNT(*) FILTER (WHERE admin_response LIKE '%denied%') as denied,
  COUNT(*) as total
FROM support_tickets
WHERE ticket_type = 'account_appeal'
  AND status = 'resolved';

-- Average response time
SELECT 
  AVG(EXTRACT(EPOCH FROM (resolved_at - created_at))/3600) as avg_hours
FROM support_tickets
WHERE status = 'resolved';

-- Tickets by type
SELECT 
  ticket_type,
  COUNT(*) as count
FROM support_tickets
GROUP BY ticket_type
ORDER BY count DESC;
```

---

## Future Enhancements

### Phase 2 (Optional)
- [ ] Email notifications when admin responds
- [ ] In-app notification for ticket updates
- [ ] Ticket comments/thread (multi-message conversation)
- [ ] Attach screenshots to appeals
- [ ] Canned responses for common scenarios
- [ ] Ticket assignment to specific admins
- [ ] SLA tracking (response time goals)

---

## Testing

### Test the Appeal Flow

1. **Suspend a test user** (via ban-user function)
2. **Log in as that user** on mobile app
3. **See suspended screen** with "Submit Appeal" button
4. **Submit an appeal** with test message
5. **Check admin panel** - ticket should appear
6. **Respond to ticket** and approve/deny
7. **Verify user status** updated correctly

---

## Support

**Questions or Issues:**
- Check `support_tickets` table in Supabase Dashboard
- Review RLS policies if permissions issues
- Check admin panel console for errors

**Database Access:**
- Supabase Dashboard: https://supabase.com/dashboard/project/rahhezqtkpvkialnduft
- Table Editor → support_tickets

---

## Quick Reference

| Action | Endpoint/Query |
|--------|----------------|
| List all tickets | `SELECT * FROM support_tickets ORDER BY created_at DESC` |
| Get open tickets | `WHERE status = 'open'` |
| Respond to ticket | `UPDATE support_tickets SET admin_response = '...', status = 'resolved'` |
| Approve appeal | Update user status to 'active' + update ticket |
| Deny appeal | Update ticket with denial reason |

---

**Ready to integrate!** 🎫

The support tickets table is created and the mobile app is ready to submit appeals. Just add the UI to your admin panel to view and respond to tickets.
