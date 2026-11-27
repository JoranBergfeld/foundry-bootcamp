# Step 2 – Build the toolbox for the agent's assignment (12 min)

## The assignment

> **Shopping-Assistant** helps Contoso Sports shoppers with products, store policies, live information and totals – and helps **store staff** solve IT problems using past support tickets and Microsoft Learn.

All tools for this assignment go into **one Toolbox**, behind **one MCP endpoint** that any agent can reuse.

| Part of the assignment | Tool in the toolbox | Grounded on |
|---|---|---|
| Products, prices, stock, delivery, returns | **File search** | `assets/products.md`, `assets/store-policies.md` |
| Store staff IT problems | **Foundry IQ** (Azure AI Search) | Pre-indexed `bootcamp-baseline-v1` – 100,000 IT support tickets |
| Live / general info (weather, running tips) | **Web search** | The public web, with sources |
| Totals and comparisons | **Code interpreter** | – |
| Microsoft how-to questions | **MCP server – Microsoft Learn** (existing, no sign-in) | Official Microsoft Learn docs |

> ⚠️ Toolbox is in **preview** – if a button name is slightly different, pick the closest match.

## 2a. Create the toolbox

Create your own toolbox; if the name is taken, add a unique suffix and use it throughout. Do not modify a provisioned toolbox, existing vector store or shared Search index.

| # | Click / do | Choose / type |
|---|---|---|
| 1 | **Build → Tools → Toolboxes** tab → **+ Create toolbox** | – |
| 2 | **Name** | `contoso-store-toolbox` |
| 3 | **Description** | `Tools for the Contoso Sports assistant` |

## 2b. Add the five tools

| # | Click / do | Choose / type |
|---|---|---|
| 1 | **+ Add tool → File search** → **Upload files** | `assets/products.md` and `assets/store-policies.md` – wait for **Ready** |
| 2 | Description | `Contoso product catalog and store policies` |
| 3 | **+ Add tool → Foundry IQ** (Azure AI Search) | Connection: `bootcamp-search` · Index: `bootcamp-baseline-v1` · Query type: **Simple** (keyword) |
| 4 | Description | `Past IT support tickets – use for store staff IT problems` |
| 5 | **+ Add tool → Web search** | Description: `Live or general information that is not in the files` |
| 6 | **+ Add tool → Code interpreter** | Description: `Maths, totals and price comparisons` |
| 7 | **+ Add tool → MCP** → pick **Microsoft Learn** from the catalog, or **Custom → MCP** | Name `microsoft-learn` · Endpoint `https://learn.microsoft.com/api/mcp` · Authentication **Unauthenticated** |
| 8 | **Create** / **Save** | – |

✅ The toolbox shows **version 1** with **5 tools**.

> 💡 No file upload inside the toolbox in your region? Add **File search** directly to the agent (**Agent → Tools → + Add → File search**) and keep the other four tools in the toolbox.
> ℹ️ The `bootcamp-baseline-v1` index is **keyword (full-text)** only – it has no vectors, so choose a simple / keyword query type.

Use a **new** File Search vector store for your uploads, not an existing store from another lab. If uploads, tools or authentication are unavailable, ask the organizer rather than changing shared setup or using keys.

Web search can send query data outside the Azure compliance boundary. Use only this lab's fictional scenario and synthetic data; never send credentials or real customer information.

## 2c. Attach the toolbox to your agent

| # | Click / do | Choose / type |
|---|---|---|
| 1 | **Build → Agents** → open **Shopping-Assistant** | – |
| 2 | **Tools → + Add → Toolbox** | `contoso-store-toolbox` |
| 3 | **Save** | – |

✅ **Checkpoint:** the agent shows one toolbox with 5 tools.

📖 Docs: [What is Toolbox?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/toolbox-overview) · [Connect to MCP servers](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol)

➡️ Next: [Step 3 – Test each tool and read the trace](03-test-tools-and-traces.md)
