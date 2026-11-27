function Get-ProvisioningToken([string]$ResourceUrl) {
    $token = (Get-AzAccessToken -ResourceUrl $ResourceUrl).Token
    if ($token -is [securestring]) {
        return [System.Net.NetworkCredential]::new('', $token).Password
    }
    if ($token -is [string] -and -not [string]::IsNullOrWhiteSpace($token)) {
        return $token
    }
    throw "Provisioning could not obtain an Entra token for $ResourceUrl."
}

function Invoke-ProvisioningRequest {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$ResourceUrl,
        [hashtable]$Headers = @{},
        [byte[]]$Body,
        [string]$ContentType,
        [int[]]$AcceptStatus = @()
    )
    $safeReplay = $Method -in @('Get', 'Head', 'Put')
    for ($attempt = 1; $attempt -le 61; $attempt++) {
        $Headers.Authorization = "Bearer $(Get-ProvisioningToken $ResourceUrl)"
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
            if (-not $safeReplay -or $attempt -eq 61) {
                throw "Provisioning $Method request to $Uri failed: $($_.Exception.Message). Rerun provisioning to reconcile existing resources."
            }
            Start-Sleep -Seconds 10
            continue
        }
        $status = [int]$response.StatusCode
        if (($status -ge 200 -and $status -lt 300) -or $status -in $AcceptStatus) {
            return $response
        }
        # Rejected auth/throttling requests are safe to retry; uncertain creates are not.
        if (($status -in @(403, 429) -or ($safeReplay -and $status -ge 500)) -and $attempt -lt 61) {
            Start-Sleep -Seconds 10
            continue
        }
        throw "Provisioning $Method request to $Uri failed with HTTP $status. $($response.Content)"
    }
}

function Assert-ProvisioningBlob($Response, [byte[]]$Bytes, [string]$Hash, [string]$Uri) {
    $length = @($Response.Headers['Content-Length'])[0]
    $remoteHash = @($Response.Headers['x-ms-meta-sha256'])[0]
    $remoteMd5 = @($Response.Headers['Content-MD5'])[0]
    $expectedMd5 = [Convert]::ToBase64String([Security.Cryptography.MD5]::HashData($Bytes))
    if ($null -eq $length -or [long]$length -ne $Bytes.Length -or
        $remoteHash -ne $Hash -or $remoteMd5 -ne $expectedMd5) {
        throw "Provisioning blob $Uri already exists with different content; it was not overwritten."
    }
}

function Publish-ProvisioningBlob([string]$Uri, [byte[]]$Bytes, [string]$ContentType) {
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    $existing = Invoke-ProvisioningRequest -Uri $Uri -Method Head -ResourceUrl 'https://storage.azure.com/' -AcceptStatus 404
    if ($existing.StatusCode -ne 404) {
        Assert-ProvisioningBlob $existing $Bytes $hash $Uri
        return
    }
    $headers = @{
        'x-ms-blob-type' = 'BlockBlob'
        'x-ms-meta-sha256' = $hash
        'Content-MD5' = [Convert]::ToBase64String([Security.Cryptography.MD5]::HashData($Bytes))
        'If-None-Match' = '*'
    }
    $null = Invoke-ProvisioningRequest -Uri $Uri -Method Put -ResourceUrl 'https://storage.azure.com/' `
        -Headers $headers -Body $Bytes -ContentType $ContentType -AcceptStatus 412
    $existing = Invoke-ProvisioningRequest -Uri $Uri -Method Head -ResourceUrl 'https://storage.azure.com/'
    Assert-ProvisioningBlob $existing $Bytes $hash $Uri
}
