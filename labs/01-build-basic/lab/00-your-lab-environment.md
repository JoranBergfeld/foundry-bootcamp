# Step 0 – Open your lab environment (5 min)

Your MicroHack lab environment is **already set up for you**. You do **not** create a project or deploy a chat model.

## ✅ You don't have to set anything up

The MicroHack gives you a **username and password**. Behind that account everything is already provisioned:

| Ready for you | Name | Used in |
|---|---|---|
| Your account, with **Owner** rights on your environment | from the MicroHack | everything |
| Foundry project | `bootcamp` | all steps |
| Chat model deployment | `bootcamp-chat` (gpt-5.4-mini) | Steps 1–3 |
| Embedding model deployment | `bootcamp-embedding` | used by File search |
| Azure AI Search with a **pre-indexed** dataset (100,000 synthetic IT support tickets) | index `bootcamp-baseline-v1`, connection `bootcamp-search` | Step 2 (Foundry IQ) |
| Tracing to Application Insights | connection `bootcamp-tracing` | Step 3 (traces) |

## 🖱️ What to click

| # | Do this | What you should see |
|---|---|---|
| 1 | Open an **InPrivate / Incognito** browser window | A clean window – so your corporate account does not get in the way |
| 2 | Go to **https://ai.azure.com** and sign in with the **username and password the MicroHack gave you** | The Foundry home page |
| 3 | Switch the **New Foundry** toggle **ON** (top bar) | The new Foundry look – all steps use it |
| 4 | Open the project selector → choose **bootcamp** in the account matching `FoundryProjectEndpoint` on your participant dashboard | Your project home page |
| 5 | Left menu **Build → Models** | `bootcamp-chat` and `bootcamp-embedding` with status *Succeeded* |
| 6 | Open the Lab 01 guide from the extracted Student ZIP or this repo in a second tab (you copy text from it) | – |

> ⚠️ **Do not delete** the project, deployments, AI Search or storage. The same environment is used for all six bootcamp labs.

If a resource or permission is missing, contact the organizer. Do not create a replacement project, grant yourself roles or use a key. File Search upload and toolbox access must be verified by the organizer before the session.

✅ **Checkpoint:** you are in project **bootcamp** and see **bootcamp-chat** under Models.

➡️ Next: [Step 1 – Create your first agent](01-create-your-first-agent.md)
