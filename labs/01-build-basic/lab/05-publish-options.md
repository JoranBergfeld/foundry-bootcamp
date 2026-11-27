# Step 5 – See where your agent can go (look only) (6 min)

> 👀 **Look only.** Publishing to Teams, Microsoft 365 Copilot or Copilot Studio is **not available in the bootcamp environment**. You only see where the options are in the Foundry portal – **do not click the final Publish button**.

## 5a. Versions

| # | Click / do | What you see |
|---|---|---|
| 1 | Open **Shopping-Assistant** → **Details** tab | Your agent's settings |
| 2 | Look at **Active version** | **Always use latest** – every **Save** creates a new version, and the endpoint serves the active one |

## 5b. Endpoints

| # | Click / do | What you see |
|---|---|---|
| 1 | **Details** tab → **Endpoints** | **Responses** endpoint – how your own apps call the agent |
| 2 | Same section | **A2A** endpoint – how other agents call it |

## 5c. The Publish menu

| # | Click / do | What you see |
|---|---|---|
| 1 | Click **Publish** (top right) | The publish options, including **Teams and Microsoft Copilot** |
| 2 | Click **Cancel** / close the dialog | Nothing is published |

## What you would do in your own tenant

| Where | How | Status |
|---|---|---|
| **Teams + Microsoft 365 Copilot** | Publish → Teams and Microsoft Copilot → details → **Just you** (no admin approval) or **People in your organization** (admin approval) | GA |
| **Copilot Studio** | Add the published agent as a **connected agent** with the project endpoint + Agent ID | Preview |
| **Your apps / other agents** | Call the **Responses** or **A2A** endpoint | Available / preview |

✅ **Checkpoint:** you found the active version, the endpoints and the Publish options – without publishing.

📖 Docs: [Publish to Microsoft Copilot and Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot) · [Add a Foundry agent in Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/agents-experience/add-agent-foundry)

➡️ Next: [Step 6 – Wrap up](06-wrap-up.md)
