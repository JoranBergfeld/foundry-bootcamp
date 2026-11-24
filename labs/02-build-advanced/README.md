# Lab 02: Build it (advanced, with advanced RAG)

> [!WARNING]
> PROTOTYPE, disposable. Part of the content-pack skeleton for [Validate the repository skeleton in the MicroHack console](https://github.com/JoranBergfeld/foundry-bootcamp/issues/7). Never merge.

Ground the agent in IT help desk articles with Foundry IQ: a blob knowledge source, a knowledge base, and a RAG agent.

## Source

Adapted from [syash-git/foundryIQ-rag-workshop at `973494c`](https://github.com/syash-git/foundryIQ-rag-workshop/tree/973494c76e780199c5075b010a58fd1931cd480b). The source repository has no license file; confirm reuse permission with its author before any of this leaves the prototype branch. Its `env.example` was **not** copied: [env.example](env.example) here contains placeholders only. Relative links to scripts were repointed to `src/`; nothing else was changed. The full upstream guide is [upstream-README.md](upstream-README.md).

## Starting action

```powershell
cd labs/02-build-advanced
python -m venv .venv; .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Then follow [Module 1](modules/module-01-knowledge-source.md).

## Tooling and dependencies

Python 3.10+, Azure CLI, [requirements.txt](requirements.txt).

## Prerequisite environment state

- PLACEHOLDER: entry state from [Define cross-lab state and dependency boundaries](https://github.com/JoranBergfeld/foundry-bootcamp/issues/3).
- Foundry project with chat and embedding deployments, Azure AI Search with semantic ranker, and a blob container holding the [sample IT articles](assets/it-desk-articles/). An inferred, unwired template lives in `labautomation/infra/` (coach/organizer only).
- PLACEHOLDER: how values reach the participant (dashboard credentials) is [Define the shared provisioning interface used by every lab](https://github.com/JoranBergfeld/foundry-bootcamp/issues/6).

## Follow-along (40-45 minutes)

| Step | Module | Checkpoint |
| --- | --- | --- |
| 1 | [Create a blob knowledge source](modules/module-01-knowledge-source.md) | Script prints `Knowledge source ... created or updated successfully.` |
| 2 | [Create a knowledge base](modules/module-02-knowledge-base.md) | Index, indexer and skillset visible in Search. |
| 3 | [Create a RAG agent](modules/module-03-rag-agent.md) | Agent answer shows a retrieval tool call with an article citation. |
| Optional | [Local web app](modules/module-04-local-web-app.md) | Outside core timing. |

## Catch-up and help

See the troubleshooting table in [upstream-README.md](upstream-README.md#troubleshooting). PLACEHOLDER: catch-up path from a previous lab.

## Completion criteria

The agent answers "How do I reset my password?" citing `password-reset.md`, and answers "I don't know" for out-of-scope questions.
