# AGENTS.md

This repository holds the material for the **Winter Bootcamp**: six one-hour sessions run by a team of colleagues, built on the [MicroHack](https://github.com/microsoft/MicroHack) environment and format.

## Workflow

- **Commit and push after every session.** Keep `main` up to date so colleagues always see the latest state. This applies especially during the `/wayfinder` flow: push map/ticket context and any resulting docs before ending a session.
- **Context and docs go straight to `main`.** Files such as `AGENTS.md`, `GLOSSARY.md`, `docs/adr/`, and `docs/agents/` may be committed and pushed directly.
- **Code changes need at least one reviewer.** Any change to bootcamp code (labs, scripts, infrastructure, workflows) goes through a pull request and needs at least one approving review before merging. Do not push code changes directly to `main`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `JoranBergfeld/foundry-bootcamp`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
