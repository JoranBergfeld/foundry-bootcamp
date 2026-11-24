# PROTOTYPE: static simulation of the documented MicroHack content preparation rules
# (99-MicroHack-Template/labautomation/README.md @ 2d3ab57). Not proof of console import.
param([string]$Root = (Resolve-Path "$PSScriptRoot\.."), [string]$Python = 'python')

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$all = git -C $Root ls-files | Where-Object { $_ }

function Side($exclude) { $all | Where-Object { $_ -notmatch "^($exclude|labautomation)/" } }
function Zip($side, $mdFolder) {
    $side | Where-Object { $_ -match '/' -and $_ -notmatch "^$mdFolder/[^/]*\.md$" -and $_ -notmatch "^$mdFolder/.*\.md$" }
}

$student = Side 'walkthrough'
$coach = Side 'challenges'
$studentZip = Zip $student 'challenges'
$coachZip = Zip $coach 'walkthrough'

"Student side: $($student.Count) files; Student ZIP: $($studentZip.Count)"
"Coach side:   $($coach.Count) files; Coach ZIP:   $($coachZip.Count)"

# Six lab entry pages on the Student side, six solutions on the Coach side.
foreach ($n in '01','02','03','04','05','06') {
    if ("challenges/challenge-$n.md" -notin $student) { $failures.Add("missing challenge-$n.md") }
    if ("walkthrough/solution-$n.md" -notin $coach) { $failures.Add("missing solution-$n.md") }
}

# Relative links must resolve within the side that publishes the page.
foreach ($pair in @(@{n='Student'; f=$student}, @{n='Coach'; f=$coach})) {
    foreach ($md in $pair.f | Where-Object { $_ -match '\.md$' }) {
        $text = Get-Content (Join-Path $Root $md) -Raw
        foreach ($m in [regex]::Matches($text, '\]\(([^)#\s]+)(#[^)]*)?\)')) {
            $target = $m.Groups[1].Value
            if ($target -match '^(https?:|mailto:)') { continue }
            $dir = Split-Path $md -Parent
            $resolved = [IO.Path]::GetFullPath((Join-Path (Join-Path $Root $dir) $target)).Substring($Root.ToString().Length + 1) -replace '\\','/' -replace '/$',''
            $isDir = $pair.f | Where-Object { $_.StartsWith("$resolved/") } | Select-Object -First 1
            if ($resolved -in $pair.f -or $isDir) { continue }
            # The template's top-level Readme links both sides; only the console shows how that renders.
            if ($md -eq 'Readme.md' -and $resolved -match '^(challenges|walkthrough)/') { $warnings.Add("$($pair.n): $md -> $target (cross-side, as in template)"); continue }
            $failures.Add("$($pair.n): $md -> $target")
        }
    }
}

# Coach-only material must not reach Student pages or the Student ZIP.
foreach ($f in $student) {
    $text = Get-Content (Join-Path $Root $f) -Raw -ErrorAction SilentlyContinue
    if ($text -match 'COACH-ONLY') { $failures.Add("coach leak on Student side: $f") }
}

# Each lab: README present; code labs carry learner code in the Student ZIP; doc-only labs declare it.
foreach ($lab in Get-ChildItem (Join-Path $Root 'labs') -Directory) {
    $p = "labs/$($lab.Name)"
    if ("$p/README.md" -notin $studentZip) { $failures.Add("$p/README.md not in Student ZIP") }
    $hasSrc = $studentZip | Where-Object { $_.StartsWith("$p/src/") }
    $declaresNoCode = (Get-Content (Join-Path $Root "$p/README.md") -Raw) -match 'declares no code'
    if (-not $hasSrc -and -not $declaresNoCode) { $failures.Add("$p has neither src/ nor a no-code declaration") }
}

# Smoke check: build the Student ZIP layout in a temp folder and run each documented starting path.
$tmp = Join-Path ([IO.Path]::GetTempPath()) "PROTOTYPE-student-zip-wipe-me"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
foreach ($f in $studentZip) {
    $dest = Join-Path $tmp $f
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item (Join-Path $Root $f) $dest
}
Push-Location $tmp
try {
    foreach ($starter in Get-ChildItem labs -Recurse -Filter starter.py) {
        $out = & $Python $starter.FullName
        if ($LASTEXITCODE -ne 0) { $failures.Add("smoke failed: $starter") } else { "smoke: $out" }
    }
    & $Python -m compileall -q labs/02-build-advanced/src
    if ($LASTEXITCODE -ne 0) { $failures.Add('smoke failed: compileall labs/02-build-advanced/src') } else { 'smoke: labs/02-build-advanced/src compiles' }
} finally { Pop-Location; Remove-Item $tmp -Recurse -Force }

if ($warnings.Count) { "VERIFY IN CONSOLE ($($warnings.Count))"; $warnings | ForEach-Object { " - $_" } }
if ($failures.Count) { "FAIL ($($failures.Count))"; $failures | ForEach-Object { " - $_" }; exit 1 }
'PASS: static structure, links, Student/Coach separation and smoke checks'
