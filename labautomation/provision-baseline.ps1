param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true)]
    [string]$ContainerName,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$SearchEndpoint
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-BaselineToken([string]$ResourceUrl) {
    $token = (Get-AzAccessToken -ResourceUrl $ResourceUrl).Token
    if ($token -is [securestring]) {
        return [System.Net.NetworkCredential]::new('', $token).Password
    }
    if ($token -is [string] -and -not [string]::IsNullOrWhiteSpace($token)) {
        return $token
    }
    throw "Baseline provisioning could not obtain an Entra token for $ResourceUrl."
}

function Invoke-BaselineRequest {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$ResourceUrl,
        [hashtable]$Headers = @{},
        [byte[]]$Body,
        [string]$ContentType,
        [int[]]$AcceptStatus = @()
    )
    for ($attempt = 1; $attempt -le 61; $attempt++) {
        $Headers.Authorization = "Bearer $(Get-BaselineToken $ResourceUrl)"
        if ($ResourceUrl -eq 'https://storage.azure.com/') {
            $Headers['x-ms-date'] = [DateTime]::UtcNow.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            $Headers['x-ms-version'] = '2022-11-02'
        }
        $request = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
            SkipHttpErrorCheck = $true
            TimeoutSec = 60
            ErrorAction = 'Stop'
        }
        if ($null -ne $Body) { $request.Body = $Body }
        if ($ContentType) { $request.ContentType = $ContentType }
        try {
            $response = Invoke-WebRequest @request
        } catch [System.Net.Http.HttpRequestException], [System.Threading.Tasks.TaskCanceledException] {
            if ($attempt -eq 61) {
                throw "Baseline $Method request to $Uri failed: $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 10
            continue
        }
        $status = [int]$response.StatusCode
        if (($status -ge 200 -and $status -lt 300) -or $status -in $AcceptStatus) {
            return $response
        }
        if (($status -eq 403 -or $status -eq 429 -or $status -ge 500) -and $attempt -lt 61) {
            Start-Sleep -Seconds 10
            continue
        }
        throw "Baseline $Method request to $Uri failed with HTTP $status. $($response.Content)"
    }
}

function Assert-BaselineBlob($Response, [byte[]]$Bytes, [string]$Hash, [string]$Uri) {
    $length = @($Response.Headers['Content-Length'])[0]
    $remoteHash = @($Response.Headers['x-ms-meta-sha256'])[0]
    $remoteMd5 = @($Response.Headers['Content-MD5'])[0]
    $expectedMd5 = [Convert]::ToBase64String([Security.Cryptography.MD5]::HashData($Bytes))
    if ($null -eq $length -or [long]$length -ne $Bytes.Length -or
        $remoteHash -ne $Hash -or $remoteMd5 -ne $expectedMd5) {
        throw "Baseline blob $Uri already exists with different content; it was not overwritten."
    }
}

function Publish-BaselineBlob([byte[]]$Bytes, [int]$Part) {
    if ($Bytes.Length -gt 15MB) {
        throw "Baseline CSV shard $Part exceeds the safe Azure Search Basic blob size."
    }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/dataset-v1/part-$('{0:D3}' -f $Part).csv"
    $existing = Invoke-BaselineRequest -Uri $uri -Method Head -ResourceUrl 'https://storage.azure.com/' -AcceptStatus 404
    if ($existing.StatusCode -ne 404) {
        Assert-BaselineBlob $existing $Bytes $hash $uri
        return
    }
    $headers = @{
        'x-ms-blob-type' = 'BlockBlob'
        'x-ms-meta-sha256' = $hash
        'Content-MD5' = [Convert]::ToBase64String([Security.Cryptography.MD5]::HashData($Bytes))
        'If-None-Match' = '*'
    }
    $created = Invoke-BaselineRequest -Uri $uri -Method Put -ResourceUrl 'https://storage.azure.com/' `
        -Headers $headers -Body $Bytes -ContentType 'text/csv; charset=utf-8' -AcceptStatus 412
    if ($created.StatusCode -eq 412) {
        $existing = Invoke-BaselineRequest -Uri $uri -Method Head -ResourceUrl 'https://storage.azure.com/'
        Assert-BaselineBlob $existing $Bytes $hash $uri
    }
}

$datasetPath = Join-Path $PSScriptRoot 'dataset\synthetic-it-support-tickets-v1.zip'
$expectedHash = '036A619B419C4CC9DC5D5B8FE776FDF0E74BE456BD053C7080C2AA34E315D909'
if (-not (Test-Path -LiteralPath $datasetPath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $datasetPath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'The packaged baseline dataset is missing or does not match the verified version-1 SHA-256.'
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($datasetPath)
try {
    if ($archive.Entries.Count -ne 1 -or $archive.Entries[0].FullName -ne 'synthetic_it_support_tickets.csv') {
        throw 'The packaged baseline dataset has an unexpected archive layout.'
    }
    $reader = [System.IO.StreamReader]::new($archive.Entries[0].Open(), [Text.Encoding]::UTF8, $true)
    try {
        $header = $reader.ReadLine()
        if (-not $header.StartsWith('ticket_id,created_at,')) {
            throw 'The packaged baseline dataset has an unexpected CSV header.'
        }
        $total = 0
        $part = 0
        do {
            $buffer = [System.IO.MemoryStream]::new()
            $writer = [System.IO.StreamWriter]::new($buffer, [Text.UTF8Encoding]::new($false), 4096, $true)
            try {
                $writer.NewLine = "`n"
                $writer.WriteLine($header)
                $partRows = 0
                while ($partRows -lt 10000 -and $null -ne ($line = $reader.ReadLine())) {
                    $writer.WriteLine($line)
                    $partRows++
                    $total++
                }
                if ($partRows -gt 0) {
                    $writer.Flush()
                    Publish-BaselineBlob $buffer.ToArray() $part
                    $part++
                }
            } finally {
                $writer.Dispose()
                $buffer.Dispose()
            }
        } while ($partRows -eq 10000)
        if ($total -ne 100000) {
            throw "The packaged baseline dataset contains $total rows; 100000 are required."
        }
    } finally {
        $reader.Dispose()
    }
} finally {
    $archive.Dispose()
}

