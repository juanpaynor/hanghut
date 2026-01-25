# 🧑‍🏫 Partner Registration Guide for Web Team

This guide details exactly how to build the Partner Registration flow for the HangHut Dashboard.

## 🚨 Critical Architecture Note

**We use a SPLIT database model:**
1.  `auth.users`: Managed by Supabase Auth (Store login credentials).
2.  `public.partners`: Our custom table (Stores business details).

**⚠️ THE RACE CONDITION:**
When a user signs up, Supabase creates an `auth.users` record. If you try to insert into `public.partners` *before* our triggers have finished setting up the `public.users` record, **IT WILL FAIL** with a Foreign Key violation.

**The Fix:**
I have implemented a synchronous SQL trigger (`on_auth_user_created`) that guarantees `public.users` exists immediately. **You do not need to do anything special** other than ensuring your DB migrations are up to date.

---

## 🛠️ Step-by-Step Implementation Flow

### 1. The Sign-Up Page (`/register`)

**Goal:** Create the account credentials first.

```typescript
// Frontend (React/Vue/etc.)
const signUp = async (email, password) => {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        role: 'partner', // IMPORTANT: Set metadata role
        display_name: 'New Partner' 
      }
    }
  });
  
  if (error) throw error;
  
  // SUCCESS: User is created in auth.users
  // SUCCESS: Trigger automatically creates public.users record
};
```

### 2. The Onboarding Wizard (`/onboarding`)

**Goal:** Collect business details and link them to the logged-in user.

**State:** User is logged in (`supabase.auth.user()`) but has no `partners` record yet.

**Field Mapping:**

| Form Field | Database Column (`partners`) | Type |
| :--- | :--- | :--- |
| Business Name | `business_name` | Text |
| Business Type | `business_type` | Text (restaurant, event_org, etc.) |
| Registration No. | `registration_number` | Text |
| Tax ID | `tax_id` | Text |
| Contact Name | `contact_name` | Text |
| Email | `email` | Text |
| Phone | `phone` | Text |
| Address | `address` | Text (Full string or JSON) |
| Bank Name | `bank_name` | Text |
| Account Name | `bank_account_name` | Text |
| Account No. | `bank_account_number` | Text |

**Document Uploads:**
Upload files to `partner-docs` bucket *before* submitting the form.

```typescript
// 1. Upload File
const { data: fileData } = await supabase.storage
  .from('partner-docs')
  .upload(`${userId}/permit.pdf`, file);

// 2. Get Public URL
const permitUrl = supabase.storage
  .from('partner-docs')
  .getPublicUrl(fileData.path).data.publicUrl;
```

### 3. Submitting the Application

**Action:** Insert row into `partners` table.

```typescript
const submitApplication = async (formData) => {
  const user = supabase.auth.user();
  
  const { error } = await supabase
    .from('partners')
    .insert({
      id: user.id, // 🔑 IMPORTANT: Partner ID = User ID
      business_name: formData.businessName,
      business_type: formData.businessType,
      registration_number: formData.regNo,
      tax_id: formData.taxId,
      contact_name: formData.contactName,
      email: formData.email, // Can be same as auth email
      phone: formData.phone,
      address: formData.address,
      bank_name: formData.bankName,
      bank_account_name: formData.accountName,
      bank_account_number: formData.accountNumber,
      
      business_permit_url: formData.permitUrl,
      valid_id_url: formData.idUrl,
      
      status: 'pending' // Default status
    });

  if (error) alert("Error submitting application: " + error.message);
};
```

---

## 🚦 Status Workflow

The `partners` table has a `status` column:

1.  **`pending`**: Default on creation. Show "Under Review" screen.
2.  **`approved`**: Admin has verified docs. Allow full dashboard access.
3.  **`rejected`**: Admin rejected. Show reason and "Resubmit" button.

### Checking Status on Login

Every time the dash loads:

```typescript
const checkStatus = async () => {
  const { data: partner } = await supabase
    .from('partners')
    .select('status')
    .eq('id', user.id)
    .single();

  if (!partner) {
    // Redirect to Onboarding
  } else if (partner.status === 'pending') {
    // Redirect to "Under Review" page
  } else if (partner.status === 'approved') {
    // Redirect to Dashboard
  }
};
```

---

## 📝 Common Pitfalls

1.  **Forgot Storage Policies:** Ensure the `partner-docs` bucket allows authenticated users to upload their own files.
2.  **Missing RLS:** The `partners` table has RLS enabled. Partners can only `INSERT` their own row and `SELECT/UPDATE` their own row. They cannot see other partners.
3.  **Email Verification:** Ideally, force email verification before allowing them to fill out the onboarding form to reduce spam.

---

## 📂 Database Schema Reference

```sql
create table public.partners (
  id uuid references public.users(id) primary key, -- 1:1 with Auth User
  business_name text not null,
  status text check (status in ('pending', 'approved', 'rejected', 'suspended')) default 'pending',
  -- ... other fields
  created_at timestamptz default now()
);
```
