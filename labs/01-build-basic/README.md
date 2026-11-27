# Lab 01: Build it (basic)

Build your first AI agent in Microsoft Foundry (no code).

Part of the **Microsoft Foundry Winter Bootcamp** (MicroHack). Everything happens in the browser – no code, no SDK.

| | |
|---|---|
| **Level** | Beginner |
| **Time** | 45 minutes follow-along; any theory introduction is separate |
| **You need** | The **username and password** from the MicroHack – everything else is already provisioned |
| **You will build** | `Shopping-Assistant` – a prompt agent with one toolbox of five tools |

## Prerequisites

- An organizer-provided participant account and extracted Student ZIP. Find
  `FoundryProjectEndpoint` and `ChatDeploymentName` on your participant dashboard;
  select the matching project and deployment, not another participant's resources.
- A browser with access to the Foundry portal. No SDK, command line or previous lab is required.
- **Organizer readiness check:** verify the participant portal can upload files,
  create a new vector store, attach File Search and run each of the five toolbox
  tools. Provisioning checks basic File Search ingestion, not this complete
  portal workflow. The `bootcamp-search` connection alone does not establish
  File Search readiness. Basic setup uses Microsoft-managed resources; standard
  setup needs connected resources and the appropriate storage roles.
- Confirm model-router availability and tracing before the session. Model calls,
  File Search storage, search tools and additional deployments can incur charges.
  The complete five-tool portal path has not been validated live for this PR.
- Use only the supplied fictional files and synthetic tickets. Do not send
  credentials or real customer data to Web search or external MCP tools.

### Already set up for you (MicroHack)

You get a **username and password**; you don't have to set anything up. Your account has **Owner** rights and comes with:

| Ready | Name |
|---|---|
| Foundry project | `bootcamp` |
| Chat model | `bootcamp-chat` (gpt-5.4-mini) |
| Embedding model | `bootcamp-embedding` |
| Azure AI Search, pre-indexed with 100,000 synthetic IT support tickets | index `bootcamp-baseline-v1` · connection `bootcamp-search` |
| Tracing to Application Insights | connection `bootcamp-tracing` |

**Do not delete anything** – the environment is shared by all six bootcamp labs.

## What you will build

**Assignment:** *Shopping-Assistant helps Contoso Sports shoppers with products, policies, live information and totals – and helps store staff solve IT problems using past support tickets and Microsoft Learn.*

```
 Shopper / store staff ──► Shopping-Assistant (prompt agent · bootcamp-chat, then model-router)
                               │  instructions: which tool to use when
                               ▼
                 contoso-store-toolbox  (one MCP endpoint)
                    ├─ File search ──► products.md + store-policies.md
                    ├─ Foundry IQ ──► AI Search index bootcamp-baseline-v1 (IT tickets)
                    ├─ Web search ──► live / general info, with sources
                    ├─ Code interpreter ──► totals and comparisons
                    └─ MCP: Microsoft Learn ──► official docs (existing MCP server)
                               ▼
   In the portal (look only) ──► versions · Responses / A2A endpoints · Publish options (Teams, M365 Copilot, Copilot Studio)
```

## How each step is written

Every step tells you exactly:
- 🖱️ **what to click** (in a table, in order)
- ⌨️ **what to type in chat** (in a grey box – copy and paste it)
- 👀 **what you should see**

## Follow-along (40-45 minutes)

| Step | What you do | Time | Guide |
|---|---|---|---|
| 0 | Sign in – your environment is ready-made | 5 min | [lab/00-your-lab-environment.md](lab/00-your-lab-environment.md) |
| 1 | Create your first agent | 5 min | [lab/01-create-your-first-agent.md](lab/01-create-your-first-agent.md) |
| 2 | Build the **toolbox** (File search, Foundry IQ, Web search, Code interpreter, Microsoft Learn **MCP**) | 12 min | [lab/02-build-the-toolbox.md](lab/02-build-the-toolbox.md) |
| 3 | Test each tool and read the **trace** | 8 min | [lab/03-test-tools-and-traces.md](lab/03-test-tools-and-traces.md) |
| 4 | Let Foundry pick the model with **model router** | 7 min | [lab/04-model-router.md](lab/04-model-router.md) |
| 5 | See where your agent can go: versions, endpoints and **Publish** options (look only) | 6 min | [lab/05-publish-options.md](lab/05-publish-options.md) |
| 6 | Wrap up (nothing to delete) | 2 min | [lab/06-wrap-up.md](lab/06-wrap-up.md) |

