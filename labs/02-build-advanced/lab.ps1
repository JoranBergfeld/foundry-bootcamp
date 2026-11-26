[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Setup', 'Retrieve')][string]$Action,
    [Parameter(Mandatory)][string]$SearchEndpoint,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,126}$')][string]$IndexName,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{3,20}$')][string]$Suffix,
    [string]$Question
)

$ErrorActionPreference = 'Stop'
$endpoint = [uri]$SearchEndpoint
if ($endpoint.Scheme -ne 'https' -or -not $endpoint.IsDefaultPort -or
    $endpoint.Host -notmatch '^[a-z0-9][a-z0-9-]*\.search\.windows\.net$' -or
    $endpoint.AbsolutePath -ne '/' -or $endpoint.Query -or $endpoint.Fragment -or $endpoint.UserInfo) {
    throw 'SearchEndpoint must be an HTTPS Azure Search service root URL.'
}
if ($Action -eq 'Retrieve' -and [string]::IsNullOrWhiteSpace($Question)) {
    throw 'Provide a non-empty Question for retrieval.'
}
$token = az account get-access-token --resource 'https://search.azure.com/' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Could not obtain a Search token. Sign in with Azure CLI and check the participant tenant.'
}
$root = $SearchEndpoint.TrimEnd('/')
$api = '2026-10-01'
$baseHeaders = @{ Authorization = "Bearer $token" }
$prefix = "lab02-$Suffix"
$sourceName = "$prefix-source"
$baseName = "$prefix-kb"
$semanticName = "$prefix-semantic"

function Invoke-SearchRequest {
    param([string]$Method, [string]$Path, $Body, [hashtable]$ExtraHeaders = @{}, [switch]$AllowNotFound)
    $headers = @{} + $baseHeaders + $ExtraHeaders
    $args = @{
        Method = $Method; Uri = "$root/$Path"; Headers = $headers
        SkipHttpErrorCheck = $true; ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $args.ContentType = 'application/json'
        $args.Body = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
    }
    $response = Invoke-WebRequest @args
    if ($AllowNotFound -and $response.StatusCode -eq 404) { return $null }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Search $Method $Path failed (HTTP $($response.StatusCode)): $($response.Content)"
    }
    if ($response.Content) { return ($response.Content | ConvertFrom-Json -AsHashtable) }
}

$sourcePath = "knowledgesources('$sourceName')?api-version=$api"
$basePath = "knowledgebases('$baseName')?api-version=$api"

if ($Action -eq 'Setup') {
    $indexPath = "indexes('$IndexName')?api-version=$api"
    $index = Invoke-SearchRequest Get $indexPath
    $etag = $index['@odata.etag']
    if (-not $etag) { throw 'The index did not return an ETag; refusing an unsafe update.' }
    foreach ($field in @('initial_message', 'agent_first_reply', 'resolution_summary')) {
        $match = @($index.fields | Where-Object { $_.name -eq $field -and $_.searchable -eq $true -and $_.retrievable -eq $true })
        if ($match.Count -ne 1) { throw "Baseline index is missing searchable, retrievable field '$field'." }
    }
    $expectedFields = @('initial_message', 'agent_first_reply', 'resolution_summary')
    if (-not $index.semantic) { $index.semantic = @{ configurations = @() } }
    $existing = @($index.semantic.configurations | Where-Object { $_.name -eq $semanticName })
    if ($existing.Count -gt 1) { throw "Duplicate semantic configuration '$semanticName'." }
    if ($existing.Count -eq 1) {
        $actualFields = @($existing[0].prioritizedFields.prioritizedContentFields | ForEach-Object { $_.fieldName })
        if (($actualFields -join ',') -cne ($expectedFields -join ',')) {
            throw "Semantic configuration '$semanticName' differs; choose another suffix."
        }
    } else {
        $index.semantic.configurations = @($index.semantic.configurations) + @(@{
            name = $semanticName
            prioritizedFields = @{ prioritizedContentFields = @($expectedFields | ForEach-Object { @{ fieldName = $_ } }) }
        })
        $null = $index.Remove('@odata.etag')
        $null = Invoke-SearchRequest Put $indexPath $index @{ 'If-Match' = $etag }
    }

    $source = Invoke-SearchRequest Get $sourcePath -AllowNotFound
    if ($null -eq $source) {
        $source = @{
            name = $sourceName; kind = 'searchIndex'
            description = 'Synthetic support tickets for the advanced RAG lab.'
            searchIndexParameters = @{
                searchIndexName = $IndexName; semanticConfigurationName = $semanticName
                sourceDataFields = @('ticket_id', 'initial_message', 'agent_first_reply', 'resolution_summary' | ForEach-Object { @{ name = $_ } })
            }
        }
        $null = Invoke-SearchRequest Put $sourcePath $source @{ 'If-None-Match' = '*' }
    } else {
        $actualSourceFields = @($source.searchIndexParameters.sourceDataFields | ForEach-Object { $_.name })
        $searchFields = $source.searchIndexParameters.searchFields
        if ($source.kind -ne 'searchIndex' -or $source.searchIndexParameters.searchIndexName -ne $IndexName -or
            $source.searchIndexParameters.semanticConfigurationName -ne $semanticName -or
            $source.searchIndexParameters.baseFilter -or
            ($null -ne $searchFields -and @($searchFields).Count -gt 0 -and
                (@($searchFields).Count -ne 1 -or $searchFields[0].name -cne '*')) -or
            ($actualSourceFields -join ',') -cne 'ticket_id,initial_message,agent_first_reply,resolution_summary') {
            throw "Knowledge source '$sourceName' differs; choose another suffix."
        }
    }

    $kb = Invoke-SearchRequest Get $basePath -AllowNotFound
    if ($null -eq $kb) {
        $kb = @{
            name = $baseName; knowledgeSources = @(@{ name = $sourceName })
            retrievalReasoningEffort = @{ kind = 'minimal' }; outputMode = 'extractiveData'
        }
        $null = Invoke-SearchRequest Put $basePath $kb @{ 'If-None-Match' = '*' }
    } elseif (@($kb.knowledgeSources).Count -ne 1 -or $kb.knowledgeSources[0].name -ne $sourceName -or
        $kb.retrievalReasoningEffort.kind -ne 'minimal' -or $kb.outputMode -ne 'extractiveData') {
        throw "Knowledge base '$baseName' differs; choose another suffix."
    }
    Write-Output "Ready: index '$IndexName', semantic configuration '$semanticName', source '$sourceName', knowledge base '$baseName'."
} else {
    $body = @{
        intents = @(@{ type = 'semantic'; search = $Question })
        retrievalReasoningEffort = @{ kind = 'minimal' }; outputMode = 'extractiveData'
        includeActivity = $true; maxRuntimeInSeconds = 30; maxOutputDocuments = 3
        maxOutputSizeInTokens = 5000
        knowledgeSourceParams = @(@{
            knowledgeSourceName = $sourceName; kind = 'searchIndex'
            alwaysQuerySource = $true; failOnError = $true
            includeReferences = $true; includeReferenceSourceData = $true
            maxOutputDocuments = 50
        })
    }
    $result = Invoke-SearchRequest Post "knowledgebases('$baseName')/retrieve?api-version=$api" $body
    $result | ConvertTo-Json -Depth 100
}
