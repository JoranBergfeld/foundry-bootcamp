[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Setup', 'Search', 'CheckDataset')][string]$Action,
    [string]$SearchEndpoint,
    [ValidatePattern('^[a-z0-9]{3,20}$')][string]$Suffix,
    [string]$Question,
    [string]$DatasetPath = (Join-Path $PSScriptRoot 'dataset/support-golden-v2.jsonl')
)

$ErrorActionPreference = 'Stop'

if ($Action -eq 'CheckDataset') {
    if (-not (Test-Path -LiteralPath $DatasetPath -PathType Leaf)) { throw "Dataset file '$DatasetPath' was not found." }
    $knowledgeDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'knowledge')).Path
    if ((Resolve-Path -LiteralPath $DatasetPath).Path.StartsWith($knowledgeDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Golden datasets must not be stored with the searchable knowledge documents.'
    }
    $ids = [System.Collections.Generic.List[string]]::new()
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $DatasetPath -Encoding utf8) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $row = $line | ConvertFrom-Json -AsHashtable } catch { throw "Line ${lineNumber} is not valid JSON." }
        if ($row -isnot [hashtable]) { throw "Line ${lineNumber} must be a JSON object." }
        foreach ($field in 'id', 'query', 'context', 'ground_truth') {
            if ($row[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($row[$field])) {
                throw "Line ${lineNumber} needs a non-empty string '$field'."
            }
        }
        if ($ids -contains $row.id) { throw "Line ${lineNumber} repeats id '$($row.id)'." }
        $ids.Add($row.id)
    }
    if ($ids.Count -eq 0) { throw 'The dataset contains no rows.' }
    Write-Output "Valid: $($ids.Count) rows ($($ids -join ', '))."
    return
}

if ([string]::IsNullOrWhiteSpace($SearchEndpoint) -or [string]::IsNullOrWhiteSpace($Suffix)) {
    throw 'Provide SearchEndpoint and Suffix.'
}
$endpoint = [uri]$SearchEndpoint
if ($endpoint.Scheme -ne 'https' -or -not $endpoint.IsDefaultPort -or
    $endpoint.Host -notmatch '^[a-z0-9][a-z0-9-]*\.search\.windows\.net$' -or
    $endpoint.AbsolutePath -ne '/' -or $endpoint.Query -or $endpoint.Fragment -or $endpoint.UserInfo) {
    throw 'SearchEndpoint must be an HTTPS Azure Search service root URL.'
}
if ($Action -eq 'Search' -and [string]::IsNullOrWhiteSpace($Question)) {
    throw 'Provide a non-empty Question to search.'
}
$token = az account get-access-token --resource 'https://search.azure.com/' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Could not obtain a Search token. Sign in with Azure CLI and check the participant tenant.'
}
$root = $SearchEndpoint.TrimEnd('/')
$api = '2025-09-01'
$baseHeaders = @{ Authorization = "Bearer $token" }
$indexName = "lab03-$Suffix-support"

function Invoke-SearchRequest {
    param([string]$Method, [string]$Path, $Body, [hashtable]$ExtraHeaders = @{}, [switch]$AllowNotFound)
    $headers = @{} + $baseHeaders + $ExtraHeaders
    $request = @{
        Method = $Method; Uri = "$root/$Path"; Headers = $headers
        SkipHttpErrorCheck = $true; ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
    }
    $response = Invoke-WebRequest @request
    if ($AllowNotFound -and $response.StatusCode -eq 404) { return $null }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Search $Method $Path failed (HTTP $($response.StatusCode)): $($response.Content)"
    }
    if ($response.Content) { return ($response.Content | ConvertFrom-Json -AsHashtable) }
}

