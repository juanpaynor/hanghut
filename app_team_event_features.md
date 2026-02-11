# App Team Guide: Event Features Implementation

This guide covers the implementation details for **Ticket Tiers** and **Promo Codes** in the mobile application.

---

# Part 1: Ticket Tiers

## Overview
Events can have multiple ticket tiers (e.g., General Admission, VIP, Early Bird). The mobile app must fetch and display these tiers correctly, respecting availability, pricing, and purchase limits.

## Database Schema: `ticket_tiers`

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Unique ID |
| `event_id` | UUID | References `events(id)` |
| `name` | TEXT | Display Name (e.g., "VIP Pass") |
| `description` | TEXT | Details about perks/access |
| `price` | NUMERIC | Price in PHP. `0` = Free. |
| `quantity_total` | INTEGER | Total tickets available for this tier. |
| `quantity_sold` | INTEGER | Number of tickets already sold. |
| `min_per_order` | INTEGER | Min tickets per purchase (default 1). |
| `max_per_order` | INTEGER | Max tickets per purchase. |
| `sales_start` | TIMESTAMPTZ | When sales open (Null = immediately). |
| `sales_end` | TIMESTAMPTZ | When sales close (Null = until event end). |
| `is_active` | BOOLEAN | If false, do not display. |
| `sort_order` | INTEGER | Display order (ASC). |

## Display Logic

**Query:**
```sql
SELECT * FROM ticket_tiers 
WHERE event_id = 'EVENT_ID' 
  AND is_active = TRUE 
ORDER BY sort_order ASC
```

**Availability Logic (Client-Side filter):**
1.  **Sold Out:** `quantity_sold >= quantity_total`
2.  **Not Started:** `now() < sales_start`
3.  **Ended:** `now() > sales_end`

**UI States:**
-   **Active:** User can select quantity (respecting `min_per_order` and `max_per_order`).
-   **Sold Out:** Display "Sold Out" badge, disable selection.
-   **Coming Soon:** If `sales_start` is future, show "Sale starts on [Date]".
-   **Closed:** If `sales_end` passed, show "Sales Ended".

## Checkout Logic

1.  **Validation:** Before creating a payment intent, re-validate that enough quantity remains.
    -   *Race condition warning:* Two users might buy the last ticket simultaneously. Handle error gracefully.
2.  **Inventory update:**
    -   When a ticket is successfully created, `quantity_sold` MUST be incremented.
    -   (Ideally handled by database triggers or the transaction creating the ticket).

## Fee Calculation
The `price` is the base ticket price.
-   **Platform Fee:** Typically computed on top or included, depending on partner settings.
-   **Processing Fee:** 3% + ₱15 (standard Stripe/Xendit logic).

*Ensure the user sees the breakdown before paying.*

---

# Part 2: Promo Codes

## Overview
Organizers can create promo codes for their events via the Web Dashboard. The mobile app needs to support **applying** these codes during the checkout flow.

## Database Schema: `promo_codes`

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | UUID | Unique ID |
| `event_id` | UUID | References `events(id)` |
| `code` | TEXT | The code string (e.g., "SUMMER20"). **Case-insensitive.** |
| `discount_type` | TEXT | `'percentage'` or `'fixed_amount'` |
| `discount_amount` | NUMERIC | The value (e.g., `20` for 20% or `100` for ₱100 off) |
| `usage_limit` | INTEGER | Max number of times this code can be used (global). Null = unlimited. |
| `usage_count` | INTEGER | Current number of times used. |
| `starts_at` | TIMESTAMPTZ | When the code becomes active. |
| `expires_at` | TIMESTAMPTZ | When the code expires (Null = never). |
| `is_active` | BOOLEAN | Manual toggle for enabling/disabling. |

## Application Logic

### 1. Validating a Code
When a user enters a code in the checkout screen:

**Query:**
```sql
SELECT * FROM promo_codes 
WHERE event_id = 'CURRENT_EVENT_ID' 
  AND code = 'USER_INPUT_UPPERCASE' 
  AND is_active = TRUE
```

**Checks:**
1.  **Existence:** If no record found, return "Invalid promo code".
2.  **Expiry:** (Optional) If `expires_at` is not null AND `now() > expires_at`, return "Promo code has expired".
3.  **Usage Limit:** (Optional) If `usage_limit` is not null AND `usage_count >= usage_limit`, return "Promo code usage limit reached".

### 2. Calculating Discount
Once validated, calculate the discount amount:

-   **Percentage:** `discount = subtotal * (discount_amount / 100)`
-   **Fixed Amount:** `discount = discount_amount`

**Important:** Ensure `discount` does not exceed `subtotal`. The final total cannot be negative.

### 3. Finalizing Order (Database Update)
When the payment is successful (or ticket is issued), you **MUST** increment the `usage_count`.

```sql
-- Pseudo-code for update
UPDATE promo_codes 
SET usage_count = usage_count + 1 
WHERE id = 'PROMO_CODE_ID';
```

## Checkout UI Requirements
1.  **Input Field:** "Enter Promo Code" (text input).
2.  **Apply Button:** Triggers the validation logic.
3.  **Success State:** Show the discount amount applied (e.g., "-₱100.00") and the new total.
4.  **Error State:** Show specific error messages (Invalid, Expired, Sold Out).

## Common Issues / Testing
-   **Case Sensitivity:** Always convert user input to `UPPERCASE` before querying.
-   **Rounding:** For percentage discounts, round to 2 decimal places.
