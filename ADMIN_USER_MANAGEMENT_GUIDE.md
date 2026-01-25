# User Management API - Admin Team Guide

**Date:** January 17, 2026  
**Status:** ✅ Production Ready  
**Project:** HangHut Mobile App

---

## Overview

Three new Edge Functions have been deployed to enable user management from the admin panel. These functions allow you to:

1. **Ban/Suspend/Activate** users
2. **Reset passwords** for users
3. **Delete user accounts** (soft or hard delete)

All actions are logged in the `admin_actions` audit table for compliance and tracking.

---

## Prerequisites

### 1. Make Yourself an Admin

First, you need admin privileges. Run this SQL in Supabase Dashboard → SQL Editor:

```sql
UPDATE users 
SET role = 'admin' 
WHERE email = 'your-email@example.com';
```

Replace `your-email@example.com` with your actual email address.

### 2. Get Your Admin User ID

You'll need your user ID for all API calls. Get it from Supabase Dashboard:

```sql
SELECT id FROM users WHERE email = 'your-email@example.com';
```

Save this UUID - you'll use it as `admin_id` in all requests.

---

## API Reference

### Base URL
```
https://rahhezqtkpvkialnduft.supabase.co/functions/v1
```

All endpoints require `Content-Type: application/json` header.

---

## 1. Ban/Suspend User

**Endpoint:** `POST /ban-user`

**Use Cases:**
- Ban spammers permanently
- Suspend users temporarily for review
- Reactivate previously banned/suspended users

### Request Body

```json
{
  "user_id": "uuid-of-user-to-ban",
  "action": "ban",  // Options: "ban", "suspend", "activate"
  "reason": "Spam/abuse reported by multiple users",
  "admin_id": "your-admin-uuid"
}
```

### Example: Ban a User

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/ban-user \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "action": "ban",
    "reason": "Multiple spam reports",
    "admin_id": "YOUR_ADMIN_UUID_HERE"
  }'
```

### Example: Suspend a User

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/ban-user \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "action": "suspend",
    "reason": "Under investigation",
    "admin_id": "YOUR_ADMIN_UUID_HERE"
  }'
```

### Example: Reactivate a User

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/ban-user \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "action": "activate",
    "reason": "Appeal approved",
    "admin_id": "YOUR_ADMIN_UUID_HERE"
  }'
```

### Response

```json
{
  "success": true,
  "message": "User banned successfully",
  "user_id": "123e4567-e89b-12d3-a456-426614174000",
  "new_status": "banned"
}
```

### What Happens
- User's `status` column updated to `banned`/`suspended`/`active`
- User sees `status_reason` if they try to log in
- Action logged to `admin_actions` table
- User cannot access app while banned/suspended

---

## 2. Reset Password

**Endpoint:** `POST /reset-user-password`

**Use Cases:**
- User forgot password and support ticket submitted
- User locked out of account
- Admin-initiated password reset for security reasons

### Request Body

```json
{
  "user_email": "user@example.com",
  "admin_id": "your-admin-uuid"
}
```

### Example

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/reset-user-password \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com",
    "admin_id": "YOUR_ADMIN_UUID_HERE"
  }'
```

### Response

```json
{
  "success": true,
  "message": "Password reset email sent",
  "user_email": "user@example.com"
}
```

### What Happens
- User receives password reset email from Supabase Auth
- Email contains secure reset link (expires in 1 hour)
- User can set new password via the link
- Action logged to `admin_actions` table

---

## 3. Delete User Account

**Endpoint:** `POST /delete-user-account`

**Use Cases:**
- GDPR "right to be forgotten" requests
- Remove spam/bot accounts permanently
- Soft delete for record keeping

### Request Body

```json
{
  "user_id": "uuid-of-user-to-delete",
  "admin_id": "your-admin-uuid",
  "hard_delete": false,  // true = permanent, false = soft delete
  "reason": "User requested account deletion"
}
```

### Example: Soft Delete (Recommended)

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/delete-user-account \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "admin_id": "YOUR_ADMIN_UUID_HERE",
    "hard_delete": false,
    "reason": "User requested account deletion"
  }'
```

**What Happens:**
- User status set to `deleted`
- Email changed to `deleted_{uuid}@deleted.com`
- Display name changed to "Deleted User"
- Avatar removed
- User **cannot** log in
- Data **retained** for audit/legal purposes

### Example: Hard Delete (GDPR Compliance)

```bash
curl -X POST \
  https://rahhezqtkpvkialnduft.supabase.co/functions/v1/delete-user-account \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "admin_id": "YOUR_ADMIN_UUID_HERE",
    "hard_delete": true,
    "reason": "GDPR deletion request"
  }'
```

**What Happens:**
- **Permanently deletes:**
  - User record (from `users` table)
  - All messages sent by user
  - All posts created by user
  - All events hosted by user
  - All reactions, likes, comments by user
  - All reports filed by user
  - User's Supabase Auth account
- **Cannot be undone!**

### Response

```json
{
  "success": true,
  "message": "User account permanently deleted",
  "user_id": "123e4567-e89b-12d3-a456-426614174000",
  "hard_delete": true
}
```

---

## Integration with Admin Panel

### JavaScript/TypeScript Example

```typescript
// Admin panel helper functions

const SUPABASE_FUNCTIONS_URL = 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1';
const ADMIN_ID = 'your-admin-uuid'; // Get from session/auth

