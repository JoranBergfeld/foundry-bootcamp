# Shared Foundry core (organizers)

`deploy-lab.ps1` is the MicroHack **per-template, per-participant** hook shared
by all six labs. It is not a participant setup/reset script. It retains the
platform's five parameters: `DeploymentType`, `SubscriptionId`,
`ResourceGroupName`, `PreferredLocation`, and `AllowedEntraUserIds`.
There is no per-lab provisioning entry point or shared subscription-level
Foundry account. Each participant environment also receives AI Search, Storage
and Application Insights tracing (#16), plus the pre-indexed baseline dataset
(#17).

## Operator prerequisites

- MicroHack must authenticate its provisioner, set the subscription context and
  supply its helper cmdlets before invoking the hook. The provisioner needs the
  platform's subscription Owner permissions, including resource and role
  assignment creation. The hook verifies the context and never signs in or
  switches subscriptions. Its ARM access token must contain the authenticated
  principal's Entra `oid` claim; the same principal must be able to obtain
  tokens for Storage and Search. The template grants this principal the
  resource-scoped data-plane roles required below.
- Register `Microsoft.CognitiveServices`, `Microsoft.Search`,
  `Microsoft.Storage`, `Microsoft.OperationalInsights` and `Microsoft.Insights`
  for each event subscription before fan-out. Check the AI Search Basic service
  limit per subscription/region for N participants. Provide Az.Accounts, Az.Resources, an installed Bicep compiler and the
  PowerShell 7.2 or later, and the current MicroHack helpers `Get-MhhStableHash`,
  `Invoke-MhhDeploymentWithRegionFallback`, and `Remove-MhhResourceGroup`.
  Pin/test the platform runner's helper version before the event; helpers are
  platform-supplied, not downloaded by the hook.
- Supply at least one preferred Azure region in the platform's priority order
  and participant Entra **user object IDs**. An array or comma-separated region
  input is accepted; empty/whitespace input fails before any Azure operation.
  The repository deliberately supplies no default region, including in
  `lab-defaults.json`.
- Validate access, model availability, deployment type and quota for **both**
  models in the actual event subscriptions and preferred regions before
  participant allocation. For each region, organizer read-only preflight can
  use `az cognitiveservices model list --location <region> --subscription <id>`
  and `az cognitiveservices usage list --location <region> --subscription <id>`.
  These checks are operator work, not permission to deploy.
- For N participants per subscription, reserve N times each declared capacity
  below, account/project limits and any other event demand. Choose density in
  MicroHack after checking quota; there is no quota reservation or model/SKU
  substitution in this hook. GlobalStandard processing is global, not a promise
  of region-confined processing.
- Do not run two provisioning jobs concurrently against the same participant
  scope. MicroHack owns allocation, control-plane access, environment lifetime
  and eventual teardown.
- Budget for copying and indexing approximately 35 MB of source data per
  participant, Search capacity, and RBAC propagation. Provisioning waits for a
  completed indexer and a successful query rather than publishing a partially
  prepared environment.

## Models and resources

The RG-scoped `foundry-core.bicep` declares these choices, using the stable
`2025-06-01` Cognitive Services management API:

| Resource | Choice |
|---|---|
| Foundry account | `AIServices`, S0, stable `foundry-<RG-derived uniqueString>` name |
| Project | `bootcamp`, one non-hub project, retained across all six labs |
| Chat | Deployment `bootcamp-chat`; OpenAI `gpt-5.4-mini`, version `2026-03-17`; GlobalStandard; capacity **10** |
| Embedding | Deployment `bootcamp-embedding`; OpenAI `text-embedding-3-small`, version `1`; GlobalStandard; capacity **10**; default **1536** dimensions |

Capacity values are Azure deployment capacity units, **not** participant counts
or a cross-model RPM guarantee. Check each model's current capacity-to-TPM/RPM
mapping, minimum/step size and subscription quota in the chosen regions.
GlobalStandard is documented for both models; this does not establish
availability in any particular platform-supplied region. No region was supplied
or queried against an event subscription during implementation.

As checked on 2026-11-25, the Microsoft retirement schedule lists the chat model
as GA through 2027-09-21 and the embedding model as GA through 2028-02-09.
Both deployments use `NoAutoUpgrade` to avoid unexpected version changes;
organizers must review lifecycle dates and update/revalidate before later
events. Deployments are serialized to avoid concurrent account model updates.
Changing declared model names, versions, deployment names or capacity is an
organizer-reviewed infrastructure change, not between-lab recovery.

The account and project have system-assigned managed identities. Account local
authentication is disabled; public endpoints remain enabled for participant
Entra authentication. Each supplied participant receives Azure AI User
(`53ca6127-db72-4b80-b1b0-d745d6d5456d`) scoped to the Foundry account. Current
Microsoft documentation displays this unchanged built-in role as **Foundry
User**. MicroHack retains ownership of participant control-plane roles.
No key, password, token or connection string is retrieved or published.

## Search, Storage and tracing

| Resource | Choice |
|---|---|
| AI Search | `srch-<uniqueString>`, Basic, 1 replica/partition, semantic ranker free tier, system-assigned identity, `disableLocalAuth` (Entra only) |
| Storage | `st<uniqueString>`, StorageV2 Standard_LRS, shared key and public blob access disabled, OAuth default, TLS 1.2 |
| Baseline container | `baseline` (private); contains the shared ticket dataset |
| Log Analytics | `log-<uniqueString>`, PerGB2018, 30-day retention, local auth disabled |
| Application Insights | `appi-<uniqueString>`, workspace-based, local auth disabled |
| Project connections | `bootcamp-tracing` (AppInsights) and `bootcamp-search` (CognitiveSearch), both `ProjectManagedIdentity`, no stored credentials |

Role assignments (stable `guid(scope, principal, role)` names, so reruns are
idempotent):

| Principal | Role | Scope | Why |
|---|---|---|---|
| Each participant | Search Service Contributor, Search Index Data Contributor | Search | Create and query lab indexes |
| Each participant | Storage Blob Data Contributor | Storage | Upload and read lab data |
| Foundry account MI | Search Service Contributor, Search Index Data Contributor | Search | Documented keyless auth for the Foundry AI Search tool |
| Foundry project MI | Search Service Contributor, Search Index Data Contributor | Search | `bootcamp-search` project-identity connection |
| Foundry project MI | Monitoring Metrics Publisher | Application Insights | Keyless trace ingestion |
| Search MI | Storage Blob Data Reader | Storage | Indexer reads `baseline` (#17) |
| Search MI | Cognitive Services OpenAI User | Foundry account | Baseline embedding skill and query vectorizer |
| Provisioner | Storage Blob Data Contributor | Storage | Upload and verify the baseline |
| Provisioner | Search Service Contributor, Search Index Data Reader | Search | Create the indexer and verify queries |

If the provisioner is also a supplied participant, its participant roles
already cover these operations and duplicate role assignments are avoided.
All role assignments use stable resource/principal/role-derived names.

## Shared baseline dataset

The repository includes the unchanged version-1 ZIP of
[Synthetic IT Support Tickets](https://www.kaggle.com/datasets/ahsanneural/synthetic-it-support-tickets)
by **Muhammad Ahsan**, licensed under
[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
The original dataset archive is redistributed with attribution; it contains no
separate notice file. The pinned archive is 3,722,979 bytes with SHA-256
`036a619b419c4cc9dc5d5b8fe776fdf0e74be456bd053c7080c2aa34e315d909`.
Provisioning uses this packaged copy, not a Kaggle download or participant
credentials.

The source contains 100,000 unique ticket IDs and 20 columns. Provisioning
adapts the CSV into ten 10,000-row UTF-8 shards, repeating the header and
normalizing line endings to LF; the ticket values are otherwise unchanged.
The shards stay below the [Search Basic blob-indexer limit](https://learn.microsoft.com/en-us/azure/search/search-limits-quotas-capacity#indexer-limits).
They are uploaded under `baseline/dataset-v1/`. Reserve that prefix for this
dataset: unexpected blobs there stop provisioning rather than being indexed or
deleted. Other container paths are untouched.

`bootcamp-baseline-v1` contains all 20 source columns as strings, with `ticket_id`
as the stable document key, plus `ticket_vector` (`Collection(Edm.Single)`,
1536 dimensions, cosine HNSW). Each of the 100,000 tickets gets one embedding
of its `initial_message`; replies, resolution text and metadata remain
retrievable/full-text searchable but are not part of that vector. These
43-79-character messages need no chunking.

The data source
contains only `ResourceId=<storage resource ID>;` in the Search API's
`credentials.connectionString` property; no secret is present. With no
user-assigned identity specified, the indexer reads the container as the Search
system-assigned identity. The `bootcamp-baseline-v1-embeddings` skillset uses
`bootcamp-embedding` (`text-embedding-3-small`, 1536 dimensions) on the Foundry
account endpoint derived from `FoundryProjectEndpoint`. Both the skill and the
matching `baseline-vectorizer` omit `apiKey` and `authIdentity`, selecting the
Search system-assigned identity and its existing Foundry role.

Blob uploads and Search object creation (including the skillset) are create-only. Existing shards are
checked against their expected size and hashes; existing Search definitions
must remain compatible. Participant-added index fields and unrelated resources
are preserved. An incompatible blob, data source, index, skillset or indexer fails
explicitly and is never replaced. If the indexer is missing while the index
already contains documents, provisioning stops rather than recreating an
indexer that could overwrite participant edits. A rerun does not reset the
indexer; it starts an incremental run only when an existing index is incomplete,
and publishes credentials only after a successful run, at least 100,000 indexed
documents, and a known-ticket full-text query. It then verifies **every expected
ticket ID** in 100 batches of pure exhaustive vector queries, prefiltered to
1,000 exact IDs with `k=top=1000`. Vector-only results match on vector data,
so missing vectors or missing tickets fail this check; participant-added
documents cannot fill the gap. This avoids downloading 153.6 million floats.
A final known-ticket hybrid query exercises the text vectorizer and checks its
returned vector has 1536 dimensions. Missing coverage fails explicitly, without
resetting the indexer or publishing credentials.

On a complete, unchanged rerun, these checks are read-only apart from the one
query-time embedding: source blobs are not rewritten, the indexer is not run,
and the 100,000 document embeddings are not regenerated. An incremental run can
resume unfinished work, but Azure can repeat work after its last checkpoint;
do not treat recovery as a promise of zero repeat billing. A previously created
full-text-only baseline is incompatible and is **not** automatically migrated,
deleted or reset; an organizer must decide how to preserve any participant work
before upgrading it.

Indexer errors are reported to the operator.
RBAC-related HTTP failures are retried for up to approximately ten minutes per
request; indexer polling allows 24 hours of sleep intervals, plus request
durations/retries and up to six transient-failure restarts. Long-running
indexers may span multiple Azure execution windows; runs resume saved progress
without reset. No recurring schedule is installed.
Do not delete or reset participant resources to recover a failure.

### Vector and hybrid queries

Using a participant Entra bearer token for `https://search.azure.com/`, POST
this body to
`<SearchEndpoint>/indexes('<BaselineIndexName>')/docs/search.post.search?api-version=2025-09-01`:

```json
{
  "search": "password",
  "vectorQueries": [
    {
      "kind": "text",
      "text": "I cannot sign in because my password is incorrect",
      "fields": "ticket_vector",
      "k": 10
    }
  ],
  "select": "ticket_id,initial_message,resolution_summary",
  "top": 10
}
```

This is hybrid retrieval; omit `search` for vector-only retrieval. No
participant model API key or client-side embedding call is needed.

### Embedding volume, price and provisioning time

Planning estimate checked **2026-11-25** for one participant environment:
100,000 inputs, with **5,607,974 characters** total in `initial_message`.
Using the rough English estimate of four characters per token gives
**1,401,994 input tokens (about 1.4 million)**, or about 14 tokens per ticket.
This is not a tokenizer measurement or a billing observation. There are only
96 distinct messages, but this pipeline does not deduplicate tickets or assume
model-side caching discounts: budget for all 100,000 inputs, plus retries and
query embeddings.

The [Azure Retail Prices API](https://prices.azure.com/api/retail/prices?$filter=armRegionName%20eq%20%27eastus%27%20and%20skuName%20eq%20%27text-embedding-3-small-glbl%27)
returned the USD Global meter `text-embedding-3-small-glbl Tokens` at
**$0.00002 per 1K tokens ($0.02 per million)**, effective 2024-06-01 and still
returned on the check date. Estimated first-pass embedding cost:
**1.401994 million x $0.02 = $0.02804 (about three US cents) per environment**.
The [Azure pricing page](https://azure.microsoft.com/en-us/pricing/details/azure-openai/)
and the actual event-region/offer meter govern billing; the illustrative
East US lookup is not a region selection. No Batch API discount is assumed.
Search uptime/vector storage, Storage, Foundry chat usage, tracing, taxes and
retries are additional costs and can dominate this small embedding charge.
Raw vectors alone occupy 614,400,000 bytes (about 586 MiB), before HNSW overhead
and stored copies; preflight must leave capacity for lab indexes as well.

**Capacity remains 10**, not ten parallel requests or ten PTUs. Azure maps
capacity to model/SKU-specific TPM and RPM; the [quota guide](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/quota)
warns those ratios differ by model. For conservative planning, **if** the
deployment maps each unit to 1,000 TPM, capacity 10 means 10,000 TPM and this
input volume alone takes **at least 140 minutes (2 hours 20 minutes)**. Budget
several hours plus resource deployment, RBAC propagation, Search enrichment,
index writes and coverage queries, not a one-hour setup. This is a
token-throughput lower bound, not a measured runtime or guaranteed allocation.
RPM can be the tighter limit: without request batching, 100,000 inputs at
60 RPM take at least 1,667 minutes (27.8 hours), exceeding the hook's polling
budget. Search controls embedding batching and internal throttling retries;
do not assume one request per ticket or a particular batch size.

Before event fan-out, inspect the model/SKU capacity factors and the deployed
`bootcamp-embedding` [rateLimits](https://learn.microsoft.com/en-us/rest/api/aiservices/accountmanagement/deployments/get?view=rest-aiservices-accountmanagement-2024-10-01),
or its `x-ratelimit-limit-tokens` / `x-ratelimit-limit-requests` response
headers, in the intended subscription. Recompute the bound as estimated tokens
divided by actual TPM and account for observed requests per input and RPM.
Current [quota tables](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits)
describe subscription/offer limits, not guaranteed per-deployment throughput.
If the test run is too slow or heavily throttled, **raise embedding capacity
and obtain quota before the event**: at the same assumed mapping, capacity 100
would give a 14-minute token-only floor, not a 14-minute end-to-end promise.
Do not silently change the declared models/capacity or use destructive region
fallback to solve rate limits. Neither the capacity mapping, actual runtime
nor billed cost has been measured against Azure here.

`ProjectManagedIdentity` is accepted by the Foundry resource provider and SDK
but is not yet in the published `2025-06-01` Bicep types, so the template
suppresses BCP036 for those two connections. This has not been validated by a
live deployment.

## Initial provisioning versus retries

**Default: non-destructive incremental deployment only.** An existing RG stays
in its existing region even if the preferred list changes. A missing RG fails
and requires organizer intervention. No default-path deletion or cross-region
retry exists. Stable account, project, deployment and role assignment names,
and incremental ARM mode, retain unrelated resources, agents, connections and
participant work. Failed deployments propagate; there is no automatic reset.
An existing populated scope uses this path even if organizer opt-in remains set.

For organizer-run **initial provisioning only**, the organizer may set
`BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING=true` in the **provisioner job process
environment** before the existing MicroHack hook runs. Remove it afterwards;
never expose it as a participant reset option. This is an operator intent gate,
not an authorization boundary or an additional hook parameter. The platform's
public contract does not document a UI for injecting process environment
variables: organizers must arrange this on their runner. Without it, the hook
remains safely incremental and offers no fallback.

The fallback helper is used only when this opt-in is present **and the target
RG is absent or demonstrably disposable**. Resource-empty alone is insufficient:
a pre-existing RG must be explicitly marked by the organizer with the sole tag
`bootcamp-disposable-initial-scope=true`, have `Succeeded` provisioning state,
no resource locks, no deployment history, and no direct RG role assignments
other than unconditional Owner for the supplied participant IDs. These checks
occur before either destructive helper, including when the RG is already in
preference #1.
Unmarked scopes, additional tags, locks, history or access grants cause an
explicit failure; do not strip platform metadata to force fallback. Instead,
unset the process opt-in and retain the scope using incremental provisioning.
Metadata listing errors also stop provisioning rather than authorizing deletion.

The helper receives platform regions in order, plus participant IDs so that
MicroHack restores the **only permitted direct grants**, participant RG Owner,
after recreation. Inherited subscription access is unaffected. Any other
RG-scoped platform access prevents fallback. Because the helper otherwise
prioritizes an existing RG's location, a disposable initial RG in a different
region is removed with
`Remove-MhhResourceGroup` first, with cleanup results checked, so that the first
supplied preference really is tried first.

**The upstream helper can delete its RG**, including partially deployed
resources on a failed initial attempt and on same-region recycle. It is never
used on a scope already containing resources at hook entry. After a partial
failure leaves resources, a later invocation uses incremental deployment in
place, not cleanup/fallback. An unreadable resource inventory fails rather than
being treated as an empty scope. Destructive recovery of such an environment
is a separate organizer-controlled action, outside this hook.

In `subscription` mode the hook derives `lab-<stable hash>` from the sorted
participant IDs, as in the MicroHack template. In both RG modes it requires the
platform's RG name. Changing participant allocation/IDs mid-event is not a
supported way to recover an environment.

## Participant values

Only after complete successful deployment and baseline verification, the hook
emits nine separate
`HackboxCredential` **hashtables**, each with `name` and `value`:

| Name | Value |
|---|---|
| `ResourceGroupName` | Participant resource group |
| `Region` | Effective deployment region, not merely the first preference |
| `FoundryProjectEndpoint` | Foundry API project URL, built from the account's returned endpoint |
| `ChatDeploymentName` | `bootcamp-chat` |
| `EmbeddingDeploymentName` | `bootcamp-embedding` |
| `SearchEndpoint` | `https://<search>.search.windows.net` |
| `StorageAccountName` | Participant storage account |
| `StorageBaselineContainerName` | `baseline` |
| `BaselineIndexName` | `bootcamp-baseline-v1` |

`labautomation` is not participant download material. Guides consume these
dashboard values; they must not direct participants to run provisioning.

## Local validation and outstanding acceptance

From the repository root, with PowerShell 7, Pester 6 and Azure CLI/Bicep:

```powershell
$result = Invoke-Pester -Path tests\provisioning -Output Detailed -PassThru
if ($result.Result -ne 'Passed') { throw 'Provisioning tests failed' }
az bicep lint --file labautomation\foundry-core.bicep
```

Tests invoke the real hook, substituting only platform/Azure external commands,
including a simulated Storage/Search data plane, and compile/inspect the ARM
deployment artifact without deploying it. They
exercise region input/order, organizer gating, in-place reruns, platform scope
and identity inputs, pre-existing RG metadata/access preservation, success-only
credential publication, the pinned source archive, safe dataset sharding,
indexer/query readiness (including missing-vector rejection, vectorizer wiring
and vector-mapping rerun protection), and declared keyless resources/models.
Compilation checks schema/types, not subscription
policy, live availability, quota or runtime endpoint contents.

**Not observed:** a live MicroHack hook run, cloud deployment/ARM validation,
initial region exhaustion, actual Entra inference/RBAC propagation, runtime
project endpoint, live Search/Storage upload, indexing and participant queries,
trace ingestion through the
`ProjectManagedIdentity` connection, participant dashboard rendering and retention of participant
work across a live rerun. These require explicit authorization for an
organizer-owned disposable environment. Do not equate the local tests or a
content-pack import with those acceptance checks.

## Primary-source contract

- [Pinned contract research](https://github.com/JoranBergfeld/foundry-bootcamp/blob/4fe041e66afcafe248f69d8061680430827fa127/docs/research/microhack-contract.md).
- [MicroHack hook and helper documentation](https://github.com/microsoft/MicroHack/blob/main/99-MicroHack-Template/labautomation/README.md)
  and [template hook](https://github.com/microsoft/MicroHack/blob/main/99-MicroHack-Template/labautomation/deploy-lab.ps1),
  read 2026-11-25. The research's MicroHack revision is
  `2d3ab57256c930718b48df419ac051cfac24a317`; current public raw docs were also
  checked, but GitHub API SAML enforcement prevented resolving a current SHA.
- [Foundry account ARM schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts),
  [project schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts/projects),
  and [model deployment schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts/deployments).
- [Current models](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure),
  [retirement schedule](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-retirement-schedule),
  [quota and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits)
  and [Foundry User role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#foundry-user).
- [Foundry AI Search tool keyless roles](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/ai-search),
  [AI Search RBAC](https://learn.microsoft.com/en-us/azure/search/search-security-rbac)
  and [Entra trace ingestion](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-ingestion-entra-authentication),
  read 2026-11-25.
- [Blob indexer CSV parsing](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-azure-blob-csv),
  [managed-identity Storage access](https://learn.microsoft.com/en-us/azure/search/search-howto-managed-identities-storage)
  [indexer status](https://learn.microsoft.com/en-us/azure/search/search-monitor-indexers),
  [embedding skill](https://learn.microsoft.com/en-us/azure/search/cognitive-search-skill-azure-openai-embedding),
  [query vectorizer](https://learn.microsoft.com/en-us/azure/search/vector-search-vectorizer-azure-open-ai),
  [vector queries](https://learn.microsoft.com/en-us/azure/search/vector-search-how-to-query)
  and [prefiltering](https://learn.microsoft.com/en-us/azure/search/vector-search-filters),
  read 2026-11-25.
