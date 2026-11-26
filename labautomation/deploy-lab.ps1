param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('subscription', 'resourcegroup', 'resourcegroup-with-subscriptionowner')]
    [string]$DeploymentType,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = '',
    [string[]]$PreferredLocation = @(),
    [string[]]$AllowedEntraUserIds = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$regions = @($PreferredLocation | ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if ($regions.Count -eq 0) {
    throw 'PreferredLocation must contain at least one platform-supplied region; no default region is defined.'
}
if ($AllowedEntraUserIds.Count -eq 0 -or @($AllowedEntraUserIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw 'AllowedEntraUserIds must contain the participant Entra object IDs.'
}
if ($DeploymentType -eq 'subscription') {
    $stableHash = Get-MhhStableHash ($AllowedEntraUserIds | Sort-Object -Unique) -Length 24
    $ResourceGroupName = "lab-$stableHash"
} elseif ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw "ResourceGroupName must be provided for DeploymentType '$DeploymentType'."
}

$storagePolicyExemption = $null
if (-not [string]::IsNullOrWhiteSpace($env:BOOTCAMP_STORAGE_POLICY_EXEMPTION)) {
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($env:BOOTCAMP_STORAGE_POLICY_EXEMPTION)
        $storagePolicyExemption = ConvertFrom-Json -InputObject $env:BOOTCAMP_STORAGE_POLICY_EXEMPTION `
            -AsHashtable -ErrorAction Stop
        if ($document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object -and
            $storagePolicyExemption.Contains('expiresOn')) {
            # ConvertFrom-Json coerces ISO dates on older PowerShell; preserve the original UTC string.
            $expiresOn = $document.RootElement.GetProperty('expiresOn')
            $storagePolicyExemption.expiresOn = if ($expiresOn.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                $expiresOn.GetString()
            } else { $null }
        }
    } catch {
        throw 'BOOTCAMP_STORAGE_POLICY_EXEMPTION must be a valid JSON object.'
    } finally {
        if ($null -ne $document) { $document.Dispose() }
    }
    $required = @('policyAssignmentId', 'policyDefinitionReferenceIds', 'expiresOn', 'description')
    if ($storagePolicyExemption -isnot [System.Collections.IDictionary] -or
        @($required | Where-Object { -not $storagePolicyExemption.Contains($_) }).Count -gt 0 -or
        @($storagePolicyExemption.Keys | Where-Object { $_ -notin $required }).Count -gt 0) {
        throw "BOOTCAMP_STORAGE_POLICY_EXEMPTION must contain exactly: $($required -join ', ')."
    }
    $assignmentId = $storagePolicyExemption.policyAssignmentId
    if ($assignmentId -isnot [string] -or $assignmentId -notmatch
        '^/(subscriptions/[^/]+(?:/resourceGroups/[^/]+)?|providers/Microsoft.Management/managementGroups/[^/]+)/providers/Microsoft.Authorization/policyAssignments/[^/\s]+$') {
        throw 'BOOTCAMP_STORAGE_POLICY_EXEMPTION requires a full policy assignment resource ID.'
    }
    $references = $storagePolicyExemption.policyDefinitionReferenceIds
    if ($references -isnot [array] -or $references.Count -eq 0 -or
        @($references | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'BOOTCAMP_STORAGE_POLICY_EXEMPTION requires a nonempty array of approved network policy definition reference IDs; whole-initiative exemptions are not supported.'
    }
    $expiry = [DateTimeOffset]::MinValue
    if ($storagePolicyExemption.expiresOn -isnot [string] -or
        -not [DateTimeOffset]::TryParseExact($storagePolicyExemption.expiresOn, "yyyy-MM-ddTHH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$expiry) -or
        $expiry -le [DateTimeOffset]::UtcNow) {
        throw 'BOOTCAMP_STORAGE_POLICY_EXEMPTION requires a future UTC expiresOn in yyyy-MM-ddTHH:mm:ssZ format.'
    }
    if ($storagePolicyExemption.description -isnot [string] -or
        [string]::IsNullOrWhiteSpace($storagePolicyExemption.description)) {
        throw 'BOOTCAMP_STORAGE_POLICY_EXEMPTION requires an organizer-supplied approval description.'
    }
}

$context = Get-AzContext
if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
    throw 'The authenticated subscription must match SubscriptionId. MicroHack must supply the authenticated context.'
}

$armToken = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/').Token
$tokenText = if ($armToken -is [securestring]) {
    [System.Net.NetworkCredential]::new('', $armToken).Password
} elseif ($armToken -is [string]) {
    $armToken
} else {
    throw 'The authenticated provisioner token is unavailable.'
}
$parts = $tokenText -split '\.'
if ($parts.Count -ne 3 -or $parts[1] -notmatch '^[A-Za-z0-9_-]+$') {
    throw 'The authenticated provisioner token does not contain a valid object ID.'
}
try {
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    $payload += '=' * ((4 - $payload.Length % 4) % 4)
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) |
        ConvertFrom-Json -AsHashtable -ErrorAction Stop
    $provisionerId = [guid]::Empty
    if (-not $claims.ContainsKey('oid') -or -not [guid]::TryParse($claims.oid, [ref]$provisionerId) -or
        $provisionerId -eq [guid]::Empty) {
        throw 'Missing object ID.'
    }
} catch {
    throw 'The authenticated provisioner token does not contain a valid object ID.'
} finally {
    Remove-Variable armToken, tokenText, parts -ErrorAction SilentlyContinue
}

$group = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName }
$resources = @(if ($group) { Get-AzResource -ResourceGroupName $ResourceGroupName })
$template = Join-Path $PSScriptRoot 'foundry-core.bicep'
$parameters = @{ participantObjectIds = $AllowedEntraUserIds; provisionerObjectId = $provisionerId.ToString() }
if ($null -ne $storagePolicyExemption) {
    $parameters.storagePolicyExemption = $storagePolicyExemption
}

# The MicroHack helper can delete the entire RG on recycle, including same-region retries.
if ($env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING -ceq 'true' -and $resources.Count -eq 0) {
    if ($group) {
        if (-not $group.Tags -or $group.Tags['bootcamp-disposable-initial-scope'] -cne 'true') {
            throw 'Initial resource group is not explicitly marked disposable. Retain the scope and use incremental provisioning.'
        }
        if ($group.Tags.Count -ne 1 -or $group.ProvisioningState -ne 'Succeeded') {
            throw 'Initial resource group is not disposable: existing metadata or an active lifecycle operation must be preserved.'
        }
        $locks = @(Get-AzResourceLock -ResourceGroupName $ResourceGroupName)
        $history = @(Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName)
        $extraAccess = @(Get-AzRoleAssignment -Scope $group.ResourceId | Where-Object {
            $_.Scope -eq $group.ResourceId -and (
                $_.ObjectId -notin $AllowedEntraUserIds -or
                ($_.RoleDefinitionId -split '/')[-1] -ne '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -or
                -not [string]::IsNullOrWhiteSpace($_.Condition)
            )
        })
        if ($locks.Count -gt 0 -or $history.Count -gt 0 -or $extraAccess.Count -gt 0) {
            throw 'Initial resource group is not disposable: locks, deployment history or additional RG access grants must be preserved.'
        }
    }
    # Its reuse phase otherwise tries an existing RG's region before the first preference.
    if ($group -and $group.Location -ne $regions[0]) {
        $teardown = Remove-MhhResourceGroup -ResourceGroupName $ResourceGroupName
        if (-not $teardown.ManifestCaptured -or $teardown.Errors.Count -gt 0 -or $teardown.SoftDeletedResidual.Count -gt 0) {
            throw "Empty initial scope cleanup was incomplete: $($teardown.Errors -join '; '); residuals: $($teardown.SoftDeletedResidual -join ', ')."
        }
    }
    $coreDeployment = Invoke-MhhDeploymentWithRegionFallback `
        -PreferredLocations $regions `
        -ResourceGroupName $ResourceGroupName `
        -RgOwnerEntraObjectIds $AllowedEntraUserIds `
        -TemplateFile $template `
        -TemplateParameterObject $parameters `
        -DeploymentNamePrefix 'bootcamp-core'
    if (-not $coreDeployment.Success) {
        throw 'Foundry core deployment did not succeed.'
    }
} else {
    if ($group) {
        if ($group.Location -notin $regions) {
            throw "Participant resource group '$ResourceGroupName' is in '$($group.Location)', which is not among the supplied regions ($($regions -join ', ')). It was not moved or deleted; supply its region or have an organizer resolve the allocation."
        }
    } else {
        # Standard first run: create in the first platform preference only. No fallback or deletion.
        $group = New-AzResourceGroup -Name $ResourceGroupName -Location $regions[0]
    }
    $ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $groupScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $existingOwners = @(Get-AzRoleAssignment -Scope $groupScope | Where-Object {
        $_.Scope -eq $groupScope -and ($_.RoleDefinitionId -split '/')[-1] -eq $ownerRoleId -and
        [string]::IsNullOrWhiteSpace($_.Condition)
    } | ForEach-Object { $_.ObjectId })
    # Mirrors the MicroHack helper's participant RG Owner grant; existing grants are never removed.
    foreach ($participantId in ($AllowedEntraUserIds | Select-Object -Unique)) {
        if ($participantId -notin $existingOwners) {
            $null = New-AzRoleAssignment -ObjectId $participantId -RoleDefinitionId $ownerRoleId -Scope $groupScope
        }
    }
    $parameters.location = $group.Location
    $deployment = New-AzResourceGroupDeployment `
        -Name 'bootcamp-core' `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $template `
        -TemplateParameterObject $parameters `
        -Mode Incremental
    if ($deployment.ProvisioningState -ne 'Succeeded') {
        throw 'Foundry core deployment did not succeed.'
    }
    $outputs = @{}
    foreach ($key in $deployment.Outputs.Keys) {
        $outputs[$key] = $deployment.Outputs[$key].Value
    }
    $coreDeployment = @{ LocationUsed = $group.Location; Outputs = $outputs }
}

$requiredOutputs = @(
    'FoundryProjectEndpoint', 'ChatDeploymentName', 'EmbeddingDeploymentName',
    'SearchEndpoint', 'StorageAccountName', 'StorageBaselineContainerName'
)
foreach ($key in $requiredOutputs) {
    if (-not $coreDeployment.Outputs.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($coreDeployment.Outputs[$key])) {
        throw "Foundry core deployment is missing required output '$key'. No credentials were published."
    }
}
if ([string]::IsNullOrWhiteSpace($coreDeployment.LocationUsed)) {
    throw 'Foundry core deployment is missing required output Region. No credentials were published.'
}

$baselineIndexName = & (Join-Path $PSScriptRoot 'provision-baseline.ps1') `
    -StorageAccountName $coreDeployment.Outputs.StorageAccountName `
    -ContainerName $coreDeployment.Outputs.StorageBaselineContainerName `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -SearchEndpoint $coreDeployment.Outputs.SearchEndpoint
if ([string]::IsNullOrWhiteSpace($baselineIndexName)) {
    throw 'Baseline indexing did not return an index name. No credentials were published.'
}

$credentialValues = [ordered]@{
    ResourceGroupName = $ResourceGroupName
    Region = $coreDeployment.LocationUsed
    FoundryProjectEndpoint = $coreDeployment.Outputs.FoundryProjectEndpoint
    ChatDeploymentName = $coreDeployment.Outputs.ChatDeploymentName
    EmbeddingDeploymentName = $coreDeployment.Outputs.EmbeddingDeploymentName
    SearchEndpoint = $coreDeployment.Outputs.SearchEndpoint
    StorageAccountName = $coreDeployment.Outputs.StorageAccountName
    StorageBaselineContainerName = $coreDeployment.Outputs.StorageBaselineContainerName
    BaselineIndexName = $baselineIndexName
}
foreach ($name in $credentialValues.Keys) {
    @{ HackboxCredential = @{ name = $name; value = $credentialValues[$name] } }
}
