BeforeAll {
    $script:Hook = Join-Path $PSScriptRoot '..\..\labautomation\deploy-lab.ps1'
    function Get-AzContext {}
    function Get-AzResourceGroup {}
    function Get-AzResource { param($ResourceGroupName) }
    function Get-MhhStableHash { param($InputString, $Length) }
    function Remove-MhhResourceGroup { param($ResourceGroupName) }
    function Get-AzResourceLock { param($ResourceGroupName) }
    function Get-AzResourceGroupDeployment { param($ResourceGroupName) }
    function Get-AzRoleAssignment { param($Scope) }
    function New-AzResourceGroupDeployment {
        param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterObject, $Mode)
    }
    function Invoke-MhhDeploymentWithRegionFallback {
        param($PreferredLocations, $ResourceGroupName, $RgOwnerEntraObjectIds, $TemplateFile,
            $TemplateParameterObject, $DeploymentNamePrefix)
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
                }
            }
        }
    }

    AfterEach {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $script:PreviousOptIn
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
        $credentials.Count | Should -Be 5
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

    It 'pins even an empty participant retry to the existing region without organizer opt-in' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        $script:Inputs.PreferredLocation = @('region-second')
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -ParameterFilter {
            $TemplateParameterObject.location -eq 'region-first' -and $Mode -eq 'Incremental'
        }
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

    It 'does not recreate a missing participant RG on retry' {
        Mock Get-AzResourceGroup { @() }
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        { & $script:Hook @script:Inputs } | Should -Throw '*organizer must perform initial provisioning*'
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 0
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

    It 'publishes nothing if a successful deployment omits required output' {
        Mock Invoke-MhhDeploymentWithRegionFallback {
            @{ Success = $true; LocationUsed = 'region-first'; Outputs = @{ ChatDeploymentName = 'chat' } }
        }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*missing required output*'
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
        $grant = @($arm.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')
        $grant.Count | Should -Be 1
        $roleId = $grant[0].properties.roleDefinitionId
        if ($roleId -match "^\[variables\('([^']+)'\)\]$") {
            $roleId = $arm.variables[$Matches[1]]
        }
        $roleId | Should -Match '53ca6127-db72-4b80-b1b0-d745d6d5456d'
        $grant[0].properties.principalId | Should -Match 'participantObjectIds'
        $grant[0].properties.principalType | Should -Be 'User'
        $grant[0].scope | Should -Match 'Microsoft.CognitiveServices/accounts'
        $arm.outputs.FoundryProjectEndpoint.type | Should -Be 'string'
        $arm.parameters.location.defaultValue | Should -Be '[resourceGroup().location]'
        $arm.resources.type | Should -Not -Contain 'Microsoft.Search/searchServices'
        $arm.resources.type | Should -Not -Contain 'Microsoft.Storage/storageAccounts'
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
