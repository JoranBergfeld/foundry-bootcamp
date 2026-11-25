BeforeAll {
    $script:Check = Join-Path $PSScriptRoot 'Test-ContentPack.ps1'

    $script:Labs = @(
        @{ N = '01'; Name = 'Build it (basic)'; Dir = '01-build-basic' }
        @{ N = '02'; Name = 'Build it (advanced, with advanced RAG)'; Dir = '02-build-advanced' }
        @{ N = '03'; Name = 'Evaluate it'; Dir = '03-evaluate' }
        @{ N = '04'; Name = 'Deploy it'; Dir = '04-deploy' }
        @{ N = '05'; Name = 'Integrate it'; Dir = '05-integrate' }
        @{ N = '06'; Name = 'Govern it'; Dir = '06-govern' }
    )

    function Write-PackFile([string]$Root, [string]$Path, [string]$Text) {
        $full = Join-Path $Root $Path
        New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
        Set-Content -LiteralPath $full -Value $Text -Encoding utf8
    }

    function New-ValidPack {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory $root | Out-Null
        $overview = "# Bootcamp`n`n" + (($script:Labs | ForEach-Object {
            "[$($_.Name)](challenges/challenge-$($_.N).md)"
        }) -join "`n")
        Write-PackFile $root 'Readme.md' $overview
        Write-PackFile $root 'AGENTS.md' '# Agents'
        Write-PackFile $root 'GLOSSARY.md' '# Glossary'
        Write-PackFile $root 'docs/agents/domain.md' '# Domain'
        Write-PackFile $root 'tests/content-pack/x.ps1' '#'
        Write-PackFile $root 'labautomation/lab-defaults.json' (@{
            contentPreparation = @{ studentZipExclusions = @('docs', 'AGENTS.md', 'GLOSSARY.md', 'tests') }
        } | ConvertTo-Json -Depth 5)
        foreach ($lab in $script:Labs) {
            Write-PackFile $root "challenges/challenge-$($lab.N).md" "# Challenge $($lab.N): $($lab.Name)`n`n[Lab guide](../labs/$($lab.Dir)/README.md)"
            Write-PackFile $root "walkthrough/solution-$($lab.N).md" "# Solution $($lab.N): $($lab.Name)`n`nFollow the participant [lab guide](../labs/$($lab.Dir)/README.md)."
            Write-PackFile $root "labs/$($lab.Dir)/README.md" @"
# Lab $($lab.N): $($lab.Name)

## Prerequisites

- Access to the participant environment.

## Follow-along (40-45 minutes)

1. Step.

## Checkpoints

- Checkpoint.

## Troubleshooting

- Fix.
"@
        }
        $root
    }

    function Invoke-Check([string]$Root) { & $script:Check -Root $Root }
}

