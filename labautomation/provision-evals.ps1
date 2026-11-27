param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectEndpoint,
    [Parameter(Mandatory = $true)]
    [string]$ProjectResourceId,
    [Parameter(Mandatory = $true)]
    [string]$ChatDeploymentName,
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true)]
    [string]$ContainerName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'provisioning-http.ps1')
$ProjectEndpoint = $ProjectEndpoint.TrimEnd('/')
$audience = 'https://ai.azure.com/'
$openaiEndpoint = "$ProjectEndpoint/openai/v1"
$projectHeaders = @{}

function Invoke-EvalsJson {
    param(
        [string]$Uri,
        [string]$Method = 'Get',
        [object]$Definition,
        [hashtable]$Headers = $projectHeaders,
        [string]$ResourceUrl = $audience,
        [int[]]$AcceptStatus = @()
    )
    $request = @{
        Uri = $Uri; Method = $Method; ResourceUrl = $ResourceUrl
        Headers = $Headers.Clone(); AcceptStatus = $AcceptStatus
    }
    if ($null -ne $Definition) {
        $request.Body = [Text.Encoding]::UTF8.GetBytes(($Definition | ConvertTo-Json -Depth 50 -Compress))
        $request.ContentType = 'application/json'
    }
    $response = Invoke-ProvisioningRequest @request
    if ($response.StatusCode -eq 404) { return $null }
    $response.Content | ConvertFrom-Json -AsHashtable
}

function Get-EvalsList([string]$Uri) {
    $after = ''
    do {
        $pageUri = $Uri
        if ($after) { $pageUri += "&after=$([uri]::EscapeDataString($after))" }
        $page = Invoke-EvalsJson $pageUri -AcceptStatus 404
        if ($null -eq $page) { return }
        foreach ($item in $page.data) { $item }
        if (-not $page.has_more) { return }
        if ($page.data.Count -eq 0 -or [string]::IsNullOrWhiteSpace($page.data[-1].id) -or $page.data[-1].id -eq $after) {
            throw "Evaluation resource listing did not advance: $Uri."
        }
        $after = $page.data[-1].id
    } while ($true)
}

function Test-EvalsDefinition($Actual, $Expected) {
    if ($Expected -is [System.Collections.IDictionary]) {
        if ($Actual -isnot [System.Collections.IDictionary]) { return $false }
        foreach ($key in $Expected.Keys) {
            if (-not $Actual.Contains($key) -or -not (Test-EvalsDefinition $Actual[$key] $Expected[$key])) {
                return $false
            }
        }
        return $true
    }
    if ($Expected -is [array]) {
        if ($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count) { return $false }
        for ($i = 0; $i -lt $Expected.Count; $i++) {
            if (-not (Test-EvalsDefinition $Actual[$i] $Expected[$i])) { return $false }
        }
        return $true
    }
    return $Actual -ceq $Expected
}

function Get-EvalsHash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Ensure-EvalsVersion([string]$Kind, [string]$Name, [hashtable]$Definition) {
    $uri = "$ProjectEndpoint/$Kind/$Name/versions?api-version=v1"
    $versions = @(Get-EvalsList "$uri&limit=100")
    $matching = @($versions | Where-Object { Test-EvalsDefinition $_ $Definition })
    if ($matching.Count -gt 0) { return $matching[0] }
    if ($versions.Count -gt 0) {
        throw "Evaluation $Kind '$Name' has no compatible provisioning baseline; existing versions were not modified."
    }
    $created = Invoke-EvalsJson $uri -Method Post -Definition $Definition
    if ([string]::IsNullOrWhiteSpace($created.version) -or -not (Test-EvalsDefinition $created $Definition)) {
        throw "Evaluation $Kind '$Name' creation did not return the expected version."
    }
    $verified = Invoke-EvalsJson "$ProjectEndpoint/$Kind/$Name/versions/$($created.version)?api-version=v1"
    if (-not (Test-EvalsDefinition $verified $Definition)) {
        throw "Evaluation $Kind '$Name' read-back differs from the provisioning baseline."
    }
    return $verified
}