async function banUser(userId: string, action: 'ban' | 'suspend' | 'activate', reason: string) {
  const response = await fetch(`${SUPABASE_FUNCTIONS_URL}/ban-user`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      user_id: userId,
      action,
      reason,
      admin_id: ADMIN_ID,
    }),
  });
  
  return response.json();
}

async function resetPassword(userEmail: string) {
  const response = await fetch(`${SUPABASE_FUNCTIONS_URL}/reset-user-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      user_email: userEmail,
      admin_id: ADMIN_ID,
    }),
  });
  
  return response.json();
}

async function deleteAccount(userId: string, hardDelete: boolean, reason: string) {
  const response = await fetch(`${SUPABASE_FUNCTIONS_URL}/delete-user-account`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      user_id: userId,
      admin_id: ADMIN_ID,
      hard_delete: hardDelete,
      reason,
    }),
  });
  
  return response.json();
}

// Usage in admin panel:
// Ban a spammer
await banUser('user-uuid', 'ban', 'Spam reported by users');

// Reset password for support ticket
await resetPassword('user@example.com');

// GDPR deletion
await deleteAccount('user-uuid', true, 'GDPR right to be forgotten');
```

---

## Audit Trail

All admin actions are logged to `admin_actions` table:

```sql
SELECT 
  aa.created_at,
  aa.action_type,
  aa.reason,
  admin.display_name as admin_name,
  target.display_name as target_user
FROM admin_actions aa
JOIN users admin ON admin.id = aa.admin_id
JOIN users target ON target.id = aa.target_user_id
ORDER BY aa.created_at DESC
LIMIT 50;
```

**Columns:**
- `id` - Unique action ID
- `admin_id` - Who performed the action
- `action_type` - ban, suspend, delete, reset_password
- `target_user_id` - User affected
- `reason` - Why it was done
- `metadata` - Additional context (JSON)
- `created_at` - Timestamp

---

## Error Handling

### Common Errors

**403 Unauthorized**
```json
{
  "error": "Unauthorized: Admin privileges required"
}
```
**Solution:** Make sure your user has `role = 'admin'` in the database.

**404 User Not Found**
```json
{
  "error": "User not found"
}
```
**Solution:** Double-check the user_id or email is correct.

**400 Missing Fields**
```json
{
  "error": "Missing required fields"
}
```
**Solution:** Ensure all required fields are provided in request body.

---

## Best Practices

### 1. Always Provide a Reason
```json
{
  "reason": "Multiple spam reports from users on 2026-01-17"
}
```
Clear reasons help with:
- User appeals
- Legal compliance
- Team communication

### 2. Use Soft Delete First
- Try soft delete before hard delete
- Gives you 30 days to reverse if needed
- Keeps data for legal/audit purposes

### 3. Verify Before Hard Delete
```sql
-- Check what will be deleted
SELECT 
  (SELECT COUNT(*) FROM posts WHERE user_id = 'user-uuid') as posts,
  (SELECT COUNT(*) FROM messages WHERE sender_id = 'user-uuid') as messages,
  (SELECT COUNT(*) FROM tables WHERE host_id = 'user-uuid') as events;
```

### 4. Monitor Audit Log
Set up weekly review of `admin_actions` table:
```sql
SELECT 
  action_type,
  COUNT(*) as count
FROM admin_actions
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY action_type;
```

---

## Security Notes

✅ **What's Secure:**
- All functions require admin role verification
- Actions are logged (cannot be hidden)
- Service role key never exposed to client
- CORS enabled for your admin panel domain

⚠️ **Important:**
- Keep admin user IDs confidential
- Monitor `admin_actions` for unauthorized use
- Rotate Supabase service role key periodically

---

## Testing

### Test Ban Function
1. Create a test user account
2. Call ban endpoint with test user's ID
3. Try logging in as test user → Should be blocked
4. Check `admin_actions` table for log entry
5. Call activate endpoint → Should work again

### Test Password Reset
1. Call reset endpoint with test user email
2. Check test user's email inbox
3. Verify reset link works
4. Check `admin_actions` table for log entry

### Test Delete (Soft)
1. Call delete endpoint with `hard_delete: false`
2. Verify user status = 'deleted'
3. Verify email changed to `deleted_*`
4. Try logging in → Should fail

---

## Support

**Questions or Issues:**
- Check Supabase Dashboard → Edge Functions → Logs
- Review `admin_actions` table for audit trail
- Check user's `status` and `status_reason` columns

**Database Access:**
- Supabase Dashboard: https://supabase.com/dashboard/project/rahhezqtkpvkialnduft
- SQL Editor for custom queries
- Table Editor for quick checks

---

## Quick Reference

| Action | Endpoint | Key Fields |
|--------|----------|------------|
| Ban user | `/ban-user` | `user_id`, `action: "ban"` |
| Suspend user | `/ban-user` | `user_id`, `action: "suspend"` |
| Activate user | `/ban-user` | `user_id`, `action: "activate"` |
| Reset password | `/reset-user-password` | `user_email` |
| Soft delete | `/delete-user-account` | `user_id`, `hard_delete: false` |
| Hard delete | `/delete-user-account` | `user_id`, `hard_delete: true` |

All actions require `admin_id` and optional `reason`.

---

**Ready to use!** 🚀

If you have questions, check the Supabase Functions logs or contact the development team.
