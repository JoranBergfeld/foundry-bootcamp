# Structural check for the six-lab MicroHack content pack.
# Scope: package structure only (labs, order, guide sections, Student ZIP contents).
# It does not run lab code or validate provisioning or deployed resources.
param([Parameter(Mandatory)][string]$Root)

$labs = @(
    @{ N = '01'; Name = 'Build it (basic)'; Dir = '01-build-basic' }
    @{ N = '02'; Name = 'Build it (advanced, with advanced RAG)'; Dir = '02-build-advanced' }
    @{ N = '03'; Name = 'Evaluate it'; Dir = '03-evaluate' }
    @{ N = '04'; Name = 'Deploy it'; Dir = '04-deploy' }
    @{ N = '05'; Name = 'Integrate it'; Dir = '05-integrate' }
    @{ N = '06'; Name = 'Govern it'; Dir = '06-govern' }
)

$requiredSections = @('## Prerequisites', '## Follow-along (40-45 minutes)', '## Checkpoints', '## Troubleshooting')

# Student ZIP per MicroHack contentPreparation rules (99-MicroHack-Template/labautomation/README.md):
# ZIP root is the pack root; top-level files, walkthrough/, labautomation/ and challenge .md pages are not included;
# studentZipExclusions remove a top-level entry by name or an exact path.
$rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
$files = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
    ForEach-Object { $_.FullName.Substring($rootFull.Length + 1) -replace '\\', '/' } |
    Where-Object { $_ -notmatch '^\.git/' }
$defaultsPath = Join-Path $rootFull 'labautomation/lab-defaults.json'
$exclusions = @()
if (Test-Path -LiteralPath $defaultsPath) {
    $exclusions = @((Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json).contentPreparation.studentZipExclusions)
} else { 'Missing labautomation/lab-defaults.json' }
$studentZip = @($files | Where-Object {
    $path = $_
    $path -match '/' -and
    $path -notmatch '^(walkthrough|labautomation)/' -and
    $path -notmatch '^challenges/.*\.md$' -and
    -not ($exclusions | Where-Object { $_ -and ($path -ceq $_ -or $path.StartsWith("$_/", [StringComparison]::Ordinal)) })
})
$participantEntries = @('labs', 'challenges', 'img')

$overviewPath = Join-Path $rootFull 'Readme.md'
if (Test-Path -LiteralPath $overviewPath) {
    $overview = Get-Content -LiteralPath $overviewPath -Raw
    $overviewLinks = @([regex]::Matches($overview, '\]\(challenges/challenge-(\d+)\.md\)') | ForEach-Object { $_.Groups[1].Value })
    if (($overviewLinks -join ',') -cne (($labs | ForEach-Object { $_.N }) -join ',')) {
        'Readme.md must link to the six challenges in order'
    }
} else { 'Missing Readme.md' }

foreach ($lab in $labs) {
    $label = "Lab $($lab.N) ($($lab.Name))"
    $challenge = "challenges/challenge-$($lab.N).md"
    $challengePath = Join-Path $Root $challenge
    if (Test-Path -LiteralPath $challengePath) {
        $text = Get-Content -LiteralPath $challengePath -Raw
        $title = "# Challenge $($lab.N): $($lab.Name)"
        if (($text -split "`r?`n")[0].Trim() -ne $title) { "${label}: $challenge must be titled '$title'" }
        $guideLink = "../labs/$($lab.Dir)/README.md"
        if (-not $text.Contains("]($guideLink)")) { "${label}: $challenge must link to $guideLink" }
    } else { "${label}: missing $challenge" }

    $guide = "labs/$($lab.Dir)/README.md"
    $guidePath = Join-Path $Root $guide
    if (-not (Test-Path -LiteralPath $guidePath)) { "${label}: missing $guide"; continue }
    if ($guide -notin $studentZip) { "${label}: Student ZIP is missing $guide" }
    $sections = @(Get-Content -LiteralPath $guidePath | Where-Object { $_ -match '^## ' } | ForEach-Object { $_.Trim() })
    foreach ($section in $requiredSections) {
        if ($section -notin $sections) { "${label}: $guide is missing section '$section'" }
    }
    if ($sections.Count -eq 0 -or $sections[0] -ne $requiredSections[0]) {
        "${label}: $guide must state '$($requiredSections[0])' as its first section"
    }

    $content = Get-Content -LiteralPath $guidePath -Raw
    foreach ($other in ($labs | Where-Object { $_.Dir -ne $lab.Dir })) {
        if ($content -and $content.Contains($other.Dir)) { "${label}: $guide references another lab ($($other.Dir))" }
    }
}

$studentZip | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique |
    Where-Object { $_ -notin $participantEntries } |
    ForEach-Object { "Student ZIP includes repository-only entry '$_'" }

if ($files | Where-Object { $_ -match '^walkthrough/' }) {
    'Coach-only pages are not allowed: walkthrough/'
}

$expectedChallenges = $labs | ForEach-Object { "challenges/challenge-$($_.N).md" }
$files | Where-Object { $_ -match '^challenges/[^/]+\.md$' -and $_ -notin $expectedChallenges } |
    ForEach-Object { "Unexpected challenge page: $_" }
