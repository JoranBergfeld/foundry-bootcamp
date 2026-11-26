---
article_id: KB-BIL-003
version: 1
title: "Invoice doesn't match your plan: billing discrepancies and refunds"
product_area: billing
issue_type: billing_problem
platforms: [web, desktop_app]
applies_to_versions: "4.0 and later"
status: current
last_updated: 2025-02-11
related_articles: [KB-BIL-004, KB-SUP-014, KB-GEN-016]
---

# Invoice doesn't match your plan: billing discrepancies and refunds

> **Applies to:** All plans with monthly or annual billing, version 4.0 and later.
> Only users with billing access can see invoices. If you can't open **Settings > Billing**, ask your account administrator or billing contact.

## Symptoms

- Your invoice total is higher or lower than you expected.
- The invoice shows more seats than your team uses.
- You downgraded your plan, but the invoice still shows the old plan.
- You see an extra line, such as a partial-period charge or a credit.
- You were charged twice, or you are still waiting for a refund.
- The invoice shows a status of **Under review** with code **BIL-301**.

## Why this happens

Most differences between an invoice and your plan have a clear explanation:

1. **Seat changes are prorated.** If you add seats during a billing period, you pay for the remaining days of that period. The charge appears as a separate line on your next invoice. Removing seats creates a prorated credit in the same way.
2. **Downgrades take effect at the next billing period.** If you move to a smaller plan, you keep the current plan until the period ends. The invoice issued at that time still shows the old plan for the period just ended.
3. **Upgrades take effect immediately** and are prorated for the rest of the period.
4. **Taxes depend on your region.** VAT or other taxes are shown per region. A changed billing address or missing tax ID can change the tax line.
5. **Monthly and annual billing look different.** Annual plans are invoiced once a year. Seats added during the year are invoiced as prorated charges.
6. **A failed payment was retried.** A declined payment followed by a successful retry can look like two charges. Usually only one is completed, and the other is a temporary hold by your bank.

Invoices are always issued on your **billing date**. You can see it in **Settings > Billing**.

## Error codes

| Code | Meaning | What to do |
|---|---|---|
| BIL-201 | Payment declined | Check with your bank, or update the payment method (see KB-BIL-004). |
| BIL-202 | Card expired | Add a new card in **Settings > Billing** (see KB-BIL-004). |
| BIL-301 | Invoice or plan mismatch under review | No action needed. The billing team is checking the invoice. |
| BIL-401 | Seat limit reached | Add seats or remove inactive users (see KB-BIL-004). |

## How to fix it

### Step 1: Compare the invoice with your plan

1. Go to **Settings > Billing**.
2. Open **Invoices** and select the invoice you want to check.
3. Compare each line with the **Plan** and **Seats** sections on the same page.
4. Look for lines marked *Prorated* or *Credit*. These come from changes during the period.

### Step 2: Check recent changes

- Check whether anyone added or removed seats, or changed the plan, during the billing period. Plan and seat changes are shown in the invoice detail with their dates.
- Check that the billing address and tax ID are correct. Update them in **Settings > Billing** if needed. The change applies to future invoices.
- In **Admin center > Users**, check for users who no longer need a seat. Seats stay billed until you remove them.

### Step 3: Raise a billing dispute

If the invoice still looks wrong, raise a dispute. You must do this **within 60 days of the invoice date**. After 60 days, the invoice can't be disputed.

1. Go to **Help > Contact support**.
2. Choose the category **Billing**.
3. Include the invoice number, the line you think is wrong and what you expected to see.
4. Attach a screenshot of **Settings > Billing** if it helps.

While the billing team reviews it, the invoice shows **Under review (BIL-301)**. You don't need to pay the disputed amount during the review. Pay any undisputed part as usual to avoid a payment reminder.

### Step 4: Understand the outcome

If the invoice is wrong, the billing team adjusts it and you get a corrected invoice. If you have already paid, you get a refund for the difference where it applies. If the invoice was correct, you get an explanation of each line.

## Refunds

- Refunds always go to the **original payment method**. They can't be sent to a different card or account.
- Refunds take **5–10 business days** to appear, depending on your bank or card provider.
- If the original card has expired or been closed, your bank usually forwards the refund to the replacement card. If not, contact your bank first, then support.
- For annual plans, a downgrade during the year doesn't create a refund. The new plan starts at the next billing period.

If you don't see a refund after 10 business days, check your statement for a credit with the same invoice number. Then contact support.

## Platform notes

- **Web:** Invoices can be downloaded as PDF from **Settings > Billing > Invoices**. This is the most complete view.
- **Desktop app:** Billing settings open in the web app in your browser.
- **Mobile app:** Billing is not available in the mobile app. Use the web app.

## When to contact support

Contact support if:

- The invoice is still unclear after you complete Steps 1 and 2.
- A refund has not arrived after 10 business days.
- You were charged and the payment was also declined (**BIL-201**) for the same invoice.

Remember the 60-day dispute window. Include the invoice number and your billing contact's email. Never send full card numbers. Response times depend on your support plan and the ticket priority; see KB-SUP-014.

## Related articles

- KB-BIL-004: Changing your plan, seats or payment method
- KB-SUP-014: How support works: response times by support plan and priority
- KB-GEN-016: Basic troubleshooting checklist before contacting support
