# Content pack structure check

From the repository root, run:

```powershell
pwsh -NoProfile -File .\tests\content-pack\check-pack.ps1
```

The check verifies the six challenge pages and their order, links to the lab
guides, required guide headings, and the expected Student ZIP layout based on
MicroHack's documented content-preparation rules. It also checks for obvious
cross-lab guide links and coach-only walkthrough files. It does not import the
pack, inspect an actual ZIP, prove lab independence, run lab code, or validate
provisioning. Verify those separately in MicroHack and in lab-specific tests.

The check's focused tests use Pester 5 or later:

```powershell
Invoke-Pester .\tests\content-pack
```
