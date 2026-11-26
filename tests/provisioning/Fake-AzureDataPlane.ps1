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
        Body = if ($url.Host -like '*.search.windows.net' -and $Body) {
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
