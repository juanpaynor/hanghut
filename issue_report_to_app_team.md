# Issue Report for App Team: 401 Unauthorized Block

Hi App Team,

We are still unable to complete a Guest Checkout due to a persistent **401 Unauthorized** error from the Edge Function, despite your Version 5 deployment.

### 🔴 The Issue
When calling `create-purchase-intent` as a Guest (unauthenticated user), the Edge Function immediately rejects the request with **401 Unauthorized**.

We have verified our side by **explicitly forcing the Authorization header to use the ANON KEY**:

```typescript
// Our specific test code
const headers = { 
  Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}` 
}
// Result: STILL returns 401 Unauthorized
```

### 🔍 Error Logs
```
POST https://[project-id].supabase.co/functions/v1/create-purchase-intent 401 (Unauthorized)
Edge Function returned a non-2xx status code
```

### ❓ Hypotheses & Questions
This usually means the Edge Function itself is enforcing an Auth check that fails for Guests.

1. **Verify `config.toml` / Function Configuration:**
   - Is `verify_jwt = true` set for this function? (This handles the JWT verification automatically).
   - If yes, **does the function code *also* manually check for a logged-in user?**
   - E.g., `if (!user) throw new Error('Unauthorized')` <-- This would block Guests.

2. **Verify Guest Logic:**
   - Since we are sending the **Anon Key** (which is a valid JWT), the platform level check passes.
   - The 401 is likely coming from **within your function logic**.
   - Are you mistakenly throwing 401 if `supabase.auth.getUser()` returns null?
   - **Requirement:** For Guest Checkout, `getUser()` returning null is **VALID** and should be allowed to proceed using the `guest_details` payload.

### 🧪 Request to App Team
Please check the Edge Function logs for the exact line throwing the 401. 

**Likely Culprit:**
```typescript
// if you have something like this, it breaks Guest Checkout:
const { data: { user }, error } = await supabase.auth.getUser()
if (error || !user) {
  return new Response("Unauthorized", { status: 401 }) // ❌ BLOCKS GUESTS
}
```

**Correct Logic:**
```typescript
const { data: { user } } = await supabase.auth.getUser()
// Allow if User is present OR if Guest Details are present
if (!user && !payload.guest_details) { 
  return new Response("Unauthorized - Need User or Guest Details", { status: 401 }) 
}
```

Please confirm if the function logic allows null users!

Best,
Web Team
