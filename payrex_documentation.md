# PayRex Developer Integration Guide

This guide is a comprehensive synthesis of the official PayRex documentation, covering everything from core platform capabilities to deep technical integration details.

---

## 1. Platform Overview

PayRex is a modern API platform designed to simplify payment processing. It provides robust tools to accept payments across various business models securely and reliably.

### Solutions
- **PayRex Elements:** Modular, customizable UI components that embed directly into your site for a frictionless, branded checkout.
- **PayRex Checkout:** A PayRex-hosted, highly optimized payment page that requires minimal integration effort.
- **Billing Statements:** Hosted payment pages tailored for invoicing, supporting line items and due dates.
- **PayRex Pages:** No-code, always-on payment links generated directly from the Dashboard.
- **Plugins:** Pre-built integrations for major e-commerce platforms like Shopify.

> [!TIP]
> **Reporting & Finance:** PayRex allows you to export detailed payout summaries (including fees, taxes, and adjustments) directly to CSV for seamless integration with ERP and accounting software.

---

## 2. API Fundamentals

The PayRex API is organized around **REST** principles, offering predictable resource-oriented URLs.

- **Format:** The API accepts form-encoded request bodies and exclusively returns **JSON-encoded** responses.
- **HTTP Methods:** Standard HTTP verbs are used (`GET` for reading, `POST` for creating, `PUT`/`PATCH` for updating, `DELETE` for removal).
- **Status Codes:** PayRex relies heavily on standard HTTP response codes to indicate the success or failure of an API request.

### Authentication

PayRex authenticates your API requests using your account's API keys. 

> [!WARNING]
> **Keep your Secret Keys secure.** Your secret keys can perform any action on your account without restriction. Never expose them in public repositories, client-side code, or mobile apps.

- **Basic Auth:** Authentication is handled via HTTP Basic Auth.
- **Credentials:** Use your API key as the basic auth **username**. You do not need to provide a password.

PayRex provides two sets of keys for your environments:
1. **Live Mode Keys:** Used to process real transactions.
2. **Test Mode Keys:** Used in your development environment to simulate transactions safely.

---

## 3. The Payment Intents API

The Payment Intents API is the recommended and unified approach to handling complex payment lifecycles. It tracks a payment from creation through to completion, accommodating scenarios where additional authentication (like 3D Secure) is required.

### Core Concepts
- **State Tracking:** A Payment Intent resource holds the complete state of a payment.
- **Amount & Currency:** You specify the exact amount and currency you wish to collect when creating the intent.
- **Status Progression:** Typical statuses include `requires_payment_method`, `requires_action` (e.g., OTP/3DS), `processing`, and `succeeded`.

### Implementation Workflow
1. **Create the Intent:** Your backend server creates a Payment Intent via the API with the specific amount.
2. **Pass Client Secret:** The API returns a `client_secret`. Your backend passes this token to your frontend application.
3. **Collect Payment Details:** Your frontend (using PayRex Elements or Checkout) uses the `client_secret` to securely collect the user's payment method details.
4. **Confirm the Payment:** The frontend submits the details. If successful, the intent status updates to `succeeded`.

---

## 4. Webhooks & Real-Time Events

Webhooks are crucial for building a resilient integration. Instead of polling the API to check if a payment succeeded or failed, PayRex pushes real-time `Event` resources to an HTTP endpoint on your server.

### When to Use Webhooks
- Fulfilling an order after a successful payment (`payment_intent.succeeded`).
- Updating your database when a payout is processed.
- Handling asynchronous payment methods (e.g., e-wallets like GCash or GrabPay).

### Security: Webhook Signatures

To ensure that the webhook requests you receive genuinely originate from PayRex and haven't been tampered with, you must verify the **Webhook Signature**.

> [!IMPORTANT]
> PayRex includes a `Payrex-Signature` header in every webhook request. You must cryptographically verify this header using your webhook endpoint's secret key.