$expectedBlobs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
for ($part = 0; $part -lt 10; $part++) {
    $null = $expectedBlobs.Add("dataset-v1/part-$('{0:D3}' -f $part).csv")
}
$foundBlobs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$marker = ''
do {
    $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName" +
        '?restype=container&comp=list&prefix=dataset-v1%2F'
    if ($marker) { $uri += "&marker=$([uri]::EscapeDataString($marker))" }
    $response = Invoke-BaselineRequest -Uri $uri -Method Get -ResourceUrl 'https://storage.azure.com/'
    $listing = [xml]$response.Content
    foreach ($node in $listing.SelectNodes('/EnumerationResults/Blobs/Blob/Name')) {
        $name = $node.InnerText
        if (-not $expectedBlobs.Contains($name)) {
            throw "Baseline dataset prefix contains unexpected blob '$name'; it was not modified."
        }
        $null = $foundBlobs.Add($name)
    }
    $markerNode = $listing.SelectSingleNode('/EnumerationResults/NextMarker')
    $marker = if ($null -eq $markerNode) { '' } else { $markerNode.InnerText }
} while ($marker)
if ($foundBlobs.Count -ne $expectedBlobs.Count) {
    throw 'Baseline dataset prefix is missing one or more expected CSV shards.'
}

$searchAudience = 'https://search.azure.com/'
$searchApiVersion = '2025-09-01'
$indexName = 'bootcamp-baseline-v1'
$sourceName = 'bootcamp-baseline-v1-source'
$indexerName = 'bootcamp-baseline-v1-indexer'
$storageId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
$columns = @(
    'ticket_id', 'created_at', 'customer_id', 'customer_segment', 'channel', 'product_area',
    'issue_type', 'priority', 'status', 'sla_plan', 'initial_message', 'agent_first_reply',
    'resolution_summary', 'resolution_time_hours', 'reopened', 'customer_sentiment',
    'csat_score', 'has_attachment', 'platform', 'region'
)
$textColumns = @('initial_message', 'agent_first_reply', 'resolution_summary')
$fields = @($columns | ForEach-Object {
    $field = @{
        name = $_
        type = 'Edm.String'
        searchable = $_ -ne 'ticket_id'
        filterable = $_ -notin $textColumns
        retrievable = $true
    }
    if ($_ -eq 'ticket_id') { $field.key = $true }
    $field
})
$index = @{ name = $indexName; fields = $fields }
$source = @{
    name = $sourceName
    type = 'azureblob'
    credentials = @{ connectionString = "ResourceId=$storageId;" }
    container = @{ name = $ContainerName; query = 'dataset-v1/' }
}
$indexer = @{
    name = $indexerName
    dataSourceName = $sourceName
    targetIndexName = $indexName
    parameters = @{
        maxFailedItems = 0
        maxFailedItemsPerBatch = 0
        configuration = @{
            parsingMode = 'delimitedText'
            firstLineContainsHeaders = $true
            indexedFileNameExtensions = '.csv'
        }
    }
    fieldMappings = @(@{ sourceFieldName = 'ticket_id'; targetFieldName = 'ticket_id' })
}

function Get-SearchResource([string]$Kind, [string]$Name) {
    $suffix = if ($Kind -eq 'datasources') { '&includeConnectionString=true' } else { '' }
    $uri = "$SearchEndpoint/$Kind('$Name')?api-version=$searchApiVersion$suffix"
    $response = Invoke-BaselineRequest -Uri $uri -Method Get -ResourceUrl $searchAudience -AcceptStatus 404
    if ($response.StatusCode -eq 404) { return $null }
    return $response.Content | ConvertFrom-Json -AsHashtable
}

