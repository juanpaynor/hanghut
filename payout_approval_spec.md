# Edge Function Specification: `approve-payout`

**Status**: Proposed
**Owner**: Web/Admin Team
**Consumer**: Admin Dashboard

## Context
The Admin Dashboard needs to approve payout requests. Currently, the Web App cannot store `XENDIT_SECRET_KEY` for security reasons. All money-movement logic must reside in Supabase Edge Functions.

## Function Definition

**Function Name**: `approve-payout`

### Authorization
- **Requires Auth**: Yes (JWT)
- **Role Required**: Admin (Service Role execution or `is_admin` check inside function)

### Request Payload (POST)
```json
{
  "payout_id": "uuid-string"
}
```

### Logic
1. **Validate User**: Ensure caller is an authenticated Admin.
2. **Fetch Payout**: SELECT * FROM payouts WHERE id = payout_id.
   - Verify status is 'pending_request'.
   - Verify `bank_account_number`, `amount` etc. are present.
3. **Resolve Bank Code**:
   - If `bank_name` is a valid Xendit Bank Code (e.g. 'PH_BDO'), use it.
   - If `bank_name` is a Name, attempt to map it (or fail).
4. **Execute Xendit Payout**:
   - Call Xendit API `/v2/payouts` using `XENDIT_SECRET_KEY`.
   - Payload:
     - `external_id`: `payout_id`
     - `amount`: `payout.amount`
     - `channel_code`: `bank_code`
     - `account_number`: `payout.bank_account_number`
     - `account_holder_name`: `payout.bank_account_name`
     - `description`: "Approved Payout for {business_name}"
5. **Update Database**:
   - UPDATE payouts SET:
     - `status` = 'processing'
     - `processed_at` = NOW()
     - `approved_by` = caller_id
     - `approved_at` = NOW()
     - `xendit_external_id` = response.external_id
     - `xendit_disbursement_id` = response.id

### Response (Success)
```json
{
  "success": true,
  "data": {
    "id": "xendit-id",
    "status": "PENDING"
  }
}
```

### Response (Error)
```json
{
  "success": false,
  "error": "Error message"
}
```