**Understanding the `Payrex-Signature` header:**
The header contains three comma-separated key-value pairs:
```http
Payrex-Signature: t=1496734175, te=5242a89..., li=5f7bsa9...
```
- `t`: The timestamp of the request.
- `te`: The signature for test mode events.
- `li`: The signature for live mode events.

**Verification Steps:**
1. Extract the timestamp (`t`) and the appropriate signature (`li` for live, `te` for test).
2. Concatenate the timestamp (as a string), a period (`.`), and the **raw JSON payload** of the HTTP request.
   *Example: `1496734175.{"id":"evt_123"}`*
3. Compute an HMAC with the SHA256 hash function using your concatenated string and your webhook's secret key.
4. Compare your generated hash against the value extracted from `li` or `te`. If they match, the request is authentic.

---

## 5. Error Handling

When interacting with the API, properly handling errors ensures a smooth experience for both developers and users.

- **400 Bad Request:** Usually indicates missing parameters or invalid data formatting. The response body will contain detailed error codes specifying exactly what went wrong.
- **401 Unauthorized:** Invalid API keys provided.
- **402 Request Failed:** The parameters were valid, but the request failed (e.g., a card was declined).
- **5xx Server Errors:** Rare, but indicates an issue on PayRex's end.

*You can implement **Idempotency Keys** (via the `Idempotency-Key` header) to safely retry API requests without the risk of accidentally creating duplicate charges.*

---

## 6. Code Samples & JSON References

### Create a Payment Intent (Node.js)
```javascript
const client = require('payrex-node')('insert your PayRex Secret API key.');

const paymentIntent = await client.paymentIntents.create({
  // Amount is in cents. The sample below is 100.00.
  amount: 10000,
  currency: 'PHP',
  payment_methods: [
    'card',
    'gcash',
    'maya',
    'qrph'
  ],
});
```

### Create a Payment Intent (cURL)
```bash
curl --request POST \
  --location 'https://api.payrexhq.com/payment_intents' \
  -u YOUR_SECRET_API_KEY: \
  --data-urlencode 'amount=10000' \
  --data-urlencode 'currency=PHP' \
  --data-urlencode 'payment_methods[]=card' \
  --data-urlencode 'payment_methods[]=gcash'
```

### PaymentIntent JSON Payload Example
```json
{
  "id": "pi_SJuGtXXC3XNRWpW3W1zQKiLWf67ZC4sX",
  "resource": "payment_intent",
  "amount": 10000,
  "amount_received": 0,
  "amount_capturable": 0,
  "client_secret": "pi_SJuGtXXC3XNRWpW3W1zQKiLWf67ZC4sX_secret_7KGizzHuLtPtaLwiRMHekBHRUo6yv52r",
  "currency": "PHP",
  "description": "",
  "last_payment_error": null,
  "latest_payment": null,
  "livemode": false,
  "metadata": null,
  "next_action": {
    "type": "redirect",
    "redirect_url": "https://my-application/redirect"
  },
  "payment_method_options": {
    "card": {
      "capture_type": "automatic"
    }
  },
  "payment_methods": [
    "card",
    "gcash"
  ],
  "statement_descriptor": null,
  "status": "awaiting_payment_method",
  "capture_before_at": 1700407880,
  "customer": null,
  "created_at": 1700407880,
  "updated_at": 1700407880
}
```

### Webhook Resource JSON Payload Example
```json
{
  "id": "wh_225tMcrUMMdiwv2Ya7HTXAEifAx8nno2",
  "resource": "webhook",
  "secret_key": "whsk_cU8kMThbLEkF3yvz1ygCrPrBdAWguuCU",
  "status": "enabled",
  "description": "This is the webhook used for sending shipments after receiving successfully paid payments",
  "livemode": false,
  "url": "https://my-ecommerce.com/send-shipments",
  "events": [
    "payment_intent.succeeded"
  ],
  "created_at": 1706056262,
  "updated_at": 1706056471
}
```
