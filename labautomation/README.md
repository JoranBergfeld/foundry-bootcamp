# Shared Foundry core (organizers)

`deploy-lab.ps1` is the MicroHack **per-template, per-participant** hook shared
by all six labs. It is not a participant setup/reset script. It retains the
platform's five parameters: `DeploymentType`, `SubscriptionId`,
`ResourceGroupName`, `PreferredLocation`, and `AllowedEntraUserIds`.
There is no per-lab provisioning entry point or shared subscription-level
Foundry account. Search, Storage, monitoring and baseline indexing are deferred
to tickets #16/#17.

## Operator prerequisites

- MicroHack must authenticate its provisioner, set the subscription context and
  supply its helper cmdlets before invoking the hook. The provisioner needs the
  platform's subscription Owner permissions, including resource and role
  assignment creation. The hook verifies the context and never signs in or
  switches subscriptions.
- Register `Microsoft.CognitiveServices` for each event subscription before
  fan-out. Provide Az.Accounts, Az.Resources, an installed Bicep compiler and the
  current MicroHack helpers `Get-MhhStableHash`,
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
User**. MicroHack retains ownership of participant control-plane roles. Workload
identity permissions for Search/Storage and their bindings belong to #16.
No key, password, token or connection string is retrieved or published.

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
RG is absent or contains zero resources**. It receives platform regions in
order, plus participant IDs so that MicroHack restores RG Owner after
recreation. Because the helper otherwise prioritizes an existing RG's location,
an empty initial RG in a different region is removed with
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

Only after complete successful deployment, the hook emits five separate
`HackboxCredential` **hashtables**, each with `name` and `value`:

| Name | Value |
|---|---|
| `ResourceGroupName` | Participant resource group |
| `Region` | Effective deployment region, not merely the first preference |
| `FoundryProjectEndpoint` | Foundry API project URL, built from the account's returned endpoint |
| `ChatDeploymentName` | `bootcamp-chat` |
| `EmbeddingDeploymentName` | `bootcamp-embedding` |

`labautomation` is not participant download material. Guides consume these
dashboard values; they must not direct participants to run provisioning.

## Local validation and outstanding acceptance

From the repository root, with PowerShell 7, Pester 6 and Azure CLI/Bicep:

```powershell
$result = Invoke-Pester -Path tests\provisioning -Output Detailed -PassThru
if ($result.FailedCount) { throw 'Provisioning tests failed' }
az bicep lint --file labautomation\foundry-core.bicep
```

Tests invoke the real hook, substituting only platform/Azure external commands,
and compile/inspect the ARM deployment artifact without deploying it. They
exercise region input/order, organizer gating, in-place reruns, platform scope
and identity inputs, success-only credential publication and declared
keyless resources/models. Compilation checks schema/types, not subscription
policy, live availability, quota or runtime endpoint contents.

**Not observed:** a live MicroHack hook run, cloud deployment/ARM validation,
initial region exhaustion, actual Entra inference/RBAC propagation, runtime
project endpoint, participant dashboard rendering and retention of participant
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
