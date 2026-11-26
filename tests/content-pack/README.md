# Content pack structure check

From the repository root, run:

```powershell
pwsh -NoProfile -File .\tests\content-pack\check-pack.ps1
```

The check verifies the six challenge pages and their order, links to the lab
guides, required guide headings, the six solution pointer pages, and the
expected Student ZIP layout based on MicroHack's documented content-preparation
rules, including the Lab 02 participant script. It also checks for obvious cross-lab guide links and any other
walkthrough files. The agreed six labs and their order are defined once in
`Labs.psd1`, shared by the check and its tests. It does not import the
pack, inspect an actual ZIP, prove lab independence, run lab code, or validate
provisioning. Verify those separately in MicroHack and in lab-specific tests.

## Solution pointer pages and the Coach ZIP

MicroHack only discovers the pack when `walkthrough/solution-01.md` to
`solution-06.md` exist: a scan without them reports 0 valid hacks. The pack has
no coach-only material, so each page holds exactly two lines: its title
(`# Solution NN: <lab>`) and `Follow the participant [lab guide](../labs/<lab>/README.md).`
The check rejects any other text in these pages and any other file under `walkthrough/`.

Known limitation: once the pages exist, MicroHack also renders a Preview
Solutions view and generates `download-Coach.zip`. The pack does not configure
`coachZipExclusions`, so the Coach ZIP can contain repository-only files that
are excluded from the Student ZIP. Do not give it to participants.

The check's focused tests use Pester 5 or later:

```powershell
Invoke-Pester .\tests\content-pack
```
