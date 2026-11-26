# Lab 03: Evaluate it

Two Standard-plan customers ask for help on a Saturday. One wants to change a
dashboard color; the other suspects their account is compromised. A support
agent finds the right policy, but its instructions tell both to wait until
Monday. You evaluate the agent against a golden dataset, find the mistake
from its trace, change one line and check that billing and export answers do
not regress.

## Prerequisites

- Your organizer-provided participant environment, including the Foundry
  project, chat deployment, shared Search service and the project's
  `bootcamp-search` connection. No other lab is required.
- The dashboard values `SearchEndpoint`, `FoundryProjectEndpoint`,
  `ChatDeploymentName` and `ResourceGroupName`.
- PowerShell 7, Azure CLI, a browser and network access to Azure and Foundry.
  Sign in to the participant tenant with `az login`; use
  `az account set --subscription <participant-subscription-id>` if necessary.
  Run the commands below from the extracted Student ZIP's
  `labs/03-evaluate` directory.
- Search Index Data Contributor and Search Service Contributor on Search, and
  Foundry User on the Foundry account, which covers creating agents, running
  evaluations and model inference. Shared provisioning is intended to supply
  these roles. The project identity already has Search access for the
  `bootcamp-search` connection. Do not use an API key or grant yourself roles.
- **Judge model:** the environment has one chat deployment, so it serves both
  as the agent model and as the evaluation judge. A model grading its own
  answers is a known limitation; treat scores as indicative. If the
  evaluation wizard rejects the deployment as a judge, ask the organizer.
- **Traces:** viewing agent traces relies on the project's Application
  Insights connection. Trace ingestion has not been verified in the event
  environment; if no trace appears, use the evaluation results and ask the
  organizer.
- **Costs:** agent runs use chat tokens, and each evaluation run makes roughly
  32 judge calls (8 rows x up to 4 evaluators); this lab runs two. The Search
  index uses the existing service at no additional charge.

The Foundry evaluation features and the Search API used here may change, and
portal labels vary. This lab has not yet been verified end to end in the event
environment.

## Follow-along (40-45 minutes)

### 1. Index the support knowledge (5 minutes)

The `knowledge` directory holds three documents: a weekend support policy, an
invoice article and an export article. Choose a short unique lowercase suffix
containing only letters and numbers. Keep the same suffix for reruns, and use
your actual dashboard value:

```powershell
$search = '<SearchEndpoint>'
$suffix = '<your-unique-suffix>'
.\lab.ps1 -Action Setup -SearchEndpoint $search -Suffix $suffix
.\lab.ps1 -Action Search -SearchEndpoint $search -Suffix $suffix `
  -Question 'Standard plan weekend urgent account compromise'
