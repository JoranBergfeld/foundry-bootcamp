# Step 3 – Test each tool and read the trace (8 min)

## 3a. One question per tool

Start a new chat after saving the toolbox attachment so the earlier ungrounded reply is not carried into these tests. Compare retrieved passages with the local files, not just the answer or citation label.

| # | Type in chat | Good answer | Tool in the trace |
|---|---|---|---|
| 1 | `Show me black running shoes under 120 euro.` | Swift Runner €99 and Night Dash €115, both in stock | **file_search** |
| 2 | `I'm store staff: the till PC can't connect to the network printer. Have we seen this before, and how was it fixed?` | A summary of similar past tickets and their resolution | **Azure AI Search** (Foundry IQ) |
| 3 | `What is the total price for 2 Swift Runners and 1 Trail Grip?` | 2 × €99 + €125 = **€323** | **code_interpreter** |
| 4 | `Will it rain in Amsterdam this weekend? Trail Grip or Swift Runner?` | Weather with a source link + a product suggestion | **web_search** + **file_search** |
| 5 | `How do I publish a Microsoft Foundry agent to Microsoft Teams?` | Short steps + a learn.microsoft.com link | **MCP** (microsoft-learn) |
| 6 | `Do you sell tennis rackets?` | Says it doesn't know – does **not** invent | none, or file_search with no relevant result |

> If the MCP tool asks for **approval** in the chat, click **Approve**. The ticket answer depends on the synthetic dataset – any relevant past tickets are fine.

## 3b. Read the trace

Tracing is already connected to Application Insights in your lab environment.

| # | Click / do | Look for |
|---|---|---|
| 1 | Agent → **Traces** tab (or the trace link under a reply) | Your conversations |
| 2 | Open the latest one | The steps of each run |
| 3 | Find the **tool calls** | Which tool ran and what it returned |
| 4 | Find the **model call** | Which model answered |

## 3c. Improve with one line (only if time remains)

Add to the end of **Instructions**: `Always end with one short follow-up question.` → **Save** → ask question 1 again.

✅ **Checkpoint:** you tested all **five tools** and inspected their calls in the trace. If a tool is blocked, ask the trainer to show its prepared trace.

➡️ Next: [Step 4 – Model router](04-model-router.md)