function Assert-SearchResource([string]$Kind, $Actual, $Expected) {
    if ($Actual -isnot [System.Collections.IDictionary]) {
        throw "Existing baseline Search $Kind '$($Expected.name)' is incompatible; it was not overwritten."
    }
    $compatible = $Actual['name'] -eq $Expected.name
    switch ($Kind) {
        'indexes' {
            foreach ($expectedField in $Expected.fields) {
                $matching = @($Actual['fields'] | Where-Object {
                    $_ -is [System.Collections.IDictionary] -and $_['name'] -eq $expectedField.name
                })
                if ($matching.Count -ne 1) { $compatible = $false; continue }
                foreach ($attribute in $expectedField.Keys) {
                    if (-not $matching[0].ContainsKey($attribute) -or
                        $matching[0][$attribute] -ne $expectedField[$attribute]) {
                        $compatible = $false
                    }
                }
            }
        }
        'datasources' {
            $container = $Actual['container']
            $credentials = $Actual['credentials']
            if ($container -isnot [System.Collections.IDictionary] -or
                $credentials -isnot [System.Collections.IDictionary]) {
                $compatible = $false
                break
            }
            $compatible = $compatible -and $Actual['type'] -eq $Expected.type -and
                $container['name'] -eq $Expected.container.name -and
                $container['query'] -eq $Expected.container.query -and
                $credentials['connectionString'] -eq $Expected.credentials.connectionString -and
                $null -eq $Actual['identity']
        }
        'indexers' {
            $parameters = $Actual['parameters']
            $mapping = @($Actual['fieldMappings'])
            if ($parameters -isnot [System.Collections.IDictionary] -or
                $parameters['configuration'] -isnot [System.Collections.IDictionary] -or
                $mapping.Count -ne 1 -or $mapping[0] -isnot [System.Collections.IDictionary]) {
                $compatible = $false
                break
            }
            $config = $parameters['configuration']
            $compatible = $compatible -and $Actual['dataSourceName'] -eq $Expected.dataSourceName -and
                $Actual['targetIndexName'] -eq $Expected.targetIndexName -and
                $config['parsingMode'] -eq 'delimitedText' -and $config['firstLineContainsHeaders'] -eq $true -and
                $config['indexedFileNameExtensions'] -eq '.csv' -and
                $parameters['maxFailedItems'] -eq 0 -and $parameters['maxFailedItemsPerBatch'] -eq 0 -and
                $mapping[0]['sourceFieldName'] -eq 'ticket_id' -and
                $mapping[0]['targetFieldName'] -eq 'ticket_id' -and
                $null -eq $mapping[0]['mappingFunction'] -and
                -not $Actual['disabled'] -and -not $Actual['skillsetName']
        }
    }
    if (-not $compatible) {
        throw "Existing baseline Search $Kind '$($Expected.name)' is incompatible; it was not overwritten."
    }
}

function Ensure-SearchResource([string]$Kind, $Definition) {
    $existing = Get-SearchResource $Kind $Definition.name
    $created = $false
    if ($null -eq $existing) {
        $uri = "$SearchEndpoint/$Kind('$($Definition.name)')?api-version=$searchApiVersion"
        $body = [Text.Encoding]::UTF8.GetBytes(($Definition | ConvertTo-Json -Depth 30 -Compress))
        $response = Invoke-BaselineRequest -Uri $uri -Method Put -ResourceUrl $searchAudience `
            -Headers @{ 'If-None-Match' = '*'; Prefer = 'return=representation' } `
            -Body $body -ContentType 'application/json' -AcceptStatus 412
        $created = $response.StatusCode -ne 412
        $existing = Get-SearchResource $Kind $Definition.name
    }
    if ($null -eq $existing) {
        throw "Baseline Search $Kind '$($Definition.name)' could not be read after creation."
    }
    Assert-SearchResource $Kind $existing $Definition
    return $created
}

