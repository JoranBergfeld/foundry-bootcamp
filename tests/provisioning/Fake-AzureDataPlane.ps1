function New-FakeAzureDataPlane {
    @{
        Blobs = @{}
        Search = @{ indexes = @{}; datasources = @{}; indexers = @{} }
        Requests = [System.Collections.Generic.List[object]]::new()
        IndexerResult = @{ status = 'success'; itemsFailed = 0; errors = @(); warnings = @() }
        RecoveryResult = $null
        ResetRequested = $false
        RepairRows = $null
        IndexedRows = 0
        StoragePublicNetworkAccess = 'Enabled'
        Foundry = @{ Files = @{}; Stores = @{}; Datasets = @{}; toolboxes = @{}; agents = @{}; Connections = @{} }
        EvalsIngestionStatus = 'completed'
        EvalsSearchEmpty = $false
        FoundryFailure = $null
        EvalsPageSize = 100
        EvalsMcpError = $false
        EvalsMcpSse = $false
    }
}

function Invoke-FakeAzureDataPlane {
    param($Uri, $Method, $Headers, $Body, $State)
    $url = [uri]$Uri
    $methodName = [string]$Method
    $State.Requests.Add(@{
        Uri = $url.AbsoluteUri
        Method = $methodName
        Headers = $Headers.Clone()
        Body = if ($url.Host -notlike '*.blob.core.windows.net' -and $Body) {
            [Text.Encoding]::UTF8.GetString($Body)
        } else { $null }
    })
    if ($Headers.Authorization -notlike 'Bearer *') {
        throw 'A data-plane request was not authenticated with an Entra bearer token.'
    }

    if ($url.Host -eq 'stexample.blob.core.windows.net') {
        if ($State.StoragePublicNetworkAccess -ne 'Enabled') {
            return [pscustomobject]@{ StatusCode = 403; Content = 'Storage public network access is disabled by policy.'; Headers = @{} }
        }
        $key = $url.AbsolutePath
        if ($key -eq '/baseline' -and $methodName -eq 'Get' -and $url.Query -match 'comp=list') {
            $names = @($State.Blobs.Keys | Where-Object { $_ -like '/baseline/dataset-v1/*' } |
                ForEach-Object { "<Blob><Name>$([Security.SecurityElement]::Escape($_.Substring('/baseline/'.Length)))</Name></Blob>" })
            $xml = "$([char]0xFEFF)<?xml version=`"1.0`" encoding=`"utf-8`"?><EnumerationResults><Blobs>$($names -join '')</Blobs><NextMarker /></EnumerationResults>"
            return [pscustomobject]@{ StatusCode = 200; Content = $xml; Headers = @{} }
        }
        if ($methodName -eq 'Head') {
            if (-not $State.Blobs.ContainsKey($key)) {
                return [pscustomobject]@{ StatusCode = 404; Content = ''; Headers = @{} }
            }
            $blob = $State.Blobs[$key]
            return [pscustomobject]@{
                StatusCode = 200
                Content = ''
                Headers = @{
                    'Content-Length' = $blob.Length
                    'Content-MD5' = $blob.Md5
                    'x-ms-meta-sha256' = $blob.Hash
                }
            }
        }
        if ($methodName -eq 'Put') {
            if ($Headers['If-None-Match'] -ne '*') { throw 'Blob upload must not overwrite an existing blob.' }
            if ($State.Blobs.ContainsKey($key)) {
                return [pscustomobject]@{ StatusCode = 412; Content = ''; Headers = @{} }
            }
            if ($key -like '/baseline/evals/*') {
                $State.Blobs[$key] = @{
                    Length = $Body.Length; Hash = $Headers['x-ms-meta-sha256']; Md5 = $Headers['Content-MD5']
                    Rows = 0; Sample = $null; Content = [Text.Encoding]::UTF8.GetString($Body)
                }
                return [pscustomobject]@{ StatusCode = 201; Content = ''; Headers = @{} }
            }
            $reader = [System.IO.StreamReader]::new([System.IO.MemoryStream]::new($Body), [Text.Encoding]::UTF8)
            try {
                $header = $reader.ReadLine()
                $first = $reader.ReadLine()
                $rows = if ($null -eq $first) { 0 } else { 1 }
                while ($null -ne $reader.ReadLine()) { $rows++ }
                $sample = if ($first) { @("$header`n$first" | ConvertFrom-Csv)[0] } else { $null }
            } finally {
                $reader.Dispose()
            }
            $State.Blobs[$key] = @{
                Length = $Body.Length
                Hash = $Headers['x-ms-meta-sha256']
                Md5 = $Headers['Content-MD5']
                Rows = $rows
                Sample = $sample
            }
            return [pscustomobject]@{ StatusCode = 201; Content = ''; Headers = @{} }
        }
    }

    if ($url.Host -in @('foundry.example', 'management.azure.com')) {
        $foundry = $State.Foundry
        if ($null -ne $State.FoundryFailure -and $url.AbsolutePath -like $State.FoundryFailure.Path -and
            $methodName -eq $State.FoundryFailure.Method) {
            return [pscustomobject]@{ StatusCode = $State.FoundryFailure.Status; Content = 'Injected Foundry failure'; Headers = @{} }
        }
        $result = $null
        $status = 200
        $path = $url.AbsolutePath
        $json = if ($Body -and $Headers['Content-Type'] -notlike 'multipart/*' -and $path -ne '/openai/v1/files') {
            [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -AsHashtable
        } else { $null }
        if ($url.Host -eq 'management.azure.com') {
            if ($path -match '/connections/([^/]+)$') {
                $name = $Matches[1]
                if ($methodName -eq 'Put') {
                    if ($foundry.Connections.ContainsKey($name)) { throw 'Existing toolbox connection was overwritten.' }
                    $foundry.Connections[$name] = $json
                }
                if ($foundry.Connections.ContainsKey($name)) { $result = $foundry.Connections[$name] } else { $status = 404 }
            } else {
                $result = @{ properties = @{ amlWorkspace = @{ internalId = '00000000-0000-0000-0000-000000000004' } } }
            }
        } elseif ($path -match '^/api/projects/bootcamp/datasets/([^/]+)/versions/([^/]+)$') {
            $key = "$($Matches[1])/$($Matches[2])"
            if ($methodName -eq 'Patch') {
                if ($foundry.Datasets.ContainsKey($key)) { throw 'Existing evaluation dataset was overwritten.' }
                $json.id = 'dataset-support-v2'
                $foundry.Datasets[$key] = $json
            }
            if ($foundry.Datasets.ContainsKey($key)) { $result = $foundry.Datasets[$key] } else { $status = 404 }
        } elseif ($path -match '^/api/projects/bootcamp/toolboxes/[^/]+/versions/[^/]+/mcp$') {
            if ($json.method -eq 'notifications/initialized') {
                return [pscustomobject]@{ StatusCode = 202; Content = ''; Headers = @{} }
            }
            if ($json.method -ne 'initialize' -and $Headers['Mcp-Session-Id'] -ne 'evals-session') {
                throw 'Toolbox MCP requests must retain the initialized session.'
            }
            $result = @{ jsonrpc = '2.0'; id = $json.id }
            if ($State.EvalsMcpError) {
                $result.error = @{ code = -32000; message = 'Toolbox denied' }
            } else {
                $result.result = switch ($json.method) {
                    initialize { @{ protocolVersion = '2025-03-26'; capabilities = @{ tools = @{} } } }
                    'tools/list' { @{ tools = @(@{ name = 'file_search'; inputSchema = @{ properties = @{ queries = @{} } } }) } }
                    'tools/call' { @{ content = @(@{ type = 'text'; text = 'Urgent tickets reach the on-call team immediately, 24/7.' }); isError = $false } }
                    default { throw "Unexpected toolbox MCP method: $($json.method)" }
                }
            }
            $content = $result | ConvertTo-Json -Depth 20 -Compress
            if ($State.EvalsMcpSse) { $content = "event: message`ndata: $content`n`n" }
            return [pscustomobject]@{ StatusCode = 200; Content = $content; Headers = @{ 'Mcp-Session-Id' = 'evals-session' } }
        } elseif ($path -match '^/api/projects/bootcamp/(toolboxes|agents)/([^/]+)/versions(?:/([^/]+))?$') {
            $kind, $name, $version = $Matches[1], $Matches[2], $Matches[3]
            if ($methodName -eq 'Post') {
                if (-not $foundry[$kind].ContainsKey($name)) { $foundry[$kind][$name] = @() }
                $json.name = $name
                $json.version = [string]($foundry[$kind][$name].Count + 1)
                $json.id = "$kind-$name-$($json.version)"
                $foundry[$kind][$name] += $json
                $result = $json
            } elseif ($foundry[$kind].ContainsKey($name)) {
                $result = if ($version) { $foundry[$kind][$name] | Where-Object version -EQ $version } else {
                    @{ data = @($foundry[$kind][$name]); has_more = $false }
                }
            } else { $status = 404 }
        } elseif ($path -like '/openai/v1/*') {
            if ($Headers['x-aml-project-id'] -ne '00000000-0000-0000-0000-000000000004') {
                throw 'Resource-level toolbox file operations require project isolation.'
            }
            if ($path -eq '/openai/v1/files') {
                if ($methodName -eq 'Post') {
                    $text = [Text.Encoding]::UTF8.GetString($Body)
                    if ($text -notmatch '(?s)name="purpose"\r\n\r\nassistants\r\n.*filename="([^"]+)".*?\r\n\r\n(.*)\r\n--bootcamp-') {
                        throw 'Invalid assistants file multipart upload.'
                    }
                    $id = "file-$($foundry.Files.Count + 1)"
                    $content = $Matches[2]
                    $foundry.Files[$id] = @{
                        id = $id; filename = $Matches[1]; bytes = [Text.Encoding]::UTF8.GetByteCount($content); Content = $content
                    }
                    $result = $foundry.Files[$id]
                } else { $result = @{ data = @($foundry.Files.Values); has_more = $false } }
            } elseif ($path -match '^/openai/v1/files/([^/]+)/content$') {
                return [pscustomobject]@{ StatusCode = 200; Content = $foundry.Files[$Matches[1]].Content; Headers = @{} }
            } elseif ($path -eq '/openai/v1/vector_stores') {
                if ($methodName -eq 'Post') {
                    $json.id = "vs-$($foundry.Stores.Count + 1)"
                    $foundry.Stores[$json.id] = $json
                    $result = $json
                } else { $result = @{ data = @($foundry.Stores.Values); has_more = $false } }
            } elseif ($path -match '^/openai/v1/vector_stores/([^/]+)(?:/(files|search))?$') {
                $store = $foundry.Stores[$Matches[1]]
                $action = $Matches[2]
                if ($action -eq 'files') {
                    $result = @{ data = @($store.file_ids | ForEach-Object { @{ id = $_ } }); has_more = $false }
                } elseif ($action -eq 'search') {
                    $result = @{ data = @(if (-not $State.EvalsSearchEmpty) {
                        @($store.file_ids | ForEach-Object { @{ content = @(@{ text = $foundry.Files[$_].Content }) } })
                    }) }
                } else {
                    $store.status = $State.EvalsIngestionStatus
                    $store.file_counts = @{
                        completed = if ($State.EvalsIngestionStatus -eq 'completed') { $store.file_ids.Count } else { 0 }
                        failed = if ($State.EvalsIngestionStatus -eq 'failed') { 1 } else { 0 }
                        cancelled = 0; total = $store.file_ids.Count
                        in_progress = if ($State.EvalsIngestionStatus -eq 'in_progress') { $store.file_ids.Count } else { 0 }
                    }
                    $result = $store
                }
            }
        }
        if ($null -eq $result -and $status -ne 404) { throw "Unexpected Foundry request: $methodName $url" }
        if ($null -ne $result -and $result.ContainsKey('data') -and $result.ContainsKey('has_more')) {
            $items = @($result.data | Sort-Object id)
            if ($url.Query -match 'after=([^&]+)') {
                $cursor = [uri]::UnescapeDataString($Matches[1])
                $ids = @($items | ForEach-Object { $_.id })
                $items = @($items | Select-Object -Skip ([array]::IndexOf($ids, $cursor) + 1))
            }
            $result = @{
                data = @($items | Select-Object -First $State.EvalsPageSize)
                has_more = $items.Count -gt $State.EvalsPageSize
            }
        }
        return [pscustomobject]@{ StatusCode = $status; Content = ($result | ConvertTo-Json -Depth 50 -Compress); Headers = @{} }
    }

    if ($url.Host -eq 'srch.example.search.windows.net') {
        if ($url.AbsolutePath -notmatch "^/(indexes|datasources|indexers)\('([^']+)'\)(?:/(.+))?$") {
            throw "Unexpected Search request: $methodName $url"
        }
        $kind, $name, $action = $Matches[1], $Matches[2], $Matches[3]
        if ($action -eq 'search.status' -and $methodName -eq 'Get') {
            $status = @{ status = 'running'; lastResult = $State.IndexerResult }
            return [pscustomobject]@{ StatusCode = 200; Content = ($status | ConvertTo-Json -Depth 20 -Compress); Headers = @{} }
        }
        if ($action -eq 'search.reset' -and $methodName -eq 'Post') {
            $State.ResetRequested = $true
            return [pscustomobject]@{ StatusCode = 204; Content = ''; Headers = @{} }
        }
        if ($action -eq 'search.run' -and $methodName -eq 'Post') {
            if ($null -ne $State.RecoveryResult) {
                $State.IndexerResult = $State.RecoveryResult
                $State.RecoveryResult = $null
            }
            # Blob change tracking: unchanged shards are reprocessed only after a reset.
            if ($State.ResetRequested) {
                $State.ResetRequested = $false
                $State.IndexedRows = if ($null -ne $State.RepairRows) { $State.RepairRows } else {
                    ($State.Blobs.Values | Measure-Object -Property Rows -Sum).Sum
                }
                $State.IndexerResult = @{
                    status = 'success'; itemsFailed = 0; errors = @(); warnings = @()
                    startTime = "repair-$($State.Requests.Count)"
                }
            }
            return [pscustomobject]@{ StatusCode = 202; Content = ''; Headers = @{} }
        }
        if ($action -eq 'docs/$count' -and $methodName -eq 'Get') {
            return [pscustomobject]@{ StatusCode = 200; Content = [string]$State.IndexedRows; Headers = @{} }
        }
        if ($action -eq 'docs/search.post.search' -and $methodName -eq 'Post') {
            $sample = $State.Blobs['/baseline/dataset-v1/part-000.csv'].Sample
            $result = @{ value = @($sample) }
            return [pscustomobject]@{ StatusCode = 200; Content = ($result | ConvertTo-Json -Depth 20 -Compress); Headers = @{} }
        }
        if (-not $action -and $methodName -eq 'Get') {
            if (-not $State.Search[$kind].ContainsKey($name)) {
                return [pscustomobject]@{ StatusCode = 404; Content = ''; Headers = @{} }
            }
            $object = $State.Search[$kind][$name]
            return [pscustomobject]@{ StatusCode = 200; Content = ($object | ConvertTo-Json -Depth 50 -Compress); Headers = @{} }
        }
        if (-not $action -and $methodName -eq 'Put') {
            if ($Headers['If-None-Match'] -ne '*') { throw 'Search resource creation must not overwrite an existing resource.' }
            if ($State.Search[$kind].ContainsKey($name)) {
                return [pscustomobject]@{ StatusCode = 412; Content = ''; Headers = @{} }
            }
            $object = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -AsHashtable
            $State.Search[$kind][$name] = $object
            if ($kind -eq 'indexers') {
                $State.IndexedRows = ($State.Blobs.Values | Measure-Object -Property Rows -Sum).Sum
            }
            return [pscustomobject]@{ StatusCode = 201; Content = ($object | ConvertTo-Json -Depth 50 -Compress); Headers = @{} }
        }
    }
    throw "Unexpected data-plane request: $methodName $url"
}
