BeforeAll {
    . (Join-Path $PSScriptRoot 'Fake-AzureDataPlane.ps1')
    $script:Hook = Join-Path $PSScriptRoot '..\..\labautomation\deploy-lab.ps1'
    function Get-AzContext {}
    function Get-AzAccessToken { param($ResourceUrl) }
    function Get-AzResourceGroup {}
    function Get-AzResource { param($ResourceGroupName) }
    function Get-MhhStableHash { param($InputString, $Length) }
    function Remove-MhhResourceGroup { param($ResourceGroupName) }
    function Get-AzResourceLock { param($ResourceGroupName) }
    function Get-AzResourceGroupDeployment { param($ResourceGroupName) }
    function Get-AzRoleAssignment { param($Scope) }
    function New-AzResourceGroup { param($Name, $Location) }
    function New-AzRoleAssignment { param($ObjectId, $RoleDefinitionId, $Scope) }
    function New-AzResourceGroupDeployment {
        param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterObject, $Mode)
    }
    function Invoke-MhhDeploymentWithRegionFallback {
        param($PreferredLocations, $ResourceGroupName, $RgOwnerEntraObjectIds, $TemplateFile,
            $TemplateParameterObject, $DeploymentNamePrefix)
    }
    function Get-CompiledCore {
        $compiled = Join-Path $TestDrive "core-$([guid]::NewGuid()).json"
        & az bicep build --file (Join-Path $PSScriptRoot '..\..\labautomation\foundry-core.bicep') --outfile $compiled --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed' }
        @{ Text = Get-Content $compiled -Raw; Arm = Get-Content $compiled -Raw | ConvertFrom-Json -AsHashtable }
    }
    function Get-RoleGrants($Arm) {
        foreach ($grant in @($Arm.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')) {
            $roleId = $grant.properties.roleDefinitionId
            if ($roleId -match "^\[variables\('([^']+)'\)\]$") { $roleId = $Arm.variables[$Matches[1]] }
            [pscustomobject]@{
                Role = $roleId
                Principal = $grant.properties.principalId
                PrincipalType = $grant.properties.principalType
                Scope = $grant.scope
            }
        }
    }
}

