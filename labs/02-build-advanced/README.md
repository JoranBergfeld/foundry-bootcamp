# Lab 02: Build it (advanced, with advanced RAG)

## Prerequisites

- Your organizer-provided participant environment, including the populated
  baseline Search index, Foundry project and chat deployment. No other lab is
  required.
- The dashboard values `SearchEndpoint`, `BaselineIndexName`,
  `FoundryProjectEndpoint`, `ChatDeploymentName` and `ResourceGroupName`.
- PowerShell 7, Azure CLI, a browser and network access to Azure and Foundry.
  Sign in to the participant tenant with `az login`; use
  `az account set --subscription <participant-subscription-id>` if necessary.
  Run the commands below from the extracted Student ZIP's
  `labs/02-build-advanced` directory.
- Search Service Contributor and Search Index Data Contributor on Search, and
  Foundry User on the Foundry account. Shared provisioning is intended to
  supply these roles. The project identity also needs Search read access.
- **Agent connection permission:** creating an MCP project connection requires
  Foundry Project Manager on the parent Foundry resource. The shared baseline
  does not explicitly grant that role. Ask the organizer to verify it or
  create the connection; do not use an API key or grant yourself roles.
- Agentic retrieval must be available in the participant's Search region. The
  Search semantic ranker free tier has a monthly query allowance. If either is
  unavailable, ask the organizer; do not create a replacement service.

The Search and MCP APIs used here may change; the MCP connection is a preview
capability. This lab has not yet been verified end to end in the event
environment.

## Follow-along (40-45 minutes)

### 1. Inspect the baseline (5 minutes)

The baseline contains synthetic support tickets, not a knowledge article
library. Each ticket has an ID, customer message, first reply and resolution.
In the Azure portal, open your Search service, select the baseline index and
use Search explorer to find `password`. Inspect the fields and one ticket's
resolution. A ticket is evidence of a past case, not a current support policy.

The shared index is full-text only: it has no vectors or semantic
configuration. Foundry IQ can use a text-only index, but needs a semantic
configuration for reranking. Vectors and a vectorizer are optional for this
path. The lab adds a **named** semantic configuration without changing the
default or any documents. It does not create embeddings, run an indexer or
change the shared provisioning.

### 2. Create a knowledge source and base (10 minutes)

Choose a short unique lowercase suffix containing only letters and numbers.
Keep the same suffix for reruns, and use your actual dashboard values:

```powershell
$search = '<SearchEndpoint>'
$index = '<BaselineIndexName>'
$suffix = '<your-unique-suffix>'
.\lab.ps1 -Action Setup -SearchEndpoint $search -IndexName $index -Suffix $suffix
```

The script authenticates through your Azure CLI sign-in. It adds
`lab02-<suffix>-semantic` to the existing index, and creates
`lab02-<suffix>-source` and `lab02-<suffix>-kb`. It uses conditional writes:
an index changed concurrently causes an explicit failure, and existing sources
or bases are never overwritten. A rerun reuses compatible objects; sources with
restricted search fields or other conflicting settings stop the script. Pick a
new suffix rather than deleting existing work.

In the Search service, inspect the index's semantic configuration and the
knowledge source's index and fields. The knowledge base references that source.
Unlike the original blob-source workshop, the shared index was populated by
organizer provisioning: this step does not create a blob source, skillset,
generated index or ingestion pipeline.

### 3. Retrieve evidence (10 minutes)

```powershell
.\lab.ps1 -Action Retrieve -SearchEndpoint $search -IndexName $index -Suffix $suffix `
  -Question 'How were incorrect password login issues resolved?'
