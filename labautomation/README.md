# Lab automation (PROTOTYPE placeholder)

Shared provisioning for all six labs lives here; its interface is [Define the shared provisioning interface used by every lab](https://github.com/JoranBergfeld/foundry-bootcamp/issues/6).

This prototype deliberately ships **no** `deploy-lab.ps1` or `shared-deploy-lab.ps1`, so importing deploys nothing. `lab-defaults.json` is present only so the import validates it. Starting a deployment would create empty participant resource groups plus RBAC; do not start one for this prototype.

[infra/main.bicep](infra/main.bicep) is an **inferred, unwired, undeployed** sketch of what lab 02 (Foundry IQ RAG) needs per participant: Foundry account and project with chat and embedding deployments, Azure AI Search with semantic ranker and a managed identity, a storage container for the help desk articles, and the role assignments listed in the source workshop. It only proves the shape compiles (`az bicep build`).