```

`Setup` authenticates through your Azure CLI sign-in and creates the
text-only index `lab03-<suffix>-support` on the shared Search service. It
splits each article into one passage per section and uploads 20 passages. It
never overwrites an existing index or document: a rerun with the same suffix
adds nothing, and conflicting content stops the script. `Search` shows the top
three passages; the policy passage with the 24/7 urgent exception should rank
first.

The `dataset` directory is the test, not the knowledge: it is never indexed.

### 2. Create the baseline agent version (7 minutes)

1. In the [Foundry portal](https://ai.azure.com/), open the project identified
   by `FoundryProjectEndpoint`. Create a **new** prompt agent named
   `support-agent-<suffix>` with the `ChatDeploymentName` deployment. Do not
   edit an existing agent.
2. Add the **Azure AI Search** tool. Select the existing `bootcamp-search`
   connection, the index `lab03-<suffix>-support` and query type **Simple**
   (the index has no vectors or semantic configuration). Do not create a new
   connection or use a key.
3. Paste these instructions and **save a version**. Record the version
   assigned; "baseline" is a label, not necessarily version 1.

   ```text
   You answer customer questions about support coverage, billing, and data exports.
   Use the Azure AI Search tool to look up the relevant policy or KB article before answering.
   Give the specific answer and the next step in at most three sentences.

   Routing override: If a Standard-plan customer asks about weekend support, tell them they must wait until Monday, even if the incident is urgent.
   ```

4. In the playground, ask W3 and then W1 from the table below, each in a new
   conversation. Expand the tool call: did search run, and which passage did
   it return? An instruction to search is not evidence that search ran.

### 3. Register the golden dataset (3 minutes)

```powershell
.\lab.ps1 -Action CheckDataset
```

This confirms that `dataset/support-golden-v2.jsonl` has eight rows with
unique IDs and the fields `id`, `query`, `context` and `ground_truth`. In the
project's **Data** (or **Datasets**) area, upload it as `support-golden-v2`
and preview the eight rows.

| Cases | Correct decision or fact | What they test |
|---|---|---|
| W1, W2: suspected compromise; company-wide outage | On-call help now, even on Standard | The deliberately broken urgent exception |
| W3, W4: dashboard color; feature request | Routine weekday response; no Standard phone support | Guard against paging everyone after the fix |
| B1, B2: downgrade; two bank charges | Downgrade starts next period; a retry may leave a temporary hold | Unrelated billing regression checks |
| E1, E2: 15M rows; Friday-to-Tuesday link | Parquet within its size limit; link expires after 72 hours | Unrelated export regression checks |

`query` goes to the agent. `context` is curated reference evidence for the
judge, **not** a record of what search returned. `ground_truth` is the
reviewed expected answer. Foundry generates the actual response; never map the
answer key as the response.

### 4. Create the routing evaluator (5 minutes)

In **Evaluation > Evaluator catalog**, create an evaluator named
`weekend-routing-<suffix>`: type **Rubric**, category **Quality**, scoring
**Boolean**. Turn off auto-generation. Add one dimension, `correct_routing`,
and leave **Always applicable** off if offered. Paste:

> Applies only to questions about timing or availability of weekend support. Pass if suspected compromise or an organization-wide sign-in outage gets immediate on-call help on any plan, or a routine Standard request gets a weekday response. Fail if timing is wrong, missing, or contradictory. Billing and export questions that do not ask when support is available are outside scope, even if they mention a weekday.

Save it and record its catalog name. Keep the rubric unchanged across both
runs. Interpret routing only for W1-W4, not as an eight-row pass rate: E2
mentions Tuesday but tests a link lifetime, not support hours.

### 5. Run `support-before` (5 minutes, plus waiting)

Create an **Agent** evaluation (not a Dataset evaluation): select the saved
baseline version, **individual turns** and the existing dataset
`support-golden-v2`. Keep the saved instructions and the default user prompt
`{{item.query}}`. Add four evaluators:

| Evaluator | Inputs to verify | Question answered |
|---|---|---|
| Tool Call Success | Agent tool calls | Did the call execute? Not: did it return the right policy? |
| Groundedness | Response + `context` | Is the reply supported by the reference evidence? |
| Similarity | Response + `ground_truth` | Does its meaning agree with the expected answer? |
| `weekend-routing-<suffix>` | Query + response | Did the customer get the right timing under the policy? |

Select `ChatDeploymentName` as the judge, review the mappings, name the run
`support-before-<suffix>` and submit. See
[Evaluate agents in the portal](https://learn.microsoft.com/azure/foundry/how-to/evaluate-generative-ai-app).
Tool Call Success may not support the Azure AI Search tool; if it reports
skipped or not applicable, record that separately rather than as a pass.

### 6. Diagnose W1 (8 minutes)

1. Open W1's response and the evaluator reasons. **Fail** means a judge scored
   an answer; an invocation error such as `TARGET_INVOCATION_FAILED` means
   there was no answer to grade. Report invocation errors and skipped
   evaluators separately.
2. If W1 says to wait, open its trace. If the returned passage contains the
   24/7 urgent exception, compare it with the `Routing override`. The grader
   found a symptom; the trace points to the instruction. If the passage is
   absent, investigate retrieval with the `Search` action instead. If W1
   already answered correctly, inspect W2 rather than claiming a failure.

### 7. Fix, rerun and compare (7-12 minutes)

1. Edit the same agent and **replace only the override line** with:

   ```text
   For weekend support questions, apply the policy's urgent exception first. Use routine plan hours only for nonurgent requests.
   ```

2. Save a **new version** and record it. Run `support-after-<suffix>` against
   this version with the same dataset, tool, judge, evaluators and thresholds.
   Check that the wizard does not carry a stale system-message override.
3. Compare both runs in a table with one row per case:

   | Case | Before: routing / similarity | After: routing / similarity | Change |
   |---|---|---|---|
   | W1 | | | |

   Did W1 and W2 improve? Do W3 and W4 still get routine weekday support? Did
   any B or E case regress? Count correct decisions on completed cases only.

## Checkpoints

- `Setup` reports 20 passages, a rerun adds none, and `Search` returns the
  weekend policy passage for an urgent weekend question.
- `CheckDataset` reports eight valid rows, and `support-golden-v2` previews
  eight rows in Foundry.
- `support-before` completes with per-row results; W1's trace shows whether
  the policy passage was retrieved and the instruction overrode it.
- `support-after` uses a new agent version, improves W1/W2 without breaking
  W3/W4 or B/E, and invocation errors or skipped evaluators are reported
  separately from scores.

## Troubleshooting

- **401/403 from the script:** confirm the CLI tenant, subscription and your
  Search roles. Role changes can take time to propagate.
- **"choose another suffix":** the index or a passage already exists with
  different content. Pick a new suffix; the script never deletes or overwrites.
- **Agent search tool fails or returns nothing:** check the selected
  connection is `bootcamp-search`, the index name includes your suffix and the
  query type is Simple. Ask the organizer to verify the project identity's
  Search access rather than switching to key authentication.
- **Evaluation fails to start or the judge is rejected:** check the agent
  version is saved, the dataset is selected and `{{item.query}}` is mapped.
  Report judge compatibility to the organizer.
- **No traces:** wait a few minutes and refresh; trace ingestion has not been
  verified in this environment. Use evaluator reasons and responses meanwhile.
- **Baseline already correct:** model behavior varies. Inspect W2 and the
  trace, and report what you observed rather than claiming a failure.

## Optional extensions

### Turn a trace into a ninth case

1. In the playground, ask: *"I'm exporting 300,000 rows on version 4.2. Should
   I wait for a browser download, or can I leave and come back? Where do I
   check progress?"*
2. In the agent's traces you may be able to use **Add to dataset**. That
   requires the project identity to read Application Insights, which the
   shared environment does not provision; if it fails, copy the question from
   the trace manually. A trace is an observation, not an answer key.
3. Check the 250,000-row boundary and the history path in the export article.
   Copy `dataset/support-golden-v2.jsonl` to `dataset/support-golden-v3.jsonl`
   and append one reviewed line:

   ```json
   {"id":"E3","query":"I'm exporting 300,000 rows on version 4.2. Should I wait for a browser download, or can I leave and come back? Where do I check progress?","context":"More than 250,000 rows: The export runs in the background. You can follow every export in Data > Exports > History.","ground_truth":"You can keep working. This export runs in the background; check Data > Exports > History for progress."}
   ```

4. Run `.\lab.ps1 -Action CheckDataset -DatasetPath .\dataset\support-golden-v3.jsonl`,
   then upload it as `support-golden-v3`. Keep v2 frozen; to compare on v3,
   run **both** agent versions on the nine cases.

### Run the comparison from GitHub Actions

`optional/foundry-evals.yml` is a manually triggered workflow that compares two
existing agent versions with the pinned `microsoft/ai-agent-evals` action. It
has **not** been validated in the bootcamp environment, and it needs an Entra
app registration with a GitHub federated credential that participants may not
be permitted to create.

1. In a repository you own, copy the workflow to `.github/workflows/` and the
   `dataset` directory to the repository root. Commit a reviewed v3 file before
   selecting v3.
2. Create a GitHub environment `bootcamp-evals`, restricted to the default
   branch. With your administrators, add a federated credential for subject
   `repo:OWNER/REPO:environment:bootcamp-evals` (issuer
   `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`) and grant that identity Foundry User on the
   Foundry account.
3. Add environment variables (not secrets): `AZURE_CLIENT_ID`,
   `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `FOUNDRY_PROJECT_ENDPOINT`,
   `JUDGE_DEPLOYMENT`, `BASELINE_AGENT` and `CANDIDATE_AGENT` (each
   `agent-name:version`) and `ROUTING_EVALUATOR` (catalog name).