**Total: 45 minutes.** The environment must be provisioned before the session. Trainers should confirm tool access, model-router availability and tracing beforehand. Keep to each step's time box; if deployment is delayed, watch the trainer's prepared example rather than extending the session.

## Files you will use

| File | Used in | Purpose |
|---|---|---|
| [assets/agent-instructions.txt](assets/agent-instructions.txt) | Step 1 | Instructions, including which tool to use when |
| [assets/products.md](assets/products.md) | Step 2 (File search) | Sample product catalog (fictional) |
| [assets/store-policies.md](assets/store-policies.md) | Step 2 (File search) | Sample returns & delivery policy (fictional) |
| [assets/test-prompts.md](assets/test-prompts.md) | Steps 3–4 | Prompts to try, with expected answers |

## Key ideas (in one line each)

- **Agent** = model + instructions + tools.
- **Instructions** tell the agent who it is, what rules to follow and which tool to use when.
- **Toolbox** is one set of tools for an assignment, behind one MCP endpoint, reusable by any agent.
- **MCP** (Model Context Protocol) is the standard way to plug existing tools into agents.
- **Foundry IQ** grounds an agent on an Azure AI Search knowledge source.
- **Traces** show what the agent actually did (which tool, what it found).
- **Model router** picks the best model for each question (Balanced, Quality or Cost).
- **Publish** puts the same agent in Teams, Microsoft 365 Copilot and Copilot Studio (in your own tenant – not in this bootcamp).

## Checkpoints

- You created your own prompt agent using the provided chat deployment.
- Your toolbox includes File Search, Foundry IQ / Azure AI Search, Web search,
  Code interpreter and Microsoft Learn MCP. Uploaded files finished processing.
- Product and policy answers agree with the files. Ticket answers cite relevant
  synthetic tickets, and traces expose tool calls and retrieved evidence.
  A plausible answer or citation alone is not proof of correctness.
- You tried model router, or watched the trainer's prepared example if deployment
  was blocked, and inspected versions, endpoints and publishing options without publishing.
- Shared projects, deployments, indexes, connections and other labs' assets remain unchanged.

## Troubleshooting

- **Missing project, model or access:** check the participant account and dashboard
  values, then contact the organizer. Do not create a replacement project, use
  keys or grant yourself roles.
- **File Search or toolbox unavailable:** ask the organizer to verify the supported
  setup, portal workflow and permissions. Never reuse another lab's vector store
  or edit a provisioned toolbox.
- **Files still processing or failed:** inspect ingestion status and confirm the
  two supplied files were uploaded. Ask the organizer if a failure persists.
- **Ticket search fails:** use `bootcamp-search`, index `bootcamp-baseline-v1`
  and simple / keyword queries. The baseline has no vector fields. Report
  permission or connection failures rather than changing the index.
- **Wrong answer or missing evidence:** confirm the saved agent and ready store,
  start a new chat and inspect the tool call and retrieved passages. If no trace
  or source evidence is visible, report grounding as unconfirmed to the trainer.
- **Model router unavailable:** keep `bootcamp-chat`, watch the prepared example
  and move on within the seven-minute time box.
- **Publishing blocked:** expected in this environment; this step is look-only.

## Learn more

- Foundry Agent Service overview – https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview
- What is Toolbox? – https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/toolbox-overview
- Connect to MCP servers – https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol
- File search tool – https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/file-search
- Deploy and configure model router – https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/model-router-configure
- Publish to Microsoft Copilot and Teams – https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot
- Add a Foundry agent in Copilot Studio – https://learn.microsoft.com/en-us/microsoft-copilot-studio/agents-experience/add-agent-foundry

> Product and policy data in this repo is fictional and for training only. The IT support tickets dataset is *Synthetic IT Support Tickets* by Muhammad Ahsan (CC BY 4.0), provisioned by the bootcamp organisers.
> The Foundry portal changes often – if a button name differs slightly, look for the closest match.

## Source and adaptation

Adapted from the creator-provided
[45-minute MicroHack beginner lab](https://github.com/sharanyaskonandur/Foundrybootcamp-beginner-session/tree/552eabb06e2fc71faef64216bc1a3747003ab396).
The creator requested this contribution. This is not a public license or a broader
reuse grant. The guide retains this repository's content-pack sections and
participant-safety requirements.
