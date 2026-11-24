# Reuse rights for the advanced-RAG source (`syash-git/foundryIQ-rag-workshop`)

Research for [#11](https://github.com/JoranBergfeld/foundry-bootcamp/issues/11). Checked 2026-11-24 against the source at commit [`973494c`](https://github.com/syash-git/foundryIQ-rag-workshop/tree/973494c76e780199c5075b010a58fd1931cd480b). This is a factual summary, not legal advice.

## Answer

**No license governs the source.** It's a public, non-forked repository with no license file, no license statement in its README or docs, and no license or copyright headers in any file. Under default copyright the author keeps all rights. GitHub's Terms of Service let other users view and fork the repository on GitHub, but they don't grant the right to copy, adapt or redistribute it elsewhere, such as in a bootcamp content pack.

**So the bootcamp can't copy or adapt the material as intended without explicit permission from the copyright holder.** Because there's no license, there are no attribution or other license obligations to meet. The obstacle is that there's no permission at all. See [Decision options](#decision-options).

## Findings

### License status

| Check | Result | Source |
|---|---|---|
| Repository license metadata | `"license": null` | `gh api repos/syash-git/foundryIQ-rag-workshop` |
| License endpoint | `404 Not Found` (GitHub detected no license) | `gh api repos/syash-git/foundryIQ-rag-workshop/license` ([API docs](https://docs.github.com/rest/licenses/licenses#get-the-license-for-a-repository)) |
| Branches | Only `main` | `gh api repos/syash-git/foundryIQ-rag-workshop/branches` |
| Files on `main` | `.gitignore`, `README.md`, `doc.md`, `env.example`, `requirements.txt`, `modules/module-01..04*.md`, `src/*.py` (5 scripts). No `LICENSE*`, `COPYING`, `NOTICE` or `CODE_OF_CONDUCT` | `gh api repos/.../git/trees/main?recursive=1` |
| README or docs license statement | None. Searched every file for `licen`, `copyright`, `(c)`, `MIT`, `Apache`, `Creative`, `based on`, `adapted` and `credit`: no matches, apart from links to Microsoft Learn | file contents through the GitHub contents API |
| Per-file headers | None in any `.py`, `.md` or config file | same |
| Fork or upstream | `"fork": false`, no `parent` or `source`. Nothing in the files says they derive from a licensed sample such as Azure-Samples or Microsoft samples | repo metadata |
| Third-party data, notebooks or images | None. There are no notebooks, images or datasets, and the README says "Sample articles are not included in this repository." Dependencies (`requirements.txt`) are `azure-identity`, `azure-search-documents`, `azure-ai-projects` and `streamlit`, which are installed from PyPI and not vendored | `README.md`, `requirements.txt` |

### Ownership: verifiable facts only

- The owner, `syash-git`, is a personal GitHub **User** account, not an organization. It was created 2025-11-11, and its profile has no name, company or public organization membership (`gh api users/syash-git`, `gh api users/syash-git/orgs`).
- The repository was created 2026-11-23. It has **one commit**, `973494c` ("Initial Foundry IQ RAG workshop"), and **one contributor**, `syash-git`.
- The commit's author and committer metadata reads `Yash Singh <singhy@microsoft.com>`. The commit is **unsigned** (`verification.verified: false`, reason `unsigned`). Commit email metadata is self-declared, so it doesn't verify identity, Microsoft employment or who owns the copyright.
- `doc.md` is a rough authoring outline of the README and module structure. It suggests the material was written for this workshop, although some of it may have been generated with tool assistance. Nothing indicates copied third-party content.

Who owns the copyright is therefore **unverified**: the individual author or, if the work was made in the course of employment, possibly their employer. A permission request should ask the author to confirm who can grant the license.

### What GitHub's terms do and don't allow

- **GitHub ToS, section D.5:** making a repository public grants other users "a nonexclusive, worldwide license to use, display, perform and reproduce (by forking) Your Content **through the Service** as permitted by GitHub's functionality". ([GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service))
- **GitHub Docs:** "without a license, the default copyright laws apply, meaning that you retain all rights to your source code and no one may reproduce, distribute, or create derivative works from your work." ([Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository))
- **choosealicense.com:** for unlicensed software, "you have no permission from the creators of the software to use, modify, or share the software. Although a code host such as GitHub may allow you to view and fork the code, this does not imply that you are permitted to use, modify, or share the software for any purpose." The site recommends asking the maintainers to add a license. ([No License](https://choosealicense.com/no-permission/))

Together these mean that viewing the repository and forking it on GitHub is allowed. Copying its modules, prose or scripts into the bootcamp's lab 2, or adapting them, isn't covered.

### Related licensing context

- **MicroHack upstream:** [`microsoft/MicroHack`](https://github.com/microsoft/MicroHack/blob/main/LICENSE) is under the MIT License (Copyright (c) Microsoft Corporation). A content pack contributed there would need to be compatible with that license, so unlicensed third-party material is a blocker.
- **This repository:** `JoranBergfeld/foundry-bootcamp` currently reports `"license": null`. The bootcamp hasn't chosen an outbound license yet, and any reused material would need to fit whatever license it chooses.
- **Microsoft Learn pages linked from the source:** the source links to Foundry IQ and agentic retrieval articles on learn.microsoft.com. Learn's [Terms of Use](https://learn.microsoft.com/en-us/legal/termsofuse) limit the site to personal, non-commercial use unless otherwise specified, and say that third-party code linked from the site is licensed by its owners. "Write original material based on the docs" therefore means linking to the docs and writing original prose and code. It doesn't mean pasting large parts of Learn articles. Whether individual doc snippets carry a separate open-source license wasn't verified here, because the backing `MicrosoftDocs` repositories need SSO access.

## Decision options

1. **Request explicit permission or a license from the author (recommended first step).** Open an issue on `syash-git/foundryIQ-rag-workshop`, or contact the author directly, and ask them to add a `LICENSE` file, ideally MIT to match MicroHack, or to grant written permission for the bootcamp to adapt and redistribute the material. Ask them to confirm who owns the copyright and therefore who can grant the license. Once a license exists, follow its obligations; for MIT, keep the copyright and permission notice.
2. **Use only licensed upstream material.** Build lab 2 from openly licensed samples, such as MIT-licensed Azure-Samples or Microsoft repositories for Foundry IQ or agentic retrieval, if suitable ones exist, and follow their notice requirements. Each candidate needs its own license check.
3. **Write original material.** Write lab 2 from scratch, based on the public product documentation (Foundry IQ knowledge sources, knowledge bases and agent connection) and linking to it, without copying text or code from the syash-git repository. The unlicensed repository can still be read for orientation, but the bootcamp's text and code must be its own.
4. **Link only.** Point participants to the syash-git repository as optional external reading, without copying it into the content pack. GitHub's ToS allow this, but the bootcamp then can't control, version or adapt that content.

Until option 1 succeeds, treat the source as **reference only**: options 2 to 4 are the paths that need no permission.
