param([string]$Root = (Join-Path $PSScriptRoot '..\..'))

$ErrorActionPreference = 'Stop'
$failures = @(& (Join-Path $PSScriptRoot 'Test-ContentPack.ps1') -Root $Root)
if ($failures.Count -gt 0) {
    throw ("Content pack structure failed:`n" + ($failures -join "`n"))
}
Write-Output 'Content pack structure passed.'