Describe 'Shared baseline dataset' {
    It 'provides the complete verified dataset without a Kaggle download' {
        $path = Join-Path $PSScriptRoot '..\..\labautomation\dataset\synthetic-it-support-tickets-v1.zip'
        $path | Should -Exist
        (Get-FileHash -Algorithm SHA256 $path).Hash |
            Should -Be '036A619B419C4CC9DC5D5B8FE776FDF0E74BE456BD053C7080C2AA34E315D909'

        $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
        try {
            $archive.Entries.Count | Should -Be 1
            $archive.Entries[0].FullName | Should -Be 'synthetic_it_support_tickets.csv'
            $archive.Entries[0].Length | Should -Be 34521641
            $reader = [System.IO.StreamReader]::new($archive.Entries[0].Open())
            try {
                $reader.ReadLine() | Should -Match '^ticket_id,created_at,'
                $rows = 0
                while ($null -ne $reader.ReadLine()) { $rows++ }
                $rows | Should -Be 100000
            } finally {
                $reader.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
    }
}

Describe 'MicroHack Foundry provisioning hook' {
    BeforeEach {
        $script:PreviousOptIn = $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = 'true'
        $script:Inputs = @{
            DeploymentType = 'resourcegroup'
            SubscriptionId = '00000000-0000-0000-0000-000000000001'
            ResourceGroupName = 'participant'
            PreferredLocation = @('region-first', 'region-second')
            AllowedEntraUserIds = @('00000000-0000-0000-0000-000000000002')
        }
        Mock Get-AzContext { @{ Subscription = @{ Id = '00000000-0000-0000-0000-000000000001' } } }
        Mock Get-AzAccessToken {
            $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
                '{"oid":"00000000-0000-0000-0000-000000000003"}')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            @{ Token = ConvertTo-SecureString "e30.$payload.signature" -AsPlainText -Force }
        }
        $global:ProvisioningTestDataPlane = New-FakeAzureDataPlane
        Mock Invoke-WebRequest {
            Invoke-FakeAzureDataPlane -Uri $Uri -Method $Method -Headers $Headers -Body $Body -State $global:ProvisioningTestDataPlane
        }
        Mock Start-Sleep {}
        Mock Get-AzResourceGroup {
            @{
                ResourceGroupName = 'participant'
                ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                Location = 'region-first'
                ProvisioningState = 'Succeeded'
                Tags = @{ 'bootcamp-disposable-initial-scope' = 'true' }
            }
        }
        Mock Get-AzResource { @() }
        Mock Get-AzResourceLock { @() }
        Mock Get-AzResourceGroupDeployment { @() }
        Mock Get-AzRoleAssignment {
            @{
                Scope = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                ObjectId = '00000000-0000-0000-0000-000000000002'
                RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
                Condition = $null
            }
        }
        Mock Get-MhhStableHash { 'a1b2c3d4e5f6a1b2c3d4e5f6' }
        Mock New-AzResourceGroup {
            @{
                ResourceGroupName = $Name
                ResourceId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/$Name"
                Location = $Location
                ProvisioningState = 'Succeeded'
            }
        }
        Mock New-AzRoleAssignment {}
        Mock Remove-MhhResourceGroup {
            @{ ManifestCaptured = $true; Errors = @(); SoftDeletedResidual = @() }
        }
        Mock New-AzResourceGroupDeployment {
            @{
                ProvisioningState = 'Succeeded'
                Outputs = @{
                    FoundryProjectEndpoint = @{ Value = 'https://foundry.example/api/projects/bootcamp' }
                    ChatDeploymentName = @{ Value = 'bootcamp-chat' }
                    EmbeddingDeploymentName = @{ Value = 'bootcamp-embedding' }
                    SearchEndpoint = @{ Value = 'https://srch.example.search.windows.net' }
                    StorageAccountName = @{ Value = 'stexample' }
                    StorageBaselineContainerName = @{ Value = 'baseline' }
                }
            }
        }
        Mock Invoke-MhhDeploymentWithRegionFallback {
            @{
                Success = $true
                LocationUsed = 'region-second'
                Outputs = @{
                    FoundryProjectEndpoint = 'https://foundry.example/api/projects/bootcamp'
                    ChatDeploymentName = 'bootcamp-chat'
                    EmbeddingDeploymentName = 'bootcamp-embedding'
                    SearchEndpoint = 'https://srch.example.search.windows.net'
                    StorageAccountName = 'stexample'
                    StorageBaselineContainerName = 'baseline'
                }
            }
        }
    }

    AfterEach {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $script:PreviousOptIn
        Remove-Variable -Name ProvisioningTestDataPlane -Scope Global -ErrorAction SilentlyContinue
    }

    It 'rejects missing platform regions before contacting Azure' {
        { & $script:Hook -DeploymentType resourcegroup -SubscriptionId 'sub' -ResourceGroupName 'participant' } |
            Should -Throw '*PreferredLocation must contain at least one platform-supplied region*'
    }

    It 'uses the platform helper in priority order for opted-in empty initial provisioning and publishes only successful public values' {
        $credentials = @(& $script:Hook @script:Inputs)
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 1 -Exactly -ParameterFilter {
            ($PreferredLocations -join ',') -eq 'region-first,region-second' -and
            $ResourceGroupName -eq 'participant' -and
            $RgOwnerEntraObjectIds[0] -eq '00000000-0000-0000-0000-000000000002' -and
            $TemplateParameterObject.participantObjectIds[0] -eq '00000000-0000-0000-0000-000000000002'
        }
        $credentials.Count | Should -Be 9
        $values = @{}
        foreach ($credential in $credentials) {
            $credential | Should -BeOfType [hashtable]
            $values[$credential.HackboxCredential.name] = $credential.HackboxCredential.value
        }
        $values.ResourceGroupName | Should -Be 'participant'
        $values.Region | Should -Be 'region-second'
        $values.FoundryProjectEndpoint | Should -Be 'https://foundry.example/api/projects/bootcamp'
        $values.ChatDeploymentName | Should -Be 'bootcamp-chat'
        $values.EmbeddingDeploymentName | Should -Be 'bootcamp-embedding'
        $values.SearchEndpoint | Should -Be 'https://srch.example.search.windows.net'
        $values.StorageAccountName | Should -Be 'stexample'
        $values.StorageBaselineContainerName | Should -Be 'baseline'
        $values.BaselineIndexName | Should -Be 'bootcamp-baseline-v1'
    }

    It 'never calls destructive fallback on a populated RG even with organizer opt-in' {
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.CognitiveServices/accounts'; Location = 'region-first' } }
        $credentials = @(& $script:Hook @script:Inputs)
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $Mode -eq 'Incremental' -and $ResourceGroupName -eq 'participant' -and
            $TemplateParameterObject.location -eq 'region-first'
        }
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'Region' }).HackboxCredential.value |
            Should -Be 'region-first'
    }

    It 'keeps an existing RG in its own region when that region is a supplied preference' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        $script:Inputs.PreferredLocation = @('region-second', 'region-first')
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
        Should -Invoke New-AzResourceGroup -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -ParameterFilter {
            $TemplateParameterObject.location -eq 'region-first' -and $Mode -eq 'Incremental'
        }
    }

    It 'fails clearly when an existing RG is outside the supplied regions' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        $script:Inputs.PreferredLocation = @('region-second')
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices' } }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw "*'region-first'*not among the supplied regions*region-second*"
        $published.Count | Should -Be 0
        Should -Invoke New-AzResourceGroupDeployment -Times 0
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
    }

    It 'starts an empty organizer scope at the first preference instead of letting helper reuse reorder it' {
        Mock Get-AzResourceGroup {
            @{
                ResourceGroupName = 'participant'
                ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                Location = 'region-second'
                ProvisioningState = 'Succeeded'
                Tags = @{ 'bootcamp-disposable-initial-scope' = 'true' }
            }
        }
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Remove-MhhResourceGroup -Times 1 -Exactly -ParameterFilter { $ResourceGroupName -eq 'participant' }
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 1 -Exactly -ParameterFilter {
            ($PreferredLocations -join ',') -eq 'region-first,region-second'
        }
    }

    It 'does not deploy after an incomplete empty-scope cleanup' {
        Mock Get-AzResourceGroup {
            @{
                ResourceGroupName = 'participant'
                ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                Location = 'region-second'
                ProvisioningState = 'Succeeded'
                Tags = @{ 'bootcamp-disposable-initial-scope' = 'true' }
            }
        }
        Mock Remove-MhhResourceGroup {
            @{ ManifestCaptured = $true; Errors = @('cleanup failed'); SoftDeletedResidual = @() }
        }
        { & $script:Hook @script:Inputs } | Should -Throw '*cleanup was incomplete*cleanup failed*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
    }

    It 'treats a failed resource inventory as an error rather than an empty scope' {
        Mock Get-AzResource { Write-Error 'Resource inventory denied' }
        { & $script:Hook @script:Inputs } | Should -Throw '*Resource inventory denied*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
    }

    It 'provisions a standard first run in the first supplied region without opt-in, fallback or deletion: <DeploymentMode>' -ForEach @(
        @{ DeploymentMode = 'subscription'; Group = 'lab-a1b2c3d4e5f6a1b2c3d4e5f6' }
        @{ DeploymentMode = 'resourcegroup'; Group = 'participant' }
    ) {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        Mock Get-AzResourceGroup { @() }
        Mock Get-AzRoleAssignment { @() }
        $script:Inputs.DeploymentType = $DeploymentMode
        if ($DeploymentMode -eq 'subscription') { $script:Inputs.ResourceGroupName = '' }
        $credentials = @(& $script:Hook @script:Inputs)
        Should -Invoke New-AzResourceGroup -Times 1 -Exactly -ParameterFilter {
            $Name -eq $Group -and $Location -eq 'region-first'
        }
        Should -Invoke New-AzRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $ObjectId -eq '00000000-0000-0000-0000-000000000002' -and
            $RoleDefinitionId -eq '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -and
            $Scope -eq "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/$Group"
        }
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $ResourceGroupName -eq $Group -and $Mode -eq 'Incremental' -and
            $TemplateParameterObject.location -eq 'region-first'
        }
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'Region' }).HackboxCredential.value |
            Should -Be 'region-first'
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'ResourceGroupName' }).HackboxCredential.value |
            Should -Be $Group
    }

    It 'does not duplicate an existing participant RG Owner grant on a standard run' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke New-AzRoleAssignment -Times 0
        Should -Invoke New-AzResourceGroup -Times 0
    }

    It 'accepts comma-separated platform preferences without adding a fallback region' {
        $script:Inputs.PreferredLocation = @(' region-first, region-second, ')
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 1 -ParameterFilter {
            ($PreferredLocations -join ',') -eq 'region-first,region-second'
        }
    }

    It 'refuses destructive initial fallback without an organizer disposable-scope tag' {
        Mock Get-AzResourceGroup {
            @{
                ResourceGroupName = 'participant'
                Location = 'region-first'
                ProvisioningState = 'Succeeded'
                Tags = @{}
            }
        }
        { & $script:Hook @script:Inputs } | Should -Throw '*not explicitly marked disposable*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
    }

    It 'preserves existing RG metadata instead of treating resource-empty as disposable: <Metadata>' -ForEach @(
        @{ Metadata = 'tags' }
        @{ Metadata = 'locks' }
        @{ Metadata = 'deployment history' }
        @{ Metadata = 'extra access grants' }
        @{ Metadata = 'conditional Owner access' }
    ) {
        switch ($Metadata) {
            'tags' {
                Mock Get-AzResourceGroup {
                    @{
                        ResourceGroupName = 'participant'
                        Location = 'region-first'
                        ProvisioningState = 'Succeeded'
                        Tags = @{ 'bootcamp-disposable-initial-scope' = 'true'; 'platform-allocation' = 'keep' }
                    }
                }
            }
            'locks' { Mock Get-AzResourceLock { @{ Name = 'keep-platform-scope' } } }
            'deployment history' { Mock Get-AzResourceGroupDeployment { @{ DeploymentName = 'prior-work' } } }
            'extra access grants' {
                Mock Get-AzRoleAssignment {
                    @{
                        Scope = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                        ObjectId = '00000000-0000-0000-0000-000000000099'
                        RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
                    }
                }
            }
            'conditional Owner access' {
                Mock Get-AzRoleAssignment {
                    @{
                        Scope = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant'
                        ObjectId = '00000000-0000-0000-0000-000000000002'
                        RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
                        Condition = 'a platform access constraint'
                    }
                }
            }
        }
        { & $script:Hook @script:Inputs } | Should -Throw '*not disposable*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
    }

    It 'rejects a wrong authenticated subscription without switching context' {
        Mock Get-AzContext { @{ Subscription = @{ Id = 'wrong-subscription' } } }
        { & $script:Hook @script:Inputs } | Should -Throw '*authenticated subscription*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 0
    }

    It 'requires the platform RG name for <Mode>' -ForEach @(
        @{ Mode = 'resourcegroup' }
        @{ Mode = 'resourcegroup-with-subscriptionowner' }
    ) {
        $script:Inputs.DeploymentType = $Mode
        $script:Inputs.ResourceGroupName = ''
        { & $script:Hook @script:Inputs } | Should -Throw '*ResourceGroupName must be provided*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
    }

    It 'requires participant object IDs before it can grant workload access' {
        $script:Inputs.AllowedEntraUserIds = @()
        { & $script:Hook @script:Inputs } | Should -Throw '*AllowedEntraUserIds must contain*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
    }

    It 'derives a stable participant RG in subscription mode without a pre-created RG' {
        Mock Get-AzResourceGroup { @() }
        $script:Inputs.DeploymentType = 'subscription'
        $script:Inputs.ResourceGroupName = ''
        $credentials = @(& $script:Hook @script:Inputs)
        Should -Invoke Get-MhhStableHash -Times 1
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 1 -ParameterFilter {
            $ResourceGroupName -eq 'lab-a1b2c3d4e5f6a1b2c3d4e5f6'
        }
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'ResourceGroupName' }).HackboxCredential.value |
            Should -Be 'lab-a1b2c3d4e5f6a1b2c3d4e5f6'
    }

    It 'publishes nothing when an incremental deployment fails' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        Mock New-AzResourceGroupDeployment { @{ ProvisioningState = 'Failed'; Outputs = @{} } }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*Foundry core deployment did not succeed*'
        $published.Count | Should -Be 0
    }

    It 'publishes nothing when the provisioner cannot upload the baseline dataset' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 403; Content = 'Forbidden'; Headers = @{} } }
        Mock Start-Sleep {}
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*baseline*403*'
        $published.Count | Should -Be 0
    }

    It 'uploads every ticket and publishes the name of a queryable keyless baseline index' {
        $credentials = @(& $script:Hook @script:Inputs)
        $indexName = ($credentials | Where-Object { $_.HackboxCredential.name -eq 'BaselineIndexName' }).HackboxCredential.value
        $indexName | Should -Be 'bootcamp-baseline-v1'
        $global:ProvisioningTestDataPlane.Blobs.Count | Should -Be 10
        ($global:ProvisioningTestDataPlane.Blobs.Values | Measure-Object -Property Rows -Sum).Sum | Should -Be 100000
        @($global:ProvisioningTestDataPlane.Blobs.Values | Where-Object { $_.Length -gt 15MB }).Count | Should -Be 0
        $global:ProvisioningTestDataPlane.IndexedRows | Should -Be 100000
        $source = $global:ProvisioningTestDataPlane.Search.datasources['bootcamp-baseline-v1-source']
        $source.container.name | Should -Be 'baseline'
        $source.container.query | Should -Be 'dataset-v1/'
        $source.credentials.connectionString |
            Should -Be 'ResourceId=/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant/providers/Microsoft.Storage/storageAccounts/stexample;'
        $source.identity | Should -BeNullOrEmpty
        $indexer = $global:ProvisioningTestDataPlane.Search.indexers['bootcamp-baseline-v1-indexer']
        $indexer.parameters.configuration.parsingMode | Should -Be 'delimitedText'
        $indexer.parameters.configuration.firstLineContainsHeaders | Should -BeTrue
        $indexer.targetIndexName | Should -Be $indexName
    }

    It 'refuses an unexpected blob in the reserved dataset prefix without deleting it' {
        $foreignBlob = @{ Length = 42; Rows = 1; Hash = 'participant-data'; Md5 = 'participant-data' }
        $global:ProvisioningTestDataPlane.Blobs['/baseline/dataset-v1/participant.csv'] = $foreignBlob
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*unexpected blob*'
        $published.Count | Should -Be 0
        $global:ProvisioningTestDataPlane.Blobs['/baseline/dataset-v1/participant.csv'] | Should -Be $foreignBlob
        $global:ProvisioningTestDataPlane.Search.indexers.Count | Should -Be 0
    }

    It 'does not publish credentials and reports the indexing error when retries cannot recover' {
        $global:ProvisioningTestDataPlane.IndexerResult = @{
            status = 'transientFailure'
            startTime = '2026-11-25T13:00:00Z'
            errorMessage = 'Search identity cannot read the baseline container'
            itemsFailed = 1
            errors = @()
        }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*Search identity cannot read the baseline container*'
        $published.Count | Should -Be 0
    }

    It 'recovers from a transient indexer failure with only item-level diagnostics' {
        $state = $global:ProvisioningTestDataPlane
        $state.IndexerResult = @{
            status = 'transientFailure'
            startTime = '2026-11-25T13:00:00Z'
            itemsFailed = 1
            errors = @(@{ statusCode = 403; errorMessage = 'Role assignment is not effective yet' })
        }
        $state.RecoveryResult = @{ status = 'success'; itemsFailed = 0; errors = @() }
        $credentials = @(& $script:Hook @script:Inputs)
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'BaselineIndexName' }).HackboxCredential.value |
            Should -Be 'bootcamp-baseline-v1'
        @($state.Requests | Where-Object { $_.Uri -match '/search\.run\?' }).Count | Should -Be 1
    }

    It 'preserves existing participant work on a <Scenario> rerun' -ForEach @(
        @{ Scenario = 'compatible' }
        @{ Scenario = 'modified key mapping' }
    ) {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices' } }
        & $script:Hook @script:Inputs | Out-Null
        $state = $global:ProvisioningTestDataPlane
        $state.Search.indexes['participant-lab-index'] = @{ name = 'participant-lab-index'; custom = 'keep' }
        $state.Search.indexes['bootcamp-baseline-v1'].fields += @{
            name = 'participant_notes'; type = 'Edm.String'; searchable = $true; retrievable = $true
        }
        if ($Scenario -eq 'modified key mapping') {
            $state.Search.indexers['bootcamp-baseline-v1-indexer'].fieldMappings[0].mappingFunction = @{ name = 'base64Encode' }
        }
        $before = $state.Requests.Count
        if ($Scenario -eq 'compatible') {
            $credentials = @(& $script:Hook @script:Inputs)
            ($credentials | Where-Object { $_.HackboxCredential.name -eq 'BaselineIndexName' }).HackboxCredential.value |
                Should -Be 'bootcamp-baseline-v1'
        } else {
            $published = [System.Collections.Generic.List[object]]::new()
            { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
                Should -Throw '*incompatible*not overwritten*'
            $published.Count | Should -Be 0
        }
        $state.Search.indexes['participant-lab-index'].custom | Should -Be 'keep'
        @($state.Search.indexes['bootcamp-baseline-v1'].fields | Where-Object name -eq 'participant_notes').Count |
            Should -Be 1
        @($state.Requests | Select-Object -Skip $before | Where-Object {
            $_.Method -in @('Put', 'Delete') -or $_.Uri -match '/search\.run\?'
        }).Count | Should -Be 0
    }

    It 'does not recreate a missing indexer over a populated baseline index on rerun' {
        & $script:Hook @script:Inputs | Out-Null
        $state = $global:ProvisioningTestDataPlane
        $state.Search.indexers.Remove('bootcamp-baseline-v1-indexer')
        $state.Search.indexes['bootcamp-baseline-v1'].fields += @{
            name = 'participant_notes'; type = 'Edm.String'; searchable = $true; retrievable = $true
        }
        $before = $state.Requests.Count
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*indexer*missing*populated*'
        $published.Count | Should -Be 0
        @($state.Search.indexes['bootcamp-baseline-v1'].fields | Where-Object name -eq 'participant_notes').Count |
            Should -Be 1
        @($state.Requests | Select-Object -Skip $before | Where-Object {
            $_.Method -in @('Put', 'Delete') -or $_.Uri -match '/search\.run\?'
        }).Count | Should -Be 0
    }

    It 'repairs an incomplete baseline index on rerun without replacing Search objects or participant fields' {
        & $script:Hook @script:Inputs | Out-Null
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices' } }
        $state = $global:ProvisioningTestDataPlane
        $state.IndexedRows = 40000
        $state.Search.indexes['bootcamp-baseline-v1'].fields += @{
            name = 'participant_notes'; type = 'Edm.String'; searchable = $true; retrievable = $true
        }
        $before = $state.Requests.Count
        $credentials = @(& $script:Hook @script:Inputs)
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'BaselineIndexName' }).HackboxCredential.value |
            Should -Be 'bootcamp-baseline-v1'
        $state.IndexedRows | Should -Be 100000
        $rerun = @($state.Requests | Select-Object -Skip $before)
        $repair = @($rerun | Where-Object { $_.Uri -match '/search\.(reset|run)\?' } | ForEach-Object { $_.Uri -replace '.*/search\.(\w+)\?.*', '$1' })
        ($repair -join ',') | Should -Be 'reset,run'
        @($rerun | Where-Object { $_.Method -in @('Put', 'Delete') }).Count | Should -Be 0
        @($state.Search.indexes['bootcamp-baseline-v1'].fields | Where-Object name -eq 'participant_notes').Count |
            Should -Be 1
    }

    It 'fails fast with a clear message when a repaired baseline index is still incomplete' {
        & $script:Hook @script:Inputs | Out-Null
        $state = $global:ProvisioningTestDataPlane
        $state.IndexedRows = 40000
        $state.RepairRows = 90000
        $before = $state.Requests.Count
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*repair*90000 of 100000*'
        $published.Count | Should -Be 0
        @($state.Requests | Select-Object -Skip $before | Where-Object { $_.Uri -match '/search\.status\?' }).Count |
            Should -BeLessThan 10
    }

    It 'rejects an incompatible existing <Resource> without replacing it' -ForEach @(
        @{ Resource = 'blob'; Message = '*different content*not overwritten*' }
        @{ Resource = 'data source'; Message = '*datasources*incompatible*not overwritten*' }
    ) {
        & $script:Hook @script:Inputs | Out-Null
        $state = $global:ProvisioningTestDataPlane
        if ($Resource -eq 'blob') {
            $state.Blobs['/baseline/dataset-v1/part-000.csv'].Hash = 'participant-edited'
        } else {
            $state.Search.datasources['bootcamp-baseline-v1-source'].Remove('credentials')
        }
        $before = $state.Requests.Count
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } | Should -Throw $Message
        $published.Count | Should -Be 0
        @($state.Requests | Select-Object -Skip $before | Where-Object { $_.Method -in @('Put', 'Delete') }).Count |
            Should -Be 0
    }

    It 'publishes nothing if a successful deployment omits required output' {
        Mock Invoke-MhhDeploymentWithRegionFallback {
            @{ Success = $true; LocationUsed = 'region-first'; Outputs = @{ ChatDeploymentName = 'chat' } }
        }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*missing required output*'
        $published.Count | Should -Be 0
    }

    It 'publishes nothing if the deployment omits the Search or Storage values' {
        Mock Invoke-MhhDeploymentWithRegionFallback {
            @{
                Success = $true
                LocationUsed = 'region-first'
                Outputs = @{
                    FoundryProjectEndpoint = 'https://foundry.example/api/projects/bootcamp'
                    ChatDeploymentName = 'bootcamp-chat'
                    EmbeddingDeploymentName = 'bootcamp-embedding'
                    StorageAccountName = 'stexample'
                    StorageBaselineContainerName = 'baseline'
                }
            }
        }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw "*missing required output 'SearchEndpoint'*"
        $published.Count | Should -Be 0
    }

    It 'submits a compilable keyless Foundry account and project with participant workload access' {
        $template = Join-Path $PSScriptRoot '..\..\labautomation\foundry-core.bicep'
        $template | Should -Exist
        $compiled = Join-Path $TestDrive 'foundry-core.json'
        & az bicep build --file $template --outfile $compiled --only-show-errors
        $LASTEXITCODE | Should -Be 0
        $arm = Get-Content $compiled -Raw | ConvertFrom-Json -AsHashtable
        $account = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts')
        $account.Count | Should -Be 1
        $account[0].kind | Should -Be 'AIServices'
        $account[0].properties.allowProjectManagement | Should -BeTrue
        $account[0].properties.disableLocalAuth | Should -BeTrue
        $account[0].identity.type | Should -Be 'SystemAssigned'
        $project = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/projects')
        $project.Count | Should -Be 1
        $project[0].identity.type | Should -Be 'SystemAssigned'
        $grant = @(Get-RoleGrants $arm | Where-Object Role -Match '53ca6127-db72-4b80-b1b0-d745d6d5456d')
        $grant.Count | Should -Be 1
        $grant[0].Principal | Should -Match 'participantObjectIds'
        $grant[0].PrincipalType | Should -Be 'User'
        $grant[0].Scope | Should -Match 'Microsoft.CognitiveServices/accounts'
        $arm.outputs.FoundryProjectEndpoint.type | Should -Be 'string'
        $arm.parameters.location.defaultValue | Should -Be '[resourceGroup().location]'
    }

    It 'adds keyless AI Search and Storage with a reusable baseline container' {
        $core = Get-CompiledCore
        $arm = $core.Arm
        $search = @($arm.resources | Where-Object type -eq 'Microsoft.Search/searchServices')
        $search.Count | Should -Be 1
        $search[0].properties.disableLocalAuth | Should -BeTrue
        $search[0].properties.Keys | Should -Not -Contain 'authOptions'
        $search[0].identity.type | Should -Be 'SystemAssigned'
        $storage = @($arm.resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts')
        $storage.Count | Should -Be 1
        $storage[0].properties.allowSharedKeyAccess | Should -BeFalse
        $storage[0].properties.allowBlobPublicAccess | Should -BeFalse
        $storage[0].properties.defaultToOAuthAuthentication | Should -BeTrue
        $container = @($arm.resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts/blobServices/containers')
        $container.Count | Should -Be 1
        $container[0].properties.publicAccess | Should -Be 'None'
        $arm.outputs.StorageBaselineContainerName.value | Should -Be 'baseline'
        $container[0].name | Should -Match 'baseline'
        $arm.outputs.SearchEndpoint.type | Should -Be 'string'
        $arm.outputs.StorageAccountName.type | Should -Be 'string'
        $core.Text | Should -Not -Match 'listKeys|listAdminKeys|listQueryKeys|InstrumentationKey'
        $tracing = @($arm.resources | Where-Object {
            $_.type -eq 'Microsoft.CognitiveServices/accounts/projects/connections' -and
            $_.properties.category -eq 'AppInsights'
        })
        $tracing.Count | Should -Be 1
        $tracing[0].properties.metadata.Remove('ApplicationInsightsConnectionString')
        ($arm | ConvertTo-Json -Depth 100) | Should -Not -Match 'ConnectionString|InstrumentationKey'
    }

    It 'connects workspace-based Application Insights to the Foundry project for keyless tracing' {
        $arm = (Get-CompiledCore).Arm
        $workspace = @($arm.resources | Where-Object type -eq 'Microsoft.OperationalInsights/workspaces')
        $workspace.Count | Should -Be 1
        $workspace[0].properties.features.disableLocalAuth | Should -BeTrue
        $insights = @($arm.resources | Where-Object type -eq 'Microsoft.Insights/components')
        $insights.Count | Should -Be 1
        $insights[0].properties.WorkspaceResourceId | Should -Match 'Microsoft.OperationalInsights/workspaces'
        $insights[0].properties.DisableLocalAuth | Should -BeTrue
        $connection = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/projects/connections' |
            Where-Object { $_.properties.category -eq 'AppInsights' })
        $connection.Count | Should -Be 1
        $connection[0].properties.authType | Should -Be 'ProjectManagedIdentity'
        $connection[0].properties.Keys | Should -Not -Contain 'credentials'
        $connection[0].properties.target | Should -Match 'Microsoft.Insights/components'
        $connection[0].properties.metadata.ApplicationInsightsConnectionString |
            Should -Match "reference\(resourceId\('Microsoft\.Insights/components'.*\.ConnectionString"
        $publisher = @(Get-RoleGrants $arm | Where-Object Role -Match '3913510d-42f4-4e42-8a64-420c390055eb')
        $publisher.Count | Should -Be 1
        $publisher[0].Principal | Should -Match 'accounts/projects'
        $publisher[0].PrincipalType | Should -Be 'ServicePrincipal'
        $publisher[0].Scope | Should -Match 'Microsoft.Insights/components'
    }

    It 'grants participants the agreed Search and Storage data-plane roles' {
        $grants = @(Get-RoleGrants (Get-CompiledCore).Arm | Where-Object PrincipalType -eq 'User')
        foreach ($expected in @(
            @{ Role = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Scope = 'Microsoft.Storage/storageAccounts' }
        )) {
            $grant = @($grants | Where-Object Role -Match $expected.Role)
            $grant.Count | Should -Be 1 -Because "participant role $($expected.Role)"
            $grant[0].Principal | Should -Match 'participantObjectIds'
            $grant[0].Scope | Should -Match $expected.Scope
        }
        $grants.Count | Should -Be 4
    }

    It 'grants the authenticated provisioner the scoped access needed to load and verify the baseline' {
        $grants = @(Get-RoleGrants (Get-CompiledCore).Arm |
            Where-Object Principal -Match "parameters\('provisionerObjectId'\)")
        foreach ($expected in @(
            @{ Role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Scope = 'Microsoft.Storage/storageAccounts' }
            @{ Role = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '1407120a-92aa-4202-b7e9-c0e197c71c8f'; Scope = 'Microsoft.Search/searchServices' }
        )) {
            @($grants | Where-Object { $_.Role -match $expected.Role -and $_.Scope -match $expected.Scope }).Count |
                Should -Be 1
        }

        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 1 -Exactly -ParameterFilter {
            $TemplateParameterObject.provisionerObjectId -eq '00000000-0000-0000-0000-000000000003'
        }
    }

    It 'binds workload managed identities to scoped Search, Foundry and Storage roles' {
        $arm = (Get-CompiledCore).Arm
        $grants = @(Get-RoleGrants $arm | Where-Object PrincipalType -eq 'ServicePrincipal')
        $expected = @(
            # Foundry account and project identities call the Search index from agent tools.
            @{ Role = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'; Principal = "accounts', variables\('accountName'\)\), '[^']+', 'full'\)\.identity"; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'; Principal = "accounts', variables\('accountName'\)\), '[^']+', 'full'\)\.identity"; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'; Principal = 'accounts/projects'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'; Principal = 'accounts/projects'; Scope = 'Microsoft.Search/searchServices' }
            # Search reads the baseline container; the full-text baseline needs no Foundry access.
            @{ Role = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'; Principal = 'Microsoft.Search/searchServices'; Scope = 'Microsoft.Storage/storageAccounts' }
            @{ Role = '3913510d-42f4-4e42-8a64-420c390055eb'; Principal = 'accounts/projects'; Scope = 'Microsoft.Insights/components' }
        )
        foreach ($binding in $expected) {
            @($grants | Where-Object { $_.Role -match $binding.Role -and $_.Principal -match $binding.Principal -and
                $_.Scope -match $binding.Scope }).Count | Should -Be 1 -Because "$($binding.Principal) needs $($binding.Role)"
        }
        $grants.Count | Should -Be $expected.Count
        @(Get-RoleGrants $arm | Where-Object Role -Match '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd').Count | Should -Be 0
        $search = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/projects/connections' |
            Where-Object { $_.properties.category -eq 'CognitiveSearch' })
        $search.Count | Should -Be 1
        $search[0].properties.authType | Should -Be 'ProjectManagedIdentity'
        $search[0].properties.Keys | Should -Not -Contain 'credentials'
    }

    It 'deploys the declared GA chat and embedding models with explicit versions and capacity' {
        $compiled = Join-Path $TestDrive 'models.json'
        & az bicep build --file (Join-Path $PSScriptRoot '..\..\labautomation\foundry-core.bicep') --outfile $compiled --only-show-errors
        $LASTEXITCODE | Should -Be 0
        $arm = Get-Content $compiled -Raw | ConvertFrom-Json -AsHashtable
        $models = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/deployments')
        $models.Count | Should -Be 2
        $chat = $models | Where-Object { $_.properties.model.name -eq 'gpt-5.4-mini' }
        $chat.properties.model.version | Should -Be '2026-03-17'
        $chat.sku.name | Should -Be 'GlobalStandard'
        $chat.sku.capacity | Should -Be 10
        $embedding = $models | Where-Object { $_.properties.model.name -eq 'text-embedding-3-small' }
        $embedding.properties.model.version | Should -Be '1'
        $embedding.sku.name | Should -Be 'GlobalStandard'
        $embedding.sku.capacity | Should -Be 10
        foreach ($model in $models) {
            $model.properties.model.format | Should -Be 'OpenAI'
            $model.properties.versionUpgradeOption | Should -Be 'NoAutoUpgrade'
        }
        $arm.outputs.ChatDeploymentName.value | Should -Be 'bootcamp-chat'
        $arm.outputs.EmbeddingDeploymentName.value | Should -Be 'bootcamp-embedding'
    }
}