Describe 'Content pack structural check' {
    It 'accepts a pack with six ordered labs, complete guides and a clean Student ZIP' {
        Invoke-Check (New-ValidPack) | Should -BeNullOrEmpty
    }

    It 'reports a missing lab' {
        $root = New-ValidPack
        Remove-Item (Join-Path $root 'challenges/challenge-05.md')
        Remove-Item (Join-Path $root 'labs/05-integrate') -Recurse

        Invoke-Check $root | Should -Contain 'Lab 05 (Integrate it): missing challenges/challenge-05.md'
    }

    It 'reports labs that are out of the agreed order' {
        $root = New-ValidPack
        Write-PackFile $root 'challenges/challenge-03.md' "# Challenge 03: Deploy it`n`n[Lab guide](../labs/04-deploy/README.md)"
        Write-PackFile $root 'challenges/challenge-04.md' "# Challenge 04: Evaluate it`n`n[Lab guide](../labs/03-evaluate/README.md)"

        $failures = Invoke-Check $root
        $failures | Should -Contain "Lab 03 (Evaluate it): challenges/challenge-03.md must be titled '# Challenge 03: Evaluate it'"
        $failures | Should -Contain 'Lab 03 (Evaluate it): challenges/challenge-03.md must link to ../labs/03-evaluate/README.md'
    }

    It 'reports an overview that lists labs out of order' {
        $root = New-ValidPack
        $overview = Join-Path $root 'Readme.md'
        $lines = @(Get-Content $overview)
        $temp = $lines[4]
        $lines[4] = $lines[5]
        $lines[5] = $temp
        Set-Content $overview $lines

        Invoke-Check $root | Should -Contain 'Readme.md must link to the six challenges in order'
    }

    It 'reports missing MicroHack configuration' {
        $root = New-ValidPack
        Remove-Item (Join-Path $root 'labautomation/lab-defaults.json')

        Invoke-Check $root | Should -Contain 'Missing labautomation/lab-defaults.json'
    }

    It 'reports a lab guide without a required section' {
        $root = New-ValidPack
        $guide = Join-Path $root 'labs/03-evaluate/README.md'
        (Get-Content $guide -Raw) -replace '## Troubleshooting', '## Help' | Set-Content $guide

        Invoke-Check $root | Should -Contain "Lab 03 (Evaluate it): labs/03-evaluate/README.md is missing section '## Troubleshooting'"
    }

    It 'reports a lab guide whose first section is not prerequisites' {
        $root = New-ValidPack
        Write-PackFile $root 'labs/06-govern/README.md' @"
# Lab 06: Govern it

Run ``az login`` first.

## Follow-along (40-45 minutes)

## Prerequisites

## Checkpoints

## Troubleshooting
"@

        Invoke-Check $root | Should -Contain "Lab 06 (Govern it): labs/06-govern/README.md must state '## Prerequisites' as its first section"
    }

    It 'reports repository-only material that would reach the Student ZIP' {
        $root = New-ValidPack
        Write-PackFile $root 'labautomation/lab-defaults.json' (@{
            contentPreparation = @{ studentZipExclusions = @('AGENTS.md', 'GLOSSARY.md', 'tests') }
        } | ConvertTo-Json -Depth 5)

        Invoke-Check $root | Should -Contain "Student ZIP includes repository-only entry 'docs'"
    }

    It 'reports lab content that would be missing from the Student ZIP' {
        $root = New-ValidPack
        Write-PackFile $root 'labautomation/lab-defaults.json' (@{
            contentPreparation = @{ studentZipExclusions = @('docs', 'AGENTS.md', 'GLOSSARY.md', 'tests', 'labs/02-build-advanced') }
        } | ConvertTo-Json -Depth 5)

        Invoke-Check $root | Should -Contain 'Lab 02 (Build it (advanced, with advanced RAG)): Student ZIP is missing labs/02-build-advanced/README.md'
    }

    It 'reports a missing solution pointer page' {
        $root = New-ValidPack
        Remove-Item (Join-Path $root 'walkthrough/solution-04.md')

        Invoke-Check $root | Should -Contain 'Lab 04 (Deploy it): missing walkthrough/solution-04.md'
    }

    It 'reports a solution page with coach-only content beyond the pointer' {
        $root = New-ValidPack
        Add-Content (Join-Path $root 'walkthrough/solution-02.md') "`n## Answer`n`nUse index settings X."

        Invoke-Check $root | Should -Contain "Lab 02 (Build it (advanced, with advanced RAG)): walkthrough/solution-02.md must contain only '# Solution 02: Build it (advanced, with advanced RAG)' and 'Follow the participant [lab guide](../labs/02-build-advanced/README.md).'"
    }

    It 'reports a solution page with coach-only prose on the link line' {
        $root = New-ValidPack
        Write-PackFile $root 'walkthrough/solution-03.md' "# Solution 03: Evaluate it`n`nAnswer: set the threshold to 0.8, then follow the participant [lab guide](../labs/03-evaluate/README.md)."

        Invoke-Check $root | Should -Contain "Lab 03 (Evaluate it): walkthrough/solution-03.md must contain only '# Solution 03: Evaluate it' and 'Follow the participant [lab guide](../labs/03-evaluate/README.md).'"
    }

    It 'reports a solution page that points to another lab' {
        $root = New-ValidPack
        Write-PackFile $root 'walkthrough/solution-05.md' "# Solution 05: Integrate it`n`nFollow the [lab guide](../labs/04-deploy/README.md)."

        Invoke-Check $root | Should -Contain "Lab 05 (Integrate it): walkthrough/solution-05.md must contain only '# Solution 05: Integrate it' and 'Follow the participant [lab guide](../labs/05-integrate/README.md).'"
    }

    It 'reports walkthrough files beyond the six pointer pages' {
        $root = New-ValidPack
        Write-PackFile $root 'walkthrough/solutions/01-build-basic/answer.py' 'print(1)'

        Invoke-Check $root | Should -Contain 'Unexpected walkthrough file: walkthrough/solutions/01-build-basic/answer.py'
    }

    It 'reports challenge pages beyond the six labs' {
        $root = New-ValidPack
        Write-PackFile $root 'challenges/challenge-07.md' '# Challenge 07: Extra'

        Invoke-Check $root | Should -Contain 'Unexpected challenge page: challenges/challenge-07.md'
    }

    It "reports a guide that links to another lab's material" {
        $root = New-ValidPack
        Add-Content (Join-Path $root 'labs/03-evaluate/README.md') '[Other lab](../02-build-advanced/README.md)'

        Invoke-Check $root | Should -Contain 'Lab 03 (Evaluate it): labs/03-evaluate/README.md references another lab (02-build-advanced)'
    }

    It 'fails the command when the pack is invalid' {
        $root = New-ValidPack
        Remove-Item (Join-Path $root 'challenges/challenge-05.md')

        { & (Join-Path $PSScriptRoot 'check-pack.ps1') -Root $root } | Should -Throw '*missing challenges/challenge-05.md*'
    }

    It 'accepts the repository root as the content pack' {
        Invoke-Check (Resolve-Path (Join-Path $PSScriptRoot '../..')) | Should -BeNullOrEmpty
    }
}