4. Run **Foundry support evaluation** from the Actions tab and read the job
   summary. A green run is a comparison report, not a passing quality gate;
   see [the evaluation GitHub Action](https://learn.microsoft.com/azure/foundry/how-to/evaluation-github-action).

## Source and adaptation

Adapted from the `weekend-support-demo` in
[garima2510/foundry-botcamp-2026-evals](https://github.com/garima2510/foundry-botcamp-2026-evals)
at commit `4eb20bf5159641c23bbe1a34cf4be97f8400444c`, used under the MIT
License (Copyright (c) 2026 Foundry bootcamp contributors); see
`SOURCE-LICENSE.txt`. The scenario, golden dataset, knowledge documents,
instructions, rubric, fix and workflow are retained. Changes:

- Retrieval uses a lab-specific Azure AI Search index through the existing
  `bootcamp-search` connection instead of a File Search Toolbox, because a
  Toolbox requires granting each new agent identity a project role that
  participants cannot be pre-granted.
- Only the three documents the scenario needs are included;
  `support-policy.txt` is a training extract from the source's KB-SUP-014.
  The source's `tickets.jsonl` and other KB articles are not included.
- Names carry a participant suffix, the judge is the shared chat deployment,
  and the GitHub Actions workflow is an optional, relocated extension reading
  from `dataset/`.