```

Inspect the JSON `response`, `references` and `activity`. Compare a returned
ticket ID and its `initial_message` and `resolution_summary` against Search
explorer. Try a second, more specific question and compare the results.
`extractiveData` returns source material, not a generated answer; references
should be checked before using them as evidence.

This base uses **minimal** reasoning: one supplied semantic intent, no
model-driven query decomposition and no answer synthesis in Search. It applies
semantic ranking to the existing text, not vector or hybrid retrieval. More
complex planning and Search-side synthesis require a compatible model and
Search managed-identity model access, which this lab does not provision.

### 4. Ground an agent (15-20 minutes)

1. In the [Foundry portal](https://ai.azure.com/), open the project identified
   by `FoundryProjectEndpoint`. Create a **new** prompt agent with a unique
   name and select the `ChatDeploymentName` deployment. Do not edit an
   existing agent.
2. Add the existing Foundry IQ knowledge base
   `lab02-<suffix>-kb` as a knowledge/tool connection. The connection must use
   the **project managed identity**, not a Search key. The MCP endpoint is:

   ```text
   <SearchEndpoint>/knowledgebases/lab02-<suffix>-kb/mcp?api-version=2026-11-01-preview
   ```

   If the portal cannot create/select the connection, ask the organizer to
   configure a unique `RemoteTool` project connection as described in
   [Connect agents to Foundry IQ](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/foundry-iq-connect).
   It needs audience `https://search.azure.com/`, project-managed-identity
   authentication, and the `knowledge_base_retrieve` MCP tool. Do not replace
   an existing connection. Portal labels and support vary.
3. Give the agent instructions such as:

   ```text
   Use the knowledge base tool for each support question. Base your answer only
   on retrieved tickets and cite their ticket IDs. If the evidence does not
   answer the question, say you do not know. Tickets are historical examples,
   not authoritative support policy.
   ```

4. Save the new version and ask the password question in the playground. Check
   the tool trace, the cited ticket IDs and the original ticket content. Ask a
   question not answered by the dataset and check that the agent does not
   invent a policy. Citations alone do not prove an answer is correct.

## Checkpoints

- The baseline ticket search returns data; the lab's semantic configuration
  is present without changing the index's default configuration.
- The source points to the baseline index; the base references that source.
  The retrieve output includes relevant ticket evidence and references.
- The new agent version calls the knowledge base and grounds its answer in
  inspectable tickets, or the connection/access blocker is reported to the
  organizer rather than bypassed with keys.

## Troubleshooting

- **401/403:** confirm the CLI tenant, subscription, participant roles and
  project identity's Search role. Role changes can take time to propagate.
- **404 baseline index:** check dashboard values; contact the organizer if the
  shared baseline has not been provisioned. Do not create a substitute index.
- **409/412 or conflicting name:** another write may have changed the index or
  the name is already in use. Rerun after inspecting it, or choose another
  suffix; no existing lab resources are deleted or overwritten.
- **No results:** inspect Search explorer first, then simplify the question.
  Check semantic-ranker quota and regional availability. A successful setup
  does not itself prove retrieval works.
- **Agent connection/tool fails:** verify project identity, Search access,
  Foundry Project Manager permission, MCP endpoint and selected agent version.
  Ask the organizer to investigate without relaxing authentication.

## Source and adaptation

Adapted from the [FoundryIQ RAG workshop](https://github.com/syash-git/foundryIQ-rag-workshop)
at commit `973494c76e780199c5075b010a58fd1931cd480b`: its knowledge source,
knowledge base, grounded agent and evidence-checking exercises are retained.
The blob-ingestion/vector pipeline and local web app are replaced by the shared
pre-indexed ticket dataset, text-only semantic retrieval and Foundry
playground. Permission to import, adapt and distribute this material was
confirmed for this bootcamp; it is not a public license or a broader reuse
grant. See [the sourcing decision](https://github.com/JoranBergfeld/foundry-bootcamp/issues/12).

The shared baseline uses [Synthetic IT Support Tickets](https://www.kaggle.com/datasets/ahsanneural/synthetic-it-support-tickets)
by Muhammad Ahsan, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Provisioning splits the original CSV into shards and normalizes line endings;
ticket values are unchanged.
