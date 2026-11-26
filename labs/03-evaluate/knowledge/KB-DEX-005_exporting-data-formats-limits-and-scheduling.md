---
article_id: KB-DEX-005
version: 1
title: "Exporting data: formats, size limits and scheduling"
product_area: data_export
issue_type: how_to
platforms: [web, desktop_app, api_client]
applies_to_versions: "4.2 and later"
status: current
last_updated: 2025-03-14
related_articles: [KB-DEX-006, KB-API-009, KB-API-010, KB-SUP-014]
---

# Exporting data: formats, size limits and scheduling

> **Applies to:** Version 4.2 and later (web, desktop app and API).
> Version 4.2 added Parquet, background exports, split output and new destinations. If you are on version 4.1 or earlier, the limits in this article do not apply. In those versions, every format was limited to 1,000,000 rows.

## Overview

You can export data from tables and dashboards to a file, send it to a destination, or set up a schedule. This article explains:

- Which formats you can use and their limits
- How direct and background exports work
- How to split large exports
- How to send exports to a destination
- How to schedule exports
- How to export through the API

If an export fails or the file is incomplete, see KB-DEX-006.

## Formats and limits

| Format | Maximum rows | Maximum file size | Best for |
|---|---|---|---|
| CSV | 5,000,000 | 2 GB | Most tools and large datasets |
| Excel (.xlsx) | 1,000,000 | 500 MB | Smaller reports opened in a spreadsheet |
| JSON | 2,000,000 | 1 GB | Developers and other systems |
| Parquet | 20,000,000 | 5 GB | Very large datasets and data analysis tools |

Choose **CSV** or **Parquet** for large datasets. Excel has the lowest row limit. Wide exports with many text columns can reach the file-size limit before the row limit.

## Direct and background exports

- **Up to 250,000 rows:** The export runs directly and downloads in your browser or the desktop app. The time limit is **30 minutes**.
- **More than 250,000 rows:** The export runs **in the background**. You can keep working. When it is ready, you get a notification with a download link. The time limit is **4 hours**.

Download links are valid for **72 hours**. After that, run the export again. Wait for the notification before you download. Opening the link before the job finishes gives a partial file.

You can follow every export in **Data > Exports > History**.

## Steps

### Step 1: Export data once

1. Open the table or dashboard you want to export.
2. Select **Export**.
3. Choose the format.
4. Use **Filters** to limit the date range or records, and select only the columns you need.
5. Select **Export**. Small exports download right away. Large exports appear in **Data > Exports > History** with the status *Running*.

### Step 2: Split a large export

1. In the export dialog, select **Advanced > Split output**.
2. Choose **By month** or **By N rows**. We recommend 1,000,000 rows per file.
3. The export creates a .zip file with one file per part.

Splitting is useful when the data is close to a format limit, or when the people who receive it use Excel.

### Step 3: Send an export to a destination

Exports can go to these destinations:

| Destination | Notes |
|---|---|
| Email | Files up to 25 MB are attached. Larger files are sent as a download link (valid 72 hours). |
| SharePoint | Needs a Microsoft 365 connection with write access to the folder. |
| Azure Blob Storage | Needs write access to the container. |
| Amazon S3 | Needs an access key with write permission to the bucket. |

To set up a destination:

1. Go to **Settings > Connections**.
2. Select **Add connection** and choose the destination type.
3. Sign in or enter the access details, then select the target folder, container or bucket.
4. In the export dialog, choose the destination under **Send to**.

> **Note:** Microsoft 365 connections expire after **90 days without use**. When an Amazon S3 access key is rotated in AWS, update it in **Settings > Connections**.

### Step 4: Schedule an export

1. Set up the export as in Step 1.
2. Select **Schedule** instead of **Export**.
3. Choose **Daily**, **Weekly** or **Monthly**, and the time.
4. Choose the destination and save.

Manage schedules in **Data > Exports > Scheduled**. There you can edit columns, pause a schedule or select **Run now** to test it. If someone renames or removes a column, the scheduled export fails with **EXP-2002**. See KB-DEX-006 for how to fix it.

### Step 5: Export through the API

1. Start the export with `POST /v2/exports`. The response includes an export ID.
2. Check the status with `GET /v2/exports/{id}`.
3. Download the file only when `status` is `completed`.

The same format limits apply. You can also receive the `export.completed` or `export.failed` webhook event instead of polling; see KB-API-010. For authentication and rate-limit errors, see KB-API-009.

## Error codes

| Code | Meaning |
|---|---|
| EXP-1001 | Export timed out |
| EXP-1004 | Row or file-size limit exceeded |
| EXP-2002 | The data structure changed during the export |
| EXP-3001 | The destination denied access |
| EXP-3007 | The destination is full or has hit its quota |
| EXP-9000 | Unexpected server error |

For what to do with each code, see KB-DEX-006.

## Platform notes

- **Web:** Download links in notifications need an active session. If your session has expired, sign in again and download from **Data > Exports > History**.
- **Desktop app:** Version 4.2.0 cut off Excel exports over 500,000 rows. This is fixed in **4.2.3**. Update via **Help > Check for updates**.
- **API client:** The v1 endpoint `/v1/export` is deprecated. It is limited to 1,000,000 rows and does not support background exports. Use `/v2/exports`.

## FAQ

**Can I export from the mobile app?**
No. Use the web app, the desktop app or the API.

**How long are export files kept?**
Download links are valid for 72 hours. Files sent to a destination stay there under your own storage rules.

**Why didn't my export download right away?**
It has more than 250,000 rows, so it runs in the background. Wait for the notification.

## When to contact support

Contact support if an export within the limits fails repeatedly, or if you need help choosing a format for a very large dataset. Include the export ID from **Data > Exports > History**. Response times depend on your support plan and the ticket priority; see KB-SUP-014.

## Related articles

- KB-DEX-006: Export fails or the exported file is incomplete
- KB-API-009: API authentication errors and rate limits (401, 403, 429)
- KB-API-010: Webhooks not firing: integration troubleshooting
- KB-SUP-014: How support works: response times by support plan and priority
