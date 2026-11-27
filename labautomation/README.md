# Shared Foundry core (organizers)

`deploy-lab.ps1` is the MicroHack **per-template, per-participant** hook shared
by all six labs. It is not a participant setup/reset script. It retains the
platform's five parameters: `DeploymentType`, `SubscriptionId`,
`ResourceGroupName`, `PreferredLocation`, and `AllowedEntraUserIds`.
There is no per-lab provisioning entry point or shared subscription-level
Foundry account. Each participant environment receives two independent Foundry
accounts/projects with deployed models, plus AI Search, Storage
and Application Insights tracing (#16), plus the pre-indexed baseline dataset
(#17) and prepared evaluation assets (#31).

## Operator prerequisites

- MicroHack must authenticate its provisioner, set the subscription context and
  supply its helper cmdlets before invoking the hook. The provisioner needs the
  platform's subscription Owner permissions, including resource and role
  assignment creation. The hook verifies the context and never signs in or
  switches subscriptions. Its ARM access token must contain the authenticated
  principal's Entra `oid` claim; the same principal must be able to obtain
  tokens for Storage, Search and `https://ai.azure.com/`. Provide `Remove-AzRoleAssignment`; for
  `resourcegroup` deployments the hook removes MicroHack's direct subscription
  Reader grant for each participant, while preserving their resource-group
  Owner grant. The template grants the provisioner the resource-scoped
  data-plane roles required below.
- Register `Microsoft.CognitiveServices`, `Microsoft.Search`,
  `Microsoft.Storage`, `Microsoft.OperationalInsights`, `Microsoft.Insights`
  and `Microsoft.App`
  for each event subscription before fan-out. Check the AI Search Serverless service
  limit per subscription/region for N participants (Basic for retained existing environments).
  Provide Az.Accounts (including `Invoke-AzRestMethod`), Az.Resources (including
  `New-AzResourceGroup` and `New-AzRoleAssignment`), an installed Bicep compiler and the
  PowerShell 7.2 or later, and the current MicroHack helpers `Get-MhhStableHash`,
  `Invoke-MhhDeploymentWithRegionFallback`, and `Remove-MhhResourceGroup`.
  Pin/test the platform runner's helper version before the event; helpers are
  platform-supplied, not downloaded by the hook.
- Supply at least one preferred Azure region in the platform's priority order
  and participant Entra **user object IDs**. An array or comma-separated region
  input is accepted; empty/whitespace input fails before any Azure operation.
  The repository deliberately supplies no default region, including in
  `lab-defaults.json`.
- New environments require a region supporting **Serverless, semantic ranker and
  agentic retrieval**, as well as the Foundry models below. Check the current
  [regional matrix](https://learn.microsoft.com/azure/search/search-region-support)
  before allocation; for example, Sweden Central supports all three Search features,
  while West Europe and North Europe do not currently offer Serverless. The hook
  does not silently substitute Basic when Serverless is unavailable.
- Validate access, model availability, deployment type and quota for **all four deployments**
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
- Ensure the MicroHack runner and Search indexer have a permitted network path
  to Storage. The template requests public network access and tags the Storage
  account `SecurityControl=Ignore` for managed-tenant controls that honor the
  tag. Confirm that this is authorized and effective in the event subscription;
  other policies can still block access.
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
| Primary Foundry account | **Sir Prompts-a-Lot**: `AIServices`, S0, `foundry-sir-prompts-a-lot-<RG-derived uniqueString>` |
| Secondary Foundry account | **Count Tokenstein**: `AIServices`, S0, `foundry-count-tokenstein-<RG-derived uniqueString>` |
| Projects | `bootcamp`, one non-hub project per account, with matching display names; original lab project/endpoints retained |
| Chat | Deployment `bootcamp-chat`; OpenAI `gpt-5.4-mini`, version `2026-03-17`; GlobalStandard; capacity **10** |
| Evaluation judge (primary) | Deployment `bootcamp-judge`; OpenAI `gpt-5.4-nano`, version `2026-03-17`; GlobalStandard; capacity **10** |
| Embedding | Deployment `bootcamp-embedding`; OpenAI `text-embedding-3-small`, version `1`; GlobalStandard; capacity **10**; default **1536** dimensions |
| Secondary chat | Deployment `bootcamp-chat-nano`; OpenAI `gpt-5.4-nano`, version `2026-03-17`; GlobalStandard; capacity **10** |

Capacity values are Azure deployment capacity units, **not** participant counts
or a cross-model RPM guarantee. Check each model's current capacity-to-TPM/RPM
mapping, minimum/step size and subscription quota in the chosen regions.
The original chat and embedding models were deployed in a Sweden Central MicroHack validation environment.
This does not establish availability or quota in other subscriptions, regions
or subsequent events. The new secondary model requires event-subscription preflight;
reserve capacity for two accounts and four deployments per participant.
Nano needs **20 capacity units per participant** across the primary judge and
secondary chat deployments. The primary agent and judge are different models
in the same account, so the evaluation wizard can select both; the existing
Count Tokenstein deployment and endpoint are retained.

The playful account-name prefixes are fixed; the resource-group-derived suffix
keeps the Azure names and endpoint subdomains unique across participant
environments. Azure cannot rename an existing account in place. On reruns the
hook inventories Cognitive Services accounts and retains the original
`foundry-<suffix>` and `foundry-alt-<suffix>` names if they already exist;
their projects still receive the new display names. If both the old and new
name for either account exist, provisioning fails rather than silently switching
participants between accounts. An organizer must resolve the ambiguity without
deleting participant work.

For direct template deployments, supply the required
`existingFoundryAccountNames` array with all Cognitive Services account names
in the target resource group (or `[]` for a new group). Omitting existing names
would select new resources instead of retaining the existing accounts.

As checked on 2026-11-25, the Microsoft retirement schedule lists the chat model
as GA through 2027-09-21 and the embedding model as GA through 2028-02-09.
The secondary `gpt-5.4-nano` model is also GA with a listed retirement date of
2027-09-21 in the [current retirement schedule](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-retirement-schedule).
All four deployments use `NoAutoUpgrade` to avoid unexpected version changes;
organizers must review lifecycle dates and update/revalidate before later
events. Deployments are serialized to avoid concurrent account model updates.
The project is deployed before the models to avoid concurrent account
operations. Changing declared model names, versions, deployment names or
capacity is an organizer-reviewed infrastructure change, not between-lab
recovery.

Both accounts and projects have system-assigned managed identities. Account local
authentication is disabled; public endpoints remain enabled for participant
Entra authentication. Each supplied participant receives Azure AI User
(`53ca6127-db72-4b80-b1b0-d745d6d5456d`) scoped to each Foundry account. Current
Microsoft documentation displays this unchanged built-in role as **Foundry
User**. MicroHack retains ownership of participant control-plane roles.
No service key, password, access token or connection string is included in
participant-facing deployment outputs.

## Date/time MCP tool (primary Foundry only)

The template also deploys one Azure Container Apps Consumption environment and
one app (`mcp-time-<uniqueString>`), using **0.25 vCPU / 0.5 GiB**, zero minimum
replicas and one maximum replica. HTTPS ingress exposes `/mcp` using the official
Python MCP SDK's stateless Streamable HTTP transport with JSON responses.
Its only tool, `get_current_datetime`, returns the current UTC date/time as an
ISO 8601 timestamp with a `+00:00` offset. `/healthz` is an HTTP probe endpoint,
not another MCP tool. Console/system logs route to the existing Log Analytics
workspace through Azure Monitor diagnostics without retrieving workspace keys.

`mcp-time/server.py` and the pinned `mcp==1.26.0` requirement are embedded into
the template at Bicep compilation. The app starts from `python:3.12.12-slim`,
installs the SDK, then executes the packaged server. No registry, custom image
build, service secret or separate deployment command is required. The environment
needs outbound access to Docker Hub to pull the image, and PyPI to install the
SDK and its dependencies on each cold start; installation failures terminate
startup and appear in app logs. Startup/readiness/liveness probes protect
traffic routing. Allow for cold-start latency; retry a timed-out first tool call.
For restricted-network or production use, build a reviewed image containing
the dependencies instead of installing them at startup.

The original project receives a `bootcamp-date-time` connection with category
`RemoteTool`, metadata type `generic_mcp`, and auth type `None`. Only this
connection uses the newer stable `2025-09-01` API, which includes `RemoteTool`.
It is available under **Build > Tools > Configured** in the primary Foundry.
The secondary Foundry has no MCP connection, Search connection or tracing
connection; the original lab integrations remain unchanged.

The endpoint is intentionally public and unauthenticated: it exposes only the
clock, never participant data or Azure credentials. Do not add data access or
mutating tools without introducing appropriate authentication and authorization.
The date/time tool is not attached to the provisioned evaluation agent. To use it,
attach it to a participant-created agent in the primary project, keeping tool-call
approval enabled. The [Foundry MCP guide](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol)
describes the agent `tools` definition: `type: mcp`, `server_label: bootcamp-date-time`,
`server_url: <McpServerUrl>`, `allowed_tools: [get_current_datetime]`, and
`require_approval: always`. The endpoint/tool name are sufficient for this
no-auth service; no header or token is needed.

## Search, Storage and tracing

| Resource | Choice |
|---|---|
| AI Search | `srch-<uniqueString>`, Serverless for new environments (no replicas/partitions), existing Basic retained at 1 replica/partition; semantic ranker free tier, system-assigned identity, `disableLocalAuth` (Entra only) |
| Storage | `st<uniqueString>`, StorageV2 Standard_LRS, public network access, `SecurityControl=Ignore`, shared key and public blob access disabled, OAuth default, TLS 1.2 |
| Baseline container | `baseline` (private); contains the shared ticket dataset |
| Log Analytics | `log-<uniqueString>`, PerGB2018, 30-day retention, local auth disabled |
| Application Insights | `appi-<uniqueString>`, workspace-based, local auth disabled |
| Project connections | `bootcamp-tracing` (AppInsights) and `bootcamp-search` (CognitiveSearch), both `ProjectManagedIdentity`, no stored authentication credentials |

Search uses management API `2026-11-01` and baseline data-plane API `2026-10-01`,
which supports Serverless blob indexers. Serverless bills compute consumption and
indexed storage, including indexing and reruns; it is not a free tier. Each index
has a 10 GB limit. Indexers share a 48-hour cumulative runtime budget per service
per UTC day and have a two-hour per-run limit; our provisioning still requires
the complete 100,000-ticket baseline within one hour.

Serverless supports inbound private endpoints, but not private indexer execution
or outbound shared private links. The baseline indexer uses the Search managed
identity against Storage's public endpoint; private blob access does not require
a private network endpoint. If tenant policy makes Storage private-endpoint-only,
this ingestion path cannot work on Serverless.
See [pricing models](https://learn.microsoft.com/azure/search/search-sku-tier) and
[Serverless indexer execution](https://learn.microsoft.com/azure/search/search-indexer-high-density-serverless-overview).

Azure requires the Application Insights connection string as routing metadata
on `bootcamp-tracing`. ARM retrieves it from the Application Insights resource;
it is stored in the project connection and can be read by identities with
access to that connection. It is not included in deployment outputs or
HackboxCredential. Its instrumentation key is a
[resource identifier, not a security key](https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings);
the connection is configured to use the project managed identity for trace
ingestion, with local authentication disabled.

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
| Provisioner | Storage Blob Data Contributor | Storage | Upload and verify the baseline |
| Provisioner | Search Service Contributor, Search Index Data Reader | Search | Create the indexer and verify queries |
| Provisioner | Foundry User | Primary Foundry account | Upload evaluation files and create dataset, toolbox and prompt-agent versions |
| Foundry project MI | Storage Blob Data Reader | Storage | Read the private golden dataset through `bootcamp-evals-storage` |

If the provisioner is also a supplied participant, its participant roles
already cover these operations and duplicate role assignments are avoided.
All role assignments use stable resource/principal/role-derived names.

## Evaluation assets and File Search preflight

After baseline indexing succeeds, `provision-evals.ps1` prepares these assets in
the **primary** project:

MicroHack stages `labautomation` as the runner's `lab` directory without the
sibling participant `labs` directory. Evaluation provisioning therefore reads
the self-contained `dataset/support-evals-v2.zip`, not participant file paths.
The archive contains the golden dataset, three knowledge files and their MIT
license, copied byte-for-byte from Lab 03. When those sources change, regenerate
the archive from the repository root and run the provisioning tests to check
source/archive parity:

```powershell
Compress-Archive -Path .\labs\03-evaluate\dataset, .\labs\03-evaluate\knowledge, .\labs\03-evaluate\SOURCE-LICENSE.txt -DestinationPath .\labautomation\dataset\support-evals-v2.zip -Force
Invoke-Pester .\tests\provisioning\Deploy-Lab.Tests.ps1
```

| Asset | Prepared content |
|---|---|
| Dataset `support-golden-v2`, version `1` | Eight validated rows copied byte-for-byte from `labs/03-evaluate/dataset/support-golden-v2.jsonl` to private `baseline/evals/support-golden-v2.jsonl`, registered as `uri_file` |
| Storage connection `bootcamp-evals-storage` | `AzureStorageAccount`, project-managed identity, no keys or SAS; the project identity can read the dataset |
| Vector store `bootcamp-support-knowledge-v2` | Exactly the three files in `labs/03-evaluate/knowledge`; the answer-key dataset is never indexed |
| Toolbox `bootcamp-support-evals` | File Search pinned to that vector store |
| Connection `bootcamp-evals-toolbox` | RemoteTool to the version-specific toolbox MCP endpoint, `UserEntraToken`, audience `https://ai.azure.com` |
| Prompt agent `bootcamp-support-agent` | `bootcamp-chat`, pinned toolbox version, deliberately incorrect weekend routing override from Lab 03 |

Dataset, agent and toolbox operations use the Foundry `v1` data-plane API.
The toolbox connection uses management API `2026-09-01`, whose provider supports
`UserEntraToken`. Toolbox file and vector-store requests use the **account-level**
`/openai/v1` endpoint with `x-aml-project-id` obtained from the project's
`properties.amlWorkspace.internalId`. Do not drop this header or substitute
another project's store. See [File Search](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/file-search)
and [toolbox setup](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox).
The toolbox tool uses the flat `vector_store_ids` shape in the current SDK contract.

Uploads are reconciled by content-addressed filenames and content read-back.
The private dataset blob is create-only and checked by length, SHA-256 and MD5;
an incompatible existing dataset registration fails without an update. A rerun
reuses the vector store only when its knowledge manifest and exact file set
match. It waits for all three files to complete ingestion, rejects failed or
cancelled files and verifies a search retrieves the urgent support policy.
Ingestion polling is bounded to approximately 30 minutes, plus request retries.

Agent and toolbox versions are immutable. Reruns reuse the compatible
provisioning baseline, even when participants have created newer versions;
they never change participant versions or promote defaults. A conflicting
reserved asset or connection stops provisioning without deleting or replacing
it. A network error or server failure during a non-idempotent create stops the
run rather than blindly creating duplicates; rerun the hook to reconcile partial
uploads. Do not run concurrent hooks for one participant.

The prompt agent uses user-identity passthrough for its read-only toolbox;
all participants already have Foundry User on the primary account.
It sets `require_approval: never` only for this curated, read-only knowledge
toolbox so unattended agent evaluations can run. This is not approval to
disable confirmation for the separate date/time tool or other MCP tools.
Participants copy the baseline agent before the lab fix and keep the golden
dataset frozen.

The hook verifies asset definitions, file content, vector retrieval, MCP
initialization/discovery and an actual toolbox File Search call, not a complete
agent evaluation. Before fan-out, organizers must confirm that a participant
agent call can retrieve the support policy,
then run Lab 03 with nano selected as judge. In particular, verify the tenant's
user-token passthrough policy, File Search region/model support and judge
evaluator compatibility. No live evaluation acceptance is implied by local tests.

### Lab 01 File Search

The basic-agent lab uploads two fictional files to a File Search vector store.
The deployment does not configure a standard agent setup. The evaluation
hook now exercises basic File Search uploads and vector ingestion, but not
Lab 01's separate portal workflow. Before the event, organizers must confirm that the actual
participant project and region allow file upload, vector-store creation and
attachment to a prompt agent, and that participants have the required access.
Basic agent setup uses Microsoft-managed file and search resources; a
standard setup requires explicitly connected resources and appropriate
storage roles. The `bootcamp-search` connection and baseline index do not
establish that File Search is ready. Allow for File Search storage and model
charges, and validate the path without changing shared resources or using keys.

## Storage network access

The Storage account is tagged `SecurityControl=Ignore` and requests
`publicNetworkAccess: Enabled` with the network default action set to `Allow`.
The tag is used by some managed MicroHack tenants to opt resources out of
security automation that disables public endpoints. It may affect other
security controls on that account; use it only in an authorized lab environment.
The tag is not an Azure Policy exemption and does not guarantee that all tenant
policies will permit access. Verify the effective network setting and the
runner's and Search indexer's access in the event subscription.

When honored, the public endpoint accepts traffic from all networks, but
anonymous blobs and shared keys remain disabled. The baseline container is
private, and uploads and Search indexing use Entra identities. On reruns the
hook retains other Storage tags from its pre-deployment inventory and replaces
any existing `SecurityControl` value. Direct template deployments must supply
existing tags through `existingStorageAccountTags`, keyed by Storage account
name, to retain them.

The hook no longer reads `BOOTCAMP_STORAGE_POLICY_EXEMPTION` or creates policy
exemptions. Incremental deployments do not remove exemptions created by an
earlier version; an authorized organizer must review those separately.

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

`bootcamp-baseline-v1` is a full-text index containing all 20 source columns
as strings, with `ticket_id` as the stable document key. The data source
contains only `ResourceId=<storage resource ID>;` in the Search API's
`credentials.connectionString` property; no secret is present. With no
user-assigned identity specified, the indexer reads the container as the Search
system-assigned identity. This baseline does **not** precompute embeddings and
has no skillset or vectorizer, so the Search identity has no Foundry role. The
`bootcamp-embedding` deployment remains available to participants. Any later
embedding skill or vectorizer must use managed identity, without an API key, and
needs its own organizer-reviewed role assignment.

Blob uploads and Search object creation are create-only. Existing shards are
checked against their expected size and hashes; existing Search definitions
must remain compatible. Participant-added index fields and unrelated resources
are preserved. An incompatible blob, data source, index, or indexer fails
explicitly and is never replaced. If the indexer is missing while the index
already contains documents, provisioning stops rather than recreating an
indexer that could overwrite participant edits. If a rerun finds the existing
index incomplete (fewer than 100,000 documents), it resets the baseline
indexer's change tracking and runs it once, because unchanged shards are
otherwise skipped. Documents are keyed by `ticket_id` and merged, so this
cannot duplicate tickets; it restores missing baseline tickets, re-applies the
source values of the 20 baseline columns, and leaves participant-added fields,
documents and indexes in place. If the repaired run completes and the index is
still incomplete, provisioning fails fast with the observed count. A complete
index is never reset. Credentials are published only after a successful run,
at least 100,000 indexed documents, and a known-ticket full-text query.
Indexer errors are reported to the operator.
RBAC-related HTTP failures are retried for up to approximately ten minutes per
request; indexer polling spans approximately one hour, plus request retries.
Do not delete or reset participant resources to recover a failure.

`ProjectManagedIdentity` is accepted by the Foundry resource provider and SDK
but is not yet in the published `2025-06-01` Bicep types, so the template
suppresses BCP036 for those two connections. Both connections were accepted in
the MicroHack validation deployment; trace ingestion remains unverified.

## Initial provisioning versus retries

**Default: non-destructive incremental deployment only.** A standard first run
(no organizer opt-in) creates a missing participant RG in the **first** supplied
region only, ensures each supplied participant has unconditional RG Owner (as
the MicroHack helper does, never removing grants), and deploys incrementally.
This works in every deployment type, including `subscription` mode. There is no
cross-region retry on this path: if the first region lacks quota or capacity,
the run fails and the organizer adjusts the supplied regions.

An existing RG stays in its existing region, which must be one of the supplied
regions; otherwise the hook fails before deploying and does not move or delete
the RG. No default-path deletion exists. Stable account, project, deployment
and role assignment names, and incremental ARM mode, retain unrelated
resources, agents, connections and participant work. Failed deployments
propagate; there is no automatic reset. An existing populated scope uses this
path even if organizer opt-in remains set.

The hook reads existing Search SKUs from ARM and preserves the managed service's
Basic or Serverless SKU. ARM cannot migrate between Dedicated and Serverless in
place. To adopt Serverless in an existing Basic environment, an organizer must
plan a separate service/environment, rebuild the baseline and reconnect Foundry;
the hook never deletes or replaces Search to force this migration.

For organizer-run **initial provisioning only**, the organizer may set
`BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING=true` in the **provisioner job process
environment** before the existing MicroHack hook runs. Remove it afterwards;
never expose it as a participant reset option. This is an operator intent gate,
not an authorization boundary or an additional hook parameter. The platform's
public contract does not document a UI for injecting process environment
variables: organizers must arrange this on their runner. Without it, the hook
remains safely incremental and offers no cross-region fallback.

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
after recreation. The hook removes the direct subscription Reader grant in
`resourcegroup` mode before deployment; access inherited from groups or broader
management scopes is unaffected. Any other RG-scoped platform access prevents
fallback. Because the helper otherwise prioritizes an existing RG's location,
a disposable initial RG in a different region is removed with
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
participant IDs, as in the MicroHack template, and creates that RG on a
standard first run. In both RG modes it requires the platform's RG name. Changing participant allocation/IDs mid-event is not a
supported way to recover an environment.

## Participant values

Only after complete successful deployment, baseline verification and evaluation
asset verification, the hook emits twenty-one separate
`HackboxCredential` **hashtables**, each with `name` and `value`:

| Name | Value |
|---|---|
| `ResourceGroupName` | Participant resource group |
| `Region` | Effective deployment region, not merely the first preference |
| `FoundryProjectEndpoint` | Foundry API project URL, built from the account's returned endpoint |
| `ChatDeploymentName` | `bootcamp-chat` |
| `JudgeDeploymentName` | `bootcamp-judge`, nano in the primary account |
| `EmbeddingDeploymentName` | `bootcamp-embedding` |
| `SecondaryFoundryProjectEndpoint` | Independent secondary Foundry API project URL |
| `SecondaryChatDeploymentName` | `bootcamp-chat-nano` |
| `McpServerUrl` | Primary project's Container App HTTPS `/mcp` endpoint |
| `McpConnectionName` | `bootcamp-date-time`, configured only in the primary project |
| `SearchEndpoint` | `https://<search>.search.windows.net` |
| `StorageAccountName` | Participant storage account |
| `StorageBaselineContainerName` | `baseline` |
| `BaselineIndexName` | `bootcamp-baseline-v1` |
| `EvalsDatasetName` | `support-golden-v2` |
| `EvalsDatasetVersion` | `1` |
| `EvalsVectorStoreId` | Verified knowledge store ID |
| `EvalsToolboxName` | `bootcamp-support-evals` |
| `EvalsToolboxVersion` | Prepared immutable toolbox version |
| `EvalsAgentName` | `bootcamp-support-agent` |
| `EvalsAgentVersion` | Prepared baseline version, not necessarily the latest participant version |

`FoundryProjectResourceId` is an internal ARM output used by the hook to resolve
project isolation and configure the toolbox connection; it is not published
as a dashboard credential.

`labautomation` is not participant download material. Guides consume these
dashboard values; they must not direct participants to run provisioning.

## Local validation and outstanding acceptance

From the repository root, with PowerShell 7, Pester 6 and Azure CLI/Bicep:

```powershell
$result = Invoke-Pester -Path tests\provisioning -Output Detailed -PassThru
if ($result.Result -ne 'Passed') { throw 'Provisioning tests failed' }
az bicep lint --file labautomation\foundry-core.bicep
uv run --python 3.12 --with-requirements labautomation\mcp-time\requirements.txt python -B -m unittest discover -s tests\provisioning -p test_mcp_time.py
```

Tests invoke the real hook, substituting only platform/Azure external commands,
including a simulated Storage/Search/Foundry data plane, and compile/inspect the ARM
deployment artifact without deploying it. They
exercise region input/order, standard first-run RG creation, existing-RG region
checks, organizer gating, in-place reruns, platform scope
and identity inputs, pre-existing RG metadata/access preservation, success-only
credential publication, the pinned source archive, safe dataset sharding,
indexer/query readiness, and declared keyless resources/models. Evaluation
cases cover dataset/knowledge separation, toolbox attachment, exact file
membership, failed/pending ingestion, query readiness, paginated reconciliation,
partial upload recovery, conflicting assets and preservation of participant
agent/toolbox versions. Network-policy
regressions reproduce blocked Storage access, inspect the requested tag and
network settings, and run both provisioning paths through all ten shards,
100,000 indexed tickets, the expected 20-field schema and the known-ticket query.
The Python test exercises MCP initialization, discovery of exactly one tool,
an actual tool call returning a current UTC timestamp, unknown-tool errors,
and the health endpoint over Streamable HTTP. The new resources still require
an organizer's Azure deployment check, Tools UI check, and an agent tool call.
Compilation checks schema/types, not subscription
policy, live availability, quota or runtime endpoint contents.

A MicroHack hook run successfully deployed the shared ARM resources in one
validation environment. **Not observed:** initial region exhaustion, actual
Entra inference/RBAC propagation, runtime project endpoint, live Search/Storage
upload, indexing and participant queries, trace ingestion through the
`ProjectManagedIdentity` connection, participant dashboard rendering and
retention of participant work across a live rerun. Whether the event's tenant
controls honor the Storage tag and permit access also remains unverified. These
require explicit authorization for an organizer-owned disposable environment.
Do not equate the local tests or a content-pack import with those acceptance checks.

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
  and [indexer status](https://learn.microsoft.com/en-us/azure/search/search-monitor-indexers),
  read 2026-11-25.