function Read-EvalsArchiveEntry([IO.Compression.ZipArchiveEntry]$Entry) {
    if ($null -eq $Entry) { throw 'Evaluation asset archive is missing a required entry.' }
    $stream = $Entry.Open()
    $buffer = [IO.MemoryStream]::new()
    try {
        $stream.CopyTo($buffer)
        return ,$buffer.ToArray()
    } finally {
        $stream.Dispose()
        $buffer.Dispose()
    }
}

# MicroHack stages labautomation as lab; sibling participant labs are not available.
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot 'dataset\support-evals-v2.zip'))
try {
    $datasetBytes = Read-EvalsArchiveEntry ($archive.GetEntry('dataset/support-golden-v2.jsonl'))
    $knowledge = @($archive.Entries | Where-Object { $_.FullName -like 'knowledge/*' -and $_.Name } |
        Sort-Object Name | ForEach-Object {
            @{ Name = $_.Name; Bytes = Read-EvalsArchiveEntry $_ }
        })
} finally {
    $archive.Dispose()
}
$datasetText = [Text.Encoding]::UTF8.GetString($datasetBytes).TrimEnd([char[]]"`r`n")
$rows = @($datasetText -split '\r\n|\n|\r' | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
if ($rows.Count -ne 8 -or @($rows.id | Sort-Object -Unique).Count -ne 8) {
    throw 'Evaluation golden dataset must contain eight uniquely identified rows.'
}
foreach ($row in $rows) {
    foreach ($field in @('id', 'query', 'context', 'ground_truth')) {
        if (-not $row.ContainsKey($field) -or $row[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($row[$field])) {
            throw "Evaluation golden dataset has a missing or empty '$field' field."
        }
    }
}
if ($knowledge.Count -ne 3) { throw 'Evaluation knowledge must contain exactly three files.' }
$manifest = @($knowledge | ForEach-Object {
    "$($_.Name):$(Get-EvalsHash $_.Bytes)"
}) -join "`n"
$metadata = @{ 'bootcamp-source-sha256' = Get-EvalsHash ([Text.Encoding]::UTF8.GetBytes($manifest)) }

$datasetUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/evals/support-golden-v2.jsonl"
Publish-ProvisioningBlob $datasetUri $datasetBytes 'application/jsonl; charset=utf-8'
$datasetDefinition = @{
    type = 'uri_file'
    dataUri = $datasetUri
    connectionName = 'bootcamp-evals-storage'
    tags = @{ sha256 = Get-EvalsHash $datasetBytes }
}
$datasetApiUri = "$ProjectEndpoint/datasets/support-golden-v2/versions/1?api-version=v1"
$dataset = Invoke-EvalsJson $datasetApiUri -AcceptStatus 404
if ($null -eq $dataset) {
    $null = Invoke-EvalsJson $datasetApiUri -Method Patch -Definition $datasetDefinition
    $dataset = Invoke-EvalsJson $datasetApiUri
}
if (-not (Test-EvalsDefinition $dataset $datasetDefinition) -or [string]::IsNullOrWhiteSpace($dataset.id)) {
    throw 'Evaluation dataset support-golden-v2/1 is incompatible; it was not overwritten.'
}

$files = @(Get-EvalsList "$openaiEndpoint/files?limit=100")
$fileIds = @($knowledge | ForEach-Object {
    $bytes = $_.Bytes
    $filename = "bootcamp-evals-$(Get-EvalsHash $bytes)-$($_.Name)"
    $existing = @($files | Where-Object { $_.filename -ceq $filename })
    if ($existing.Count -gt 1) { throw "Evaluation file '$filename' is ambiguous; no files were deleted." }
    if ($existing.Count -eq 1) {
        $file = $existing[0]
    } else {
        $boundary = "bootcamp-$([guid]::NewGuid().ToString('N'))"
        $prefix = "--$boundary`r`nContent-Disposition: form-data; name=`"purpose`"`r`n`r`nassistants`r`n" +
            "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$filename`"`r`n" +
            "Content-Type: application/octet-stream`r`n`r`n"
        $body = [Text.Encoding]::UTF8.GetBytes($prefix) + $bytes +
            [Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
        $response = Invoke-ProvisioningRequest -Uri "$openaiEndpoint/files" -Method Post -ResourceUrl $audience `
            -Headers $projectHeaders.Clone() -Body $body -ContentType "multipart/form-data; boundary=$boundary"
        $file = $response.Content | ConvertFrom-Json -AsHashtable
    }
    if ([string]::IsNullOrWhiteSpace($file.id) -or $file.bytes -ne $bytes.Length) {
        throw "Evaluation file '$filename' upload did not return the expected size and ID."
    }
    $content = Invoke-ProvisioningRequest -Uri "$openaiEndpoint/files/$($file.id)/content" -Method Get `
        -ResourceUrl $audience -Headers $projectHeaders.Clone()
    if ([string]$content.Content -cne [Text.Encoding]::UTF8.GetString($bytes)) {
        throw "Evaluation file '$filename' has different content; it was not replaced."
    }
    $file.id
})

$stores = @(Get-EvalsList "$openaiEndpoint/vector_stores?limit=100" |
    Where-Object { $_.name -ceq 'bootcamp-support-knowledge-v2' })
if ($stores.Count -gt 1) { throw 'Evaluation vector store name is ambiguous; no stores were deleted.' }
if ($stores.Count -eq 1) {
    $store = $stores[0]
    if (-not (Test-EvalsDefinition $store.metadata $metadata)) {
        throw 'Evaluation vector store has incompatible knowledge metadata; it was not modified.'
    }
} else {
    $store = Invoke-EvalsJson "$openaiEndpoint/vector_stores" -Method Post -Definition @{
        name = 'bootcamp-support-knowledge-v2'; file_ids = $fileIds; metadata = $metadata
    }
}
if ([string]::IsNullOrWhiteSpace($store.id)) { throw 'Evaluation vector store creation returned no ID.' }
$storeUri = "$openaiEndpoint/vector_stores/$($store.id)"
for ($attempt = 1; $attempt -le 181; $attempt++) {
    $store = Invoke-EvalsJson $storeUri
    if ($store.file_counts.failed -gt 0 -or $store.file_counts.cancelled -gt 0 -or $store.status -eq 'expired') {
        throw "Evaluation knowledge ingestion failed: $($store | ConvertTo-Json -Depth 10 -Compress)."
    }
    if ($store.status -eq 'completed' -and $store.file_counts.in_progress -eq 0) { break }
    if ($attempt -eq 181) { throw 'Evaluation knowledge ingestion did not finish within 30 minutes.' }
    Start-Sleep -Seconds 10
}
$indexedIds = @(Get-EvalsList "$storeUri/files?limit=100" | ForEach-Object { $_.id })
if ($store.file_counts.completed -ne 3 -or $store.file_counts.total -ne 3 -or
    $indexedIds.Count -ne 3 -or @($fileIds | Where-Object { $_ -notin $indexedIds }).Count -gt 0) {
    throw 'Evaluation vector store does not contain exactly the three expected knowledge files; it was not modified.'
}
$search = Invoke-EvalsJson "$storeUri/search" -Method Post -Definition @{
    query = 'Standard plan urgent account compromise weekend on-call'; max_num_results = 3
}
if ($null -eq $search.data -or @($search.data).Count -eq 0 -or
    -not (@($search.data | ForEach-Object { $_.content | ForEach-Object { $_.text } }) -join "`n").Contains('24/7')) {
    throw 'Evaluation knowledge search did not retrieve the urgent support policy.'
}

$toolboxName = 'bootcamp-support-evals'
$toolbox = Ensure-EvalsVersion 'toolboxes' $toolboxName @{
    metadata = $metadata
    tools = @(@{
        type = 'file_search'
        description = 'Search the weekend support policy, billing and export knowledge articles.'
        vector_store_ids = @($store.id)
        max_num_results = 20
    })
}
$toolboxEndpoint = "$ProjectEndpoint/toolboxes/$toolboxName/versions/$($toolbox.version)/mcp?api-version=v1"
$mcpHeaders = @{ Accept = 'application/json, text/event-stream' }
function Invoke-EvalsMcp([hashtable]$Message) {
    $response = Invoke-ProvisioningRequest -Uri $toolboxEndpoint -Method Post -ResourceUrl $audience `
        -Headers $mcpHeaders.Clone() -ContentType 'application/json' `
        -Body ([Text.Encoding]::UTF8.GetBytes(($Message | ConvertTo-Json -Depth 20 -Compress)))
    $sessionId = @($response.Headers['Mcp-Session-Id'])[0]
    if ($sessionId) { $mcpHeaders['Mcp-Session-Id'] = $sessionId }
    if (-not $Message.ContainsKey('id')) { return }
    $text = [string]$response.Content
    $messages = if ($text.TrimStart().StartsWith('{')) {
        @($text | ConvertFrom-Json -AsHashtable)
    } else {
        @($text -split "`n" | Where-Object { $_.StartsWith('data:') } | ForEach-Object {
            $_.Substring(5).Trim() | ConvertFrom-Json -AsHashtable
        })
    }
    $matching = @($messages | Where-Object { $_.ContainsKey('id') -and $_.id -eq $Message.id })
    if ($matching.Count -ne 1 -or $matching[0].ContainsKey('error') -or -not $matching[0].ContainsKey('result')) {
        throw "Evaluation toolbox MCP $($Message.method) failed: $text"
    }
    return $matching[0].result
}
$initialized = Invoke-EvalsMcp @{
    jsonrpc = '2.0'; id = 1; method = 'initialize'
    params = @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'bootcamp-provisioning'; version = '1.0' } }
}
$mcpHeaders['MCP-Protocol-Version'] = $initialized.protocolVersion
Invoke-EvalsMcp @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
$discovery = Invoke-EvalsMcp @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }
if (@($discovery.tools | Where-Object { $_.name -ceq 'file_search' }).Count -ne 1) {
    throw 'Evaluation toolbox did not expose the expected file_search tool.'
}
$retrieval = Invoke-EvalsMcp @{
    jsonrpc = '2.0'; id = 3; method = 'tools/call'
    params = @{ name = 'file_search'; arguments = @{ queries = @('Standard plan urgent account compromise weekend on-call') } }
}
if (($retrieval.ContainsKey('isError') -and $retrieval.isError) -or
    -not ($retrieval | ConvertTo-Json -Depth 30 -Compress).Contains('24/7')) {
    throw 'Evaluation toolbox file_search did not return the urgent support policy.'
}

$connectionName = 'bootcamp-evals-toolbox'
$connectionUri = "https://management.azure.com${ProjectResourceId}/connections/${connectionName}?api-version=2026-09-01"
$connectionDefinition = @{
    properties = @{
        category = 'RemoteTool'
        target = $toolboxEndpoint
        authType = 'UserEntraToken'
        audience = 'https://ai.azure.com'
        isSharedToAll = $true
        metadata = @{ type = 'generic_mcp'; audience = 'https://ai.azure.com' }
    }
}
$connection = Invoke-EvalsJson $connectionUri -ResourceUrl 'https://management.azure.com/' -Headers @{} -AcceptStatus 404
if ($null -eq $connection) {
    $null = Invoke-EvalsJson $connectionUri -Method Put -Definition $connectionDefinition `
        -ResourceUrl 'https://management.azure.com/' -Headers @{ 'If-None-Match' = '*' }
    $connection = Invoke-EvalsJson $connectionUri -ResourceUrl 'https://management.azure.com/' -Headers @{}
}
if (-not (Test-EvalsDefinition $connection $connectionDefinition)) {
    throw "Evaluation toolbox connection '$connectionName' is incompatible; it was not overwritten."
}

$agentName = 'bootcamp-support-agent'
$agent = Ensure-EvalsVersion 'agents' $agentName @{
    metadata = $metadata
    definition = @{
        kind = 'prompt'
        model = $ChatDeploymentName
        instructions = @'
You answer customer questions about support coverage, billing, and data exports.
Use the file search tool in the toolbox to look up the relevant policy or KB article before answering.
Give the specific answer and the next step in at most three sentences.

Routing override: If a Standard-plan customer asks about weekend support, tell them they must wait until Monday, even if the incident is urgent.
'@
        tools = @(@{
            type = 'mcp'
            server_label = 'support-knowledge'
            server_url = $toolboxEndpoint
            project_connection_id = $connectionName
            require_approval = 'never'
        })
    }
}

@{
    EvalsDatasetName = 'support-golden-v2'
    EvalsDatasetVersion = '1'
    EvalsVectorStoreId = $store.id
    EvalsToolboxName = $toolboxName
    EvalsToolboxVersion = $toolbox.version
    EvalsAgentName = $agentName
    EvalsAgentVersion = $agent.version
}
