# Step 1 – Create your first agent (5 min)

## 1a. Create the agent

Create a new agent; never edit a provisioned or another participant's agent. If `Shopping-Assistant` already exists, add your own unique suffix and use that name throughout this lab.

| # | Click / do | Type |
|---|---|---|
| 1 | In project **bootcamp**, go to **Home** | – |
| 2 | Click **Create an agent** (or **Build → Agents → + New agent**) | – |
| 3 | **Agent name** | `Shopping-Assistant` |
| 4 | Click **Create** | – |

✅ The agent **Playground** opens: settings on the left, chat on the right.

## 1b. Set the model and instructions

| # | Click / do | Type / paste |
|---|---|---|
| 1 | **Model** dropdown | `bootcamp-chat` |
| 2 | Open [`assets/agent-instructions.txt`](../assets/agent-instructions.txt) → **copy all** | – |
| 3 | Click in the **Instructions** box → paste | *(the whole text)* |
| 4 | Click **Save** | – |

## 1c. Chat with it

⌨️ Type in the chat:

```
Hi! What can you help me with?
```

👀 It introduces itself as the assistant for **Contoso Sports**.

⌨️ Type in the chat:

```
Do you have black running shoes under 120 euro?
```

👀 It says it **doesn't have the product information yet** – it must not invent products. You fix that in Step 2 with a toolbox.

💡 Switch the chat pane from **Chat** to **YAML** to see the whole agent as text.

✅ **Checkpoint:** the agent answers and follows its instructions.

➡️ Next: [Step 2 – Build the toolbox](02-build-the-toolbox.md)
