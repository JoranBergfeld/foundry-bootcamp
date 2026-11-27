# Lab 01: Build it (basic)

## Prerequisites

- An organizer-provided participant environment, with access to its Foundry
  project and chat model deployment. Find `FoundryProjectEndpoint` and
  `ChatDeploymentName` on your participant dashboard. Shared provisioning is
  intended to grant you the **Foundry User** role.
- A browser with access to the Foundry portal and the extracted Student ZIP.
  No SDK, command line, or other lab is required.
- **File Search readiness:** the organizer must verify that the project can
  upload files, create a vector store, and attach File Search in the portal.
  Shared provisioning does not currently verify this path. If the project
  uses a standard agent setup, it needs connected Storage and Foundry IQ
  resources, and you need **Storage Blob Data Contributor** on the connected
  storage account. Ask the organizer if access or setup is missing; do not
  create a new project, change the setup, or use a key.
- Only use the fictional files supplied with this lab. Basic agent setup uses
  Microsoft-managed storage and search for File Search; standard setup uses
  the resources connected to the agent environment. The shared baseline
  ticket index is separate and is not changed by this exercise.

Model calls and File Search storage can incur charges. The portal steps and
File Search have not yet been verified end to end in the event environment.
See the [File Search guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/file-search)
for current setup and availability.

## Follow-along (40-45 minutes)

### 1. Explore the scenario (5 minutes)

You are building a shopping assistant for a fictional store. Open
[products.md](assets/products.md) and [store-policies.md](assets/store-policies.md)
from the extracted Student ZIP. The first file describes three products; the
second covers returns and delivery. Keep both files available for upload.

An agent combines a model, instructions and tools. The model generates the
answer; the instructions define its behavior; File Search retrieves relevant
passages. The files are evidence, not a guarantee that every answer is right.

### 2. Create and try an agent (7 minutes)

1. Open [Microsoft Foundry](https://ai.azure.com/nextgen), sign in with your
   participant account and select the project matching `FoundryProjectEndpoint`.
   Use the existing project and model deployment, not a new one.
2. From the project home page, choose **Create an agent**. Create a text
   prompt agent named `shopping-assistant-<suffix>`, using your own short
   unique suffix. Do not edit an existing agent. In the playground, select the
   `ChatDeploymentName` model deployment.
3. Paste these **Instructions**, then save the agent version:

   ```text
   You are a helpful shopping assistant for a fictional store.
   For product, return, and delivery questions, use File Search before answering.
   Base claims only on the retrieved catalog and policy; cite the source when available.
   If the files do not answer a question, say you do not know rather than guessing.
   You cannot access real orders or live inventory, or place or change orders.
   ```

4. Before adding a tool, ask: `What is the price and capacity of the Ridge
   Bottle?` Record the response. The agent does not yet have the catalog, so
   an unsupported guess is not evidence of the answer.

### 3. Add the knowledge files (10 minutes)

1. In the agent playground, open **Tools > Add > Add tools** and choose
   **File Search**. Depending on the portal version, it may be listed under
   knowledge or files.
2. Create a new vector store named `shopping-<suffix>` and upload the two
   files from step 1. Select that store for the agent's File Search tool.
   Record the store ID and the uploaded file IDs if the portal shows them;
   they help identify only your own resources during cleanup. Do not attach
   files to an existing store.
3. Wait until both files finish processing and the store is ready. Save the
   agent version and start a **new chat**, so the earlier answer is not
   carried into the grounded test.

File Search parses and indexes the files asynchronously. If the portal only
offers an existing vector store ID, create the store and upload the files in
the portal's vector-store workflow first, then select it. If that workflow is
unavailable, ask the organizer rather than changing the shared environment.

### 4. Test and inspect evidence (15 minutes)

Use a new chat for each question. Compare the answers with the local files;
the wording may vary.

| Question | What to check |
|---|---|
| Which bottle holds at least 700 mL, has an advertised maximum cold time of at least 16 hours, and costs less than $40? | `products.md` identifies the Ridge Bottle: 750 mL, up to 18 hours and $32. "Up to" is not a guarantee. |
| How much is standard delivery for a $32 order? | `store-policies.md` says $5 for an order below $50. |
| Can I return an unused bottle in its original packaging 20 days after delivery, and who pays shipping? | Yes, the return is within 30 days; the customer pays shipping. |
| My bottle arrived damaged. What should I do and who pays return shipping? | Report it within 14 days of delivery; the store pays return shipping. |
| Does the store deliver to Japan? | The supplied policy does not say. The agent should acknowledge the missing information rather than invent a delivery area. |
| Can you check the status of my order? | The agent should say it cannot access real orders, not claim to have checked. |

For at least the first two answers, open any citation and select **Traces**
beneath the response if available. Look for a File Search call and the
retrieved product or policy passage. Compare the passage to the answer: a
citation or a plausible answer alone does not establish correctness. If no
tool call or source evidence is visible, record grounding as unconfirmed and
ask the organizer. Compare the product answer with your pre-tool response.

### 5. Finish safely (5 minutes)

If you no longer need your work and can verify that nothing else uses it,
delete only the agent and vector store you created for this lab. Deleting a
vector store does not necessarily delete the uploaded file objects: delete
those only if you can verify their IDs and that nothing else uses them.
Deleting a file object can remove it from other agents and stores. If cleanup
controls or ownership are unclear, leave the objects and ask the organizer to
remove them during environment teardown. Never delete the shared project,
model, Search service, baseline index, storage, connections, or another lab's
work.

## Checkpoints

- A new prompt agent uses the provided chat deployment and instructions.
- Its File Search tool is attached to a new vector store with both files fully
  processed.
- The product and delivery answers match the files, with retrieved evidence
  visible; missing facts and unavailable order access are not invented.
- Cleanup is limited to this lab's identified resources, or the organizer has
  been told what remains.

## Troubleshooting

- **Project, model or access missing:** confirm the participant tenant and
  dashboard values, then contact the organizer. Do not create a replacement
  deployment or grant yourself roles.
- **File Search, upload or vector-store creation unavailable:** confirm the
  organizer has prepared a supported agent setup and verified portal access.
  In a standard setup, check your storage role and connected resources.
  Report policy or permission failures rather than bypassing them.
- **Files still processing or failed:** wait for ingestion and inspect its
  status. Check that you uploaded the two `.md` files, then ask the organizer
  if a failure persists.
- **Answer is wrong or lacks evidence:** confirm that the saved agent version
  has File Search and the correct ready store; start a new chat and retry a
  specific question. Inspect the tool call and source before treating the
  answer as grounded.
- **No trace:** response-level details may be available without Application
  Insights; full distributed tracing needs the project's tracing connection.
  If neither a trace nor a citation exposes the source, report the limitation.

## Source and adaptation

Adapted from the
[beginner session outline](https://github.com/sharanyaskonandur/Foundrybootcamp-beginner-session/tree/bd7778d33f5ceee6222c7767f95730bce53db00a).
The requester confirmed the creator's permission for this bootcamp; this is not
a public license or a broader reuse grant. The detailed guide and fictional
files were authored for this adaptation because the linked source files were
absent.