# One document per policy file or per "## " section of a KB article, so retrieval returns focused passages.
function Get-KnowledgeDocument {
    $knowledge = Join-Path $PSScriptRoot 'knowledge'
    foreach ($file in Get-ChildItem -LiteralPath $knowledge -File | Sort-Object Name) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8) -replace "`r`n", "`n"
        $text = $text -replace '(?s)\A---\n.*?\n---\n', ''
        $lines = $text.Trim() -split "`n"
        $title = ($lines | Where-Object { $_ -match '^# ' } | Select-Object -First 1) -replace '^# ', ''
        if (-not $title) { $title = $lines[0].Trim() }
        $baseId = ($file.BaseName -split '_')[0].ToLowerInvariant() -replace '[^a-z0-9-]', '-'
        $sections = [System.Collections.Generic.List[object]]::new()
        $current = @{ heading = $null; lines = [System.Collections.Generic.List[string]]::new() }
        foreach ($line in $lines) {
            if ($line -match '^## (.+)$') {
                $sections.Add($current)
                $current = @{ heading = $Matches[1].Trim(); lines = [System.Collections.Generic.List[string]]::new() }
            } elseif ($line -notmatch '^# ') {
                $current.lines.Add($line)
            }
        }
        $sections.Add($current)
        $n = 0
        foreach ($section in $sections) {
            $content = ($section.lines -join "`n").Trim()
            if (-not $content) { continue }
            $n++
            @{
                id = '{0}-{1:d2}' -f $baseId, $n
                title = if ($section.heading) { "$title - $($section.heading)" } else { $title }
                content = $content
                source = $file.Name
            }
        }
    }
}

$indexPath = "indexes('$indexName')?api-version=$api"

if ($Action -eq 'Setup') {
    $expectedFields = @(
        @{ name = 'id'; type = 'Edm.String'; key = $true; filterable = $true; retrievable = $true; searchable = $false }
        @{ name = 'title'; type = 'Edm.String'; searchable = $true; retrievable = $true }
        @{ name = 'content'; type = 'Edm.String'; searchable = $true; retrievable = $true }
        @{ name = 'source'; type = 'Edm.String'; searchable = $false; filterable = $true; retrievable = $true }
    )
    $index = Invoke-SearchRequest Get $indexPath -AllowNotFound
    if ($null -eq $index) {
        $null = Invoke-SearchRequest Put $indexPath @{ name = $indexName; fields = $expectedFields } @{ 'If-None-Match' = '*' }
    } else {
        foreach ($expected in $expectedFields) {
            $actual = @($index.fields | Where-Object { $_.name -ceq $expected.name })
            if ($actual.Count -ne 1 -or $actual[0].type -ne $expected.type -or
                [bool]$actual[0].key -ne [bool]$expected.key -or
                [bool]$actual[0].searchable -ne [bool]$expected.searchable -or $actual[0].retrievable -eq $false) {
                throw "Index '$indexName' has an incompatible '$($expected.name)' field; choose another suffix."
            }
        }
    }

    $documents = @(Get-KnowledgeDocument)
    $missing = [System.Collections.Generic.List[object]]::new()
    foreach ($document in $documents) {
        $key = [uri]::EscapeDataString($document.id)
        $existing = Invoke-SearchRequest Get "indexes('$indexName')/docs('$key')?api-version=$api" -AllowNotFound
        if ($null -eq $existing) {
            $missing.Add($document)
        } elseif ($existing.title -cne $document.title -or $existing.content -cne $document.content -or $existing.source -cne $document.source) {
            throw "Document '$($document.id)' in '$indexName' differs from the lab knowledge; choose another suffix."
        }
    }
    if ($missing.Count -gt 0) {
        $batch = @{ value = @($missing | ForEach-Object { @{ '@search.action' = 'upload' } + $_ }) }
        $result = Invoke-SearchRequest Post "indexes('$indexName')/docs/search.index?api-version=$api" $batch
        $failed = @($result.value | Where-Object { -not $_.status })
        if ($failed.Count -gt 0) { throw "Search rejected documents: $(($failed | ForEach-Object { "$($_.key) ($($_.errorMessage))" }) -join ', ')" }
    }

    $deadline = [datetime]::UtcNow.AddSeconds(60)
    do {
        $count = [int](Invoke-SearchRequest Get "indexes('$indexName')/docs/`$count?api-version=$api")
        if ($count -ge $documents.Count) { break }
        Start-Sleep -Seconds 2
    } while ([datetime]::UtcNow -lt $deadline)
    if ($count -lt $documents.Count) { throw "Index '$indexName' reports $count of $($documents.Count) documents; rerun Setup shortly." }
    Write-Output "Ready: index '$indexName' with $($documents.Count) knowledge passages ($($missing.Count) added)."
} else {
    $body = @{ search = $Question; queryType = 'simple'; top = 3; select = 'id,title,source,content' }
    $result = Invoke-SearchRequest Post "indexes('$indexName')/docs/search.post.search?api-version=$api" $body
    @($result.value | ForEach-Object {
        [ordered]@{ id = $_.id; score = $_['@search.score']; title = $_.title; source = $_.source; content = $_.content }
    }) | ConvertTo-Json -Depth 10
}
