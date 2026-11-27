# Step 4 – Let Foundry pick the model: model router (7 min)

**Model router** is one deployment that picks the best model for **each** question: small and fast for easy ones, a bigger reasoning model for hard ones.

| Routing mode | What it does |
|---|---|
| **Balanced** (default) | Cheapest model that is almost as good as the best |
| **Quality** | Always the best model |
| **Cost** | Cheapest within a wider quality range |

> You are **Owner** on your resource group, so you can deploy it yourself. If the deployment fails on quota or region, ask your trainer – model router is not in every region.

Create a deployment only as directed by the trainer. If `model-router` already exists, ask whether to reuse it; do not overwrite or reconfigure a shared deployment. Do not change roles or quota yourself.

**Time box: 7 minutes.** If deployment is not ready in time, keep your agent on `bootcamp-chat`, watch the trainer's prepared model-router example and continue to Step 5. Do not spend the remaining session troubleshooting deployment.

## 4a. Deploy model router

| # | Click / do | Choose / type |
|---|---|---|
| 1 | Top bar **Discover → Models** → search `model-router` | – |
| 2 | **model-router → Deploy → Custom settings** | – |
| 3 | **Deployment name** | `model-router` |
| 4 | **Routing mode** | **Balanced** |
| 5 | **Deploy** | – |

## 4b. Use it in your agent

**Build → Agents → Shopping-Assistant → Model:** `model-router` → **Save**. The toolbox keeps working.

## 4c. Compare an easy and a hard question

```
What colours does the Swift Runner come in?
```

```
I run 3 times a week, half on muddy trails and half on the road in the dark. My budget is 250 euro for two pairs. Which two shoes, and what is the total?
```

👀 Trail Grip (€125) + Night Dash (€115) = **€240**.

Open **Traces** → compare the **model** that answered each question.

✅ **Checkpoint:** your agent runs on `model-router` and you saw which model answered, or you watched the trainer's prepared example while keeping `bootcamp-chat`. The easy and hard questions may route to the same model.

📖 Docs: [Deploy and configure model router](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/model-router-configure)

➡️ Next: [Step 5 – Publish options (look only)](05-publish-options.md)