$indexCreated = Ensure-SearchResource 'indexes' $index
$countUri = "$SearchEndpoint/indexes('$indexName')/docs/`$count?api-version=$searchApiVersion"
if (-not $indexCreated -and $null -eq (Get-SearchResource 'indexers' $indexerName)) {
    $countResponse = Invoke-BaselineRequest -Uri $countUri -Method Get -ResourceUrl $searchAudience
    [long]$existingCount = 0
    if (-not [long]::TryParse($countResponse.Content, [ref]$existingCount)) {
        throw 'Baseline Search returned an invalid document count.'
    }
    if ($existingCount -gt 0) {
        throw 'The baseline indexer is missing and the existing index is populated; it was not recreated to avoid overwriting participant work.'
    }
}
$null = Ensure-SearchResource 'datasources' $source
$indexerCreated = Ensure-SearchResource 'indexers' $indexer
$statusUri = "$SearchEndpoint/indexers('$indexerName')/search.status?api-version=$searchApiVersion"
$runUri = "$SearchEndpoint/indexers('$indexerName')/search.run?api-version=$searchApiVersion"
$queryUri = "$SearchEndpoint/indexes('$indexName')/docs/search.post.search?api-version=$searchApiVersion"
$query = @{
    search = 'password'
    searchFields = 'initial_message'
    filter = "ticket_id eq 'TCKT_000001'"
    select = 'ticket_id,initial_message'
    top = 1
}
$queryBody = [Text.Encoding]::UTF8.GetBytes(($query | ConvertTo-Json -Compress))
$resetUri = "$SearchEndpoint/indexers('$indexerName')/search.reset?api-version=$searchApiVersion"
$repairResetRequested = $false
$repairRunStarted = $false
$repairPriorStart = ''
$repairIncompletePolls = 0
$lastFailure = $null
$failureRetries = 0
$lastStatus = 'not started'
$lastCount = 0
$lastDiagnostic = 'No indexer result has been reported.'
for ($poll = 0; $poll -lt 180; $poll++) {
    $statusResponse = Invoke-BaselineRequest -Uri $statusUri -Method Get -ResourceUrl $searchAudience
    $status = $statusResponse.Content | ConvertFrom-Json -AsHashtable
    if ($status.status -eq 'error') {
        throw "Baseline indexer is in an error state: $($statusResponse.Content)"
    }
    $lastResult = $status.lastResult
    if ($null -ne $lastResult) {
        $lastStatus = $lastResult.status
        $lastDiagnostic = $statusResponse.Content
        if ($lastResult.status -eq 'success') {
            if (-not $lastResult.ContainsKey('itemsFailed') -or $lastResult.itemsFailed -ne 0) {
                throw "Baseline indexer completed with failures: $($statusResponse.Content)"
            }
            $countResponse = Invoke-BaselineRequest -Uri $countUri -Method Get -ResourceUrl $searchAudience
            if (-not [long]::TryParse($countResponse.Content, [ref]$lastCount)) {
                throw 'Baseline Search returned an invalid document count.'
            }
            if ($lastCount -ge 100000) {
                $queryResponse = Invoke-BaselineRequest -Uri $queryUri -Method Post -ResourceUrl $searchAudience `
                    -Body $queryBody -ContentType 'application/json'
                $found = $queryResponse.Content | ConvertFrom-Json -AsHashtable
                if (@($found.value).Count -eq 1 -and $found.value[0].ticket_id -eq 'TCKT_000001' -and
                    $found.value[0].initial_message -like '*password is incorrect*') {
                    return $indexName
                }
            } elseif (-not $indexerCreated) {
                # Blob change tracking skips unchanged shards, so an incomplete index needs a reset to refill.
                # Documents are keyed by ticket_id and merged, so a full re-read cannot duplicate tickets.
                if (-not $repairRunStarted) {
                    if (-not $repairResetRequested) {
                        $null = Invoke-BaselineRequest -Uri $resetUri -Method Post -ResourceUrl $searchAudience
                        $repairResetRequested = $true
                        $repairPriorStart = [string]$lastResult['startTime']
                    }
                    $runResponse = Invoke-BaselineRequest -Uri $runUri -Method Post -ResourceUrl $searchAudience -AcceptStatus 409
                    $repairRunStarted = $runResponse.StatusCode -ne 409
                } elseif ([string]$lastResult['startTime'] -ne $repairPriorStart) {
                    # Allow brief document-count lag before declaring the completed repair incomplete.
                    $repairIncompletePolls++
                    if ($repairIncompletePolls -ge 3) {
                        throw "Baseline index repair completed, but '$indexName' contains $lastCount of 100000 documents. No credentials were published; an organizer must investigate the index and the dataset-v1 shards."
                    }
                }
            }
        } elseif ($lastResult.status -eq 'transientFailure') {
            $fingerprint = "$($lastResult['startTime'])|$($lastResult['errorMessage'])"
            if ($fingerprint -ne $lastFailure) {
                if ($failureRetries -ge 6) {
                    throw "Baseline indexer repeatedly failed: $($statusResponse.Content)"
                }
                $lastFailure = $fingerprint
                $failureRetries++
                Start-Sleep -Seconds 30
                $null = Invoke-BaselineRequest -Uri $runUri -Method Post -ResourceUrl $searchAudience -AcceptStatus 409
            }
        }
    }
    Start-Sleep -Seconds 20
}
throw "Baseline indexer did not produce the complete queryable dataset within one hour (status: $lastStatus; documents: $lastCount). Last result: $lastDiagnostic"
