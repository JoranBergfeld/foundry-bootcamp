BeforeAll {
    . (Join-Path $PSScriptRoot 'Fake-AzureDataPlane.ps1')
    $script:Hook = Join-Path $PSScriptRoot '..\..\labautomation\deploy-lab.ps1'
    function Invoke-TestEvals {
        & (Join-Path $PSScriptRoot '..\..\labautomation\provision-evals.ps1') `
            -ProjectEndpoint 'https://foundry.example/api/projects/bootcamp' `
            -ProjectResourceId '/subscriptions/sub/resourceGroups/participant/providers/Microsoft.CognitiveServices/accounts/foundry/projects/bootcamp' `
            -ChatDeploymentName 'bootcamp-chat' -StorageAccountName 'stexample' -ContainerName 'baseline'
    }
    function Get-AzContext {}
    function Get-AzAccessToken { param($ResourceUrl) }
    function Get-AzResourceGroup {}
    function Get-AzResource { param($ResourceGroupName) }
    function Invoke-AzRestMethod { param($Method, $Path) }
    function Get-MhhStableHash { param($InputString, $Length) }
    function Remove-MhhResourceGroup { param($ResourceGroupName) }
    function Get-AzResourceLock { param($ResourceGroupName) }
    function Get-AzResourceGroupDeployment { param($ResourceGroupName) }
    function Get-AzRoleAssignment { param($Scope) }
    function Remove-AzRoleAssignment { param($ObjectId, $RoleDefinitionId, $Scope) }
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
    It 'packages evaluation inputs and their license byte-for-byte from the participant lab' {
        $source = Join-Path $PSScriptRoot '..\..\labs\03-evaluate'
        $archive = [IO.Compression.ZipFile]::OpenRead(
            (Join-Path $PSScriptRoot '..\..\labautomation\dataset\support-evals-v2.zip'))
        try {
            $expected = @('SOURCE-LICENSE.txt', 'dataset/support-golden-v2.jsonl') +
                @(Get-ChildItem (Join-Path $source 'knowledge') -File | ForEach-Object { "knowledge/$($_.Name)" })
            $archive.Entries.FullName | Sort-Object | Should -Be ($expected | Sort-Object)
            foreach ($path in $expected) {
                $stream = $archive.GetEntry($path).Open()
                $buffer = [IO.MemoryStream]::new()
                try {
                    $stream.CopyTo($buffer)
                    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($buffer.ToArray())) |
                        Should -Be (Get-FileHash (Join-Path $source $path) -Algorithm SHA256).Hash
                } finally {
                    $stream.Dispose()
                    $buffer.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
    }

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
        Mock Invoke-AzRestMethod { @{ Content = '{"sku":{"name":"basic"}}' } }
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
        Mock Remove-AzRoleAssignment {}
        Mock Remove-MhhResourceGroup {
            @{ ManifestCaptured = $true; Errors = @(); SoftDeletedResidual = @() }
        }
        Mock New-AzResourceGroupDeployment {
            @{
                ProvisioningState = 'Succeeded'
                Outputs = @{
                    FoundryProjectEndpoint = @{ Value = 'https://foundry.example/api/projects/bootcamp' }
                    ChatDeploymentName = @{ Value = 'bootcamp-chat' }
                    JudgeDeploymentName = @{ Value = 'bootcamp-judge' }
                    FoundryProjectResourceId = @{ Value = '/subscriptions/sub/resourceGroups/participant/providers/Microsoft.CognitiveServices/accounts/foundry/projects/bootcamp' }
                    EmbeddingDeploymentName = @{ Value = 'bootcamp-embedding' }
                    SecondaryFoundryProjectEndpoint = @{ Value = 'https://foundry-alt.example/api/projects/bootcamp' }
                    SecondaryChatDeploymentName = @{ Value = 'bootcamp-chat-nano' }
                    McpServerUrl = @{ Value = 'https://mcp.example/mcp' }
                    McpConnectionName = @{ Value = 'bootcamp-date-time' }
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
                    JudgeDeploymentName = 'bootcamp-judge'
                    FoundryProjectResourceId = '/subscriptions/sub/resourceGroups/participant/providers/Microsoft.CognitiveServices/accounts/foundry/projects/bootcamp'
                    EmbeddingDeploymentName = 'bootcamp-embedding'
                    SecondaryFoundryProjectEndpoint = 'https://foundry-alt.example/api/projects/bootcamp'
                    SecondaryChatDeploymentName = 'bootcamp-chat-nano'
                    McpServerUrl = 'https://mcp.example/mcp'
                    McpConnectionName = 'bootcamp-date-time'
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
            $TemplateParameterObject.participantObjectIds[0] -eq '00000000-0000-0000-0000-000000000002' -and
            $TemplateParameterObject.existingFoundryAccountNames.Count -eq 0 -and
            $TemplateParameterObject.existingSearchServiceSkus.Count -eq 0
        }
        $credentials.Count | Should -Be 21
        $values = @{}
        foreach ($credential in $credentials) {
            $credential | Should -BeOfType [hashtable]
            $values[$credential.HackboxCredential.name] = $credential.HackboxCredential.value
        }
        $values.ResourceGroupName | Should -Be 'participant'
        $values.Region | Should -Be 'region-second'
        $values.FoundryProjectEndpoint | Should -Be 'https://foundry.example/api/projects/bootcamp'
        $values.ChatDeploymentName | Should -Be 'bootcamp-chat'
        $values.JudgeDeploymentName | Should -Be 'bootcamp-judge'
        $values.EmbeddingDeploymentName | Should -Be 'bootcamp-embedding'
        $values.SecondaryFoundryProjectEndpoint | Should -Be 'https://foundry-alt.example/api/projects/bootcamp'
        $values.SecondaryChatDeploymentName | Should -Be 'bootcamp-chat-nano'
        $values.McpServerUrl | Should -Be 'https://mcp.example/mcp'
        $values.McpConnectionName | Should -Be 'bootcamp-date-time'
        $values.SearchEndpoint | Should -Be 'https://srch.example.search.windows.net'
        $values.StorageAccountName | Should -Be 'stexample'
        $values.StorageBaselineContainerName | Should -Be 'baseline'
        $values.BaselineIndexName | Should -Be 'bootcamp-baseline-v1'
    }

    It 'never calls destructive fallback on a populated RG even with organizer opt-in' {
        Mock Get-AzResource {
            @(
                @{ ResourceType = 'Microsoft.CognitiveServices/accounts'; Name = 'foundry-abcdefghijklm' }
                @{ ResourceType = 'Microsoft.CognitiveServices/accounts'; Name = 'foundry-alt-abcdefghijklm' }
            )
        }
        $credentials = @(& $script:Hook @script:Inputs)
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $Mode -eq 'Incremental' -and $ResourceGroupName -eq 'participant' -and
            $TemplateParameterObject.location -eq 'region-first' -and
            $TemplateParameterObject.existingFoundryAccountNames.Count -eq 2 -and
            'foundry-abcdefghijklm' -in $TemplateParameterObject.existingFoundryAccountNames -and
            'foundry-alt-abcdefghijklm' -in $TemplateParameterObject.existingFoundryAccountNames
        }
        ($credentials | Where-Object { $_.HackboxCredential.name -eq 'Region' }).HackboxCredential.value |
            Should -Be 'region-first'
    }

    It 'fails before deployment when a Foundry account inventory entry has no name' {
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.CognitiveServices/accounts'; Name = '' } }
        { & $script:Hook @script:Inputs } | Should -Throw '*Foundry account inventory*without a name*'
        Should -Invoke New-AzResourceGroupDeployment -Times 0
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
    }

    It 'preserves an existing <Sku> Search service instead of migrating it in place' -ForEach @(
        @{ Sku = 'basic' }
        @{ Sku = 'serverless' }
    ) {
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices'; Name = 'srch-example' } }
        Mock Invoke-AzRestMethod { @{ Content = "{`"sku`":{`"name`":`"$Sku`"}}" } }
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Path -eq '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/participant/providers/Microsoft.Search/searchServices/srch-example?api-version=2026-11-01'
        }
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $Mode -eq 'Incremental' -and $TemplateParameterObject.existingSearchServiceSkus['srch-example'] -eq $Sku
        }
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
        Should -Invoke Remove-MhhResourceGroup -Times 0
    }

    It 'fails before deployment when an existing Search SKU cannot be read: <Response>' -ForEach @(
        @{ Response = '{}' }
        @{ Response = '{"sku":null}' }
        @{ Response = '{"sku":{}}' }
    ) {
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices'; Name = 'srch-example' } }
        Mock Invoke-AzRestMethod { @{ Content = $Response } }
        { & $script:Hook @script:Inputs } | Should -Throw '*no readable SKU*No tier change was attempted*'
        Should -Invoke New-AzResourceGroupDeployment -Times 0
        Should -Invoke Invoke-MhhDeploymentWithRegionFallback -Times 0
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
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices'; Name = 'srch-example' } }
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

    It 'removes only participants direct subscription Reader grants' {
        $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null
        $subscriptionScope = '/subscriptions/00000000-0000-0000-0000-000000000001'
        Mock Get-AzRoleAssignment {
            @(
                @{
                    Scope = $subscriptionScope
                    ObjectId = '00000000-0000-0000-0000-000000000002'
                    RoleDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
                }
                @{
                    Scope = $subscriptionScope
                    ObjectId = '00000000-0000-0000-0000-000000000002'
                    RoleDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
                }
                @{
                    Scope = $subscriptionScope
                    ObjectId = '00000000-0000-0000-0000-000000000099'
                    RoleDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
                }
                @{
                    Scope = "$subscriptionScope/resourceGroups/participant"
                    ObjectId = '00000000-0000-0000-0000-000000000002'
                    RoleDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
                }
                @{
                    Scope = "$subscriptionScope/resourceGroups/participant"
                    ObjectId = '00000000-0000-0000-0000-000000000002'
                    RoleDefinitionId = "$subscriptionScope/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
                    Condition = $null
                }
            )
        }

        & $script:Hook @script:Inputs | Out-Null

        Should -Invoke Remove-AzRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $ObjectId -eq '00000000-0000-0000-0000-000000000002' -and
            $RoleDefinitionId -eq 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -and
            $Scope -eq $subscriptionScope
        }
        Should -Invoke New-AzRoleAssignment -Times 0
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

    It 'uploads every ticket and publishes a queryable keyless baseline index: <Path>' -ForEach @(
        @{ Path = 'incremental' }
        @{ Path = 'initial fallback' }
    ) {
        if ($Path -eq 'incremental') { $env:BOOTCAMP_ORGANIZER_INITIAL_PROVISIONING = $null }
        $credentials = @(& $script:Hook @script:Inputs)
        $indexName = ($credentials | Where-Object { $_.HackboxCredential.name -eq 'BaselineIndexName' }).HackboxCredential.value
        $indexName | Should -Be 'bootcamp-baseline-v1'
        @($global:ProvisioningTestDataPlane.Blobs.Keys | Where-Object { $_ -like '/baseline/dataset-v1/*' }).Count |
            Should -Be 10
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
        $state = $global:ProvisioningTestDataPlane
        $searchRequests = @($state.Requests | Where-Object { ([uri]$_.Uri).Host -eq 'srch.example.search.windows.net' })
        $searchRequests.Count | Should -BeGreaterThan 0
        @($searchRequests | Where-Object { ([uri]$_.Uri).Query -notmatch 'api-version=2026-10-01(?:&|$)' }).Count |
            Should -Be 0
        $fields = $state.Search.indexes['bootcamp-baseline-v1'].fields
        ($fields.name -join ',') | Should -Be (
            'ticket_id,created_at,customer_id,customer_segment,channel,product_area,issue_type,priority,status,sla_plan,' +
            'initial_message,agent_first_reply,resolution_summary,resolution_time_hours,reopened,customer_sentiment,' +
            'csat_score,has_attachment,platform,region'
        )
        @($fields | Where-Object key -eq $true).name | Should -Be 'ticket_id'
        @($fields | Where-Object { $_.type -ne 'Edm.String' -or -not $_.retrievable }).Count | Should -Be 0
        $query = @($state.Requests | Where-Object { $_.Uri -match '/docs/search\.post\.search\?' })[-1].Body |
            ConvertFrom-Json -AsHashtable
        $query.search | Should -Be 'password'
        $query.filter | Should -Be "ticket_id eq 'TCKT_000001'"
        $query.searchFields | Should -Be 'initial_message'
    }

    It 'preserves existing Storage tags while replacing the security control tag' {
        Mock Get-AzResource {
            @(
                @{ ResourceType = 'Microsoft.Storage/storageAccounts'; Name = 'stexample'; Tags = @{ owner = 'team'; securitycontrol = 'Enforce' } }
                @{ ResourceType = 'Microsoft.Storage/storageAccounts'; Name = 'stuntagged'; Tags = $null }
            )
        }
        & $script:Hook @script:Inputs | Out-Null
        Should -Invoke New-AzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $tags = $TemplateParameterObject.existingStorageAccountTags
            $tags['stexample']['owner'] -eq 'team' -and
            -not $tags['stexample'].ContainsKey('securitycontrol') -and
            $tags['stuntagged'].Count -eq 0
        }
    }

    It 'does not publish a baseline when policy still blocks Storage network access' {
        $global:ProvisioningTestDataPlane.StoragePublicNetworkAccess = 'Disabled'
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*Storage public network access is disabled by policy*'
        $published.Count | Should -Be 0
        $global:ProvisioningTestDataPlane.Search.indexes.Count | Should -Be 0
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
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices'; Name = 'srch-example' } }
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
        Mock Get-AzResource { @{ ResourceType = 'Microsoft.Search/searchServices'; Name = 'srch-example' } }
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

    It 'uploads the golden dataset separately from the three indexed knowledge files and attaches the toolbox to a prompt agent' {
        $assets = Invoke-TestEvals
        $state = $global:ProvisioningTestDataPlane
        $assets.EvalsDatasetName | Should -Be 'support-golden-v2'
        $dataset = $state.Foundry.Datasets['support-golden-v2/1']
        $dataset.type | Should -Be 'uri_file'
        $dataset.connectionName | Should -Be 'bootcamp-evals-storage'
        $dataset.dataUri | Should -Be 'https://stexample.blob.core.windows.net/baseline/evals/support-golden-v2.jsonl'
        @($state.Blobs['/baseline/evals/support-golden-v2.jsonl'].Content -split "`n" | Where-Object { $_ }) |
            Should -HaveCount 8
        $state.Foundry.Files.Count | Should -Be 3
        @($state.Foundry.Files.Values | Where-Object { $_.filename -like '*golden*' }).Count | Should -Be 0
        $state.Foundry.Stores[$assets.EvalsVectorStoreId].file_ids.Count | Should -Be 3
        $toolbox = $state.Foundry.toolboxes[$assets.EvalsToolboxName][0]
        $toolbox.tools[0].type | Should -Be 'file_search'
        $toolbox.tools[0].vector_store_ids[0] | Should -Be $assets.EvalsVectorStoreId
        $agent = $state.Foundry.agents[$assets.EvalsAgentName][0]
        $agent.definition.kind | Should -Be 'prompt'
        $agent.definition.model | Should -Be 'bootcamp-chat'
        $agent.definition.instructions | Should -Match 'Routing override:.*wait until Monday'
        $agent.definition.tools[0].type | Should -Be 'mcp'
        $agent.definition.tools[0].server_url | Should -BeLike '*/toolboxes/bootcamp-support-evals/versions/1/mcp?api-version=v1'
        $agent.definition.tools[0].project_connection_id | Should -Be 'bootcamp-evals-toolbox'
        $state.Foundry.Connections['bootcamp-evals-toolbox'].properties.authType | Should -Be 'UserEntraToken'
        $state.Foundry.Connections['bootcamp-evals-toolbox'].properties.audience | Should -Be 'https://ai.azure.com'
    }

    It 'provisions evaluation assets when the ARM project has no amlWorkspace property' {
        $state = $global:ProvisioningTestDataPlane
        $state.ProjectProperties.ContainsKey('amlWorkspace') | Should -BeFalse
        $assets = Invoke-TestEvals
        $assets.EvalsDatasetName | Should -Be 'support-golden-v2'
        $fileRequests = @($state.Requests | Where-Object { $_.Uri -like '*/openai/v1/*' })
        $fileRequests.Count | Should -BeGreaterThan 0
        foreach ($request in $fileRequests) {
            $request.Uri | Should -BeLike 'https://foundry.example/api/projects/bootcamp/openai/v1/*'
            $request.Headers.ContainsKey('x-aml-project-id') | Should -BeFalse
        }
        @($state.Requests | Where-Object {
            ([uri]$_.Uri).Host -eq 'management.azure.com' -and
                ([uri]$_.Uri).AbsolutePath.EndsWith('/projects/bootcamp')
        }).Count | Should -Be 0
        $state.Foundry.Files.Count | Should -Be 3
        $state.Foundry.Stores[$assets.EvalsVectorStoreId].file_ids | Should -HaveCount 3
    }

    It 'provisions evaluation assets from the isolated MicroHack lab directory without sibling participant labs' {
        $runner = Join-Path $TestDrive 'microhack'
        $null = New-Item -ItemType Directory -Path $runner -Force
        Copy-Item (Join-Path $PSScriptRoot '..\..\labautomation') (Join-Path $runner 'lab') -Recurse
        (Join-Path $runner 'labs') | Should -Not -Exist

        $assets = & (Join-Path $runner 'lab\provision-evals.ps1') `
            -ProjectEndpoint 'https://foundry.example/api/projects/bootcamp' `
            -ProjectResourceId '/subscriptions/sub/resourceGroups/participant/providers/Microsoft.CognitiveServices/accounts/foundry/projects/bootcamp' `
            -ChatDeploymentName 'bootcamp-chat' -StorageAccountName 'stexample' -ContainerName 'baseline'

        $assets.EvalsDatasetName | Should -Be 'support-golden-v2'
        $state = $global:ProvisioningTestDataPlane
        $source = Join-Path $PSScriptRoot '..\..\labs\03-evaluate'
        $state.Blobs['/baseline/evals/support-golden-v2.jsonl'].Content |
            Should -BeExactly ([IO.File]::ReadAllText((Join-Path $source 'dataset\support-golden-v2.jsonl')))
        $state.Foundry.Files.Count | Should -Be 3
        foreach ($file in Get-ChildItem (Join-Path $source 'knowledge') -File) {
            $uploaded = @($state.Foundry.Files.Values | Where-Object { $_.filename.EndsWith("-$($file.Name)") })
            $uploaded | Should -HaveCount 1
            $uploaded[0].Content | Should -BeExactly ([IO.File]::ReadAllText($file.FullName))
        }
        $state.Foundry.Stores[$assets.EvalsVectorStoreId].file_ids | Should -HaveCount 3
    }

    It 'reuses the pinned baseline through paginated listings and preserves participant agent and toolbox versions' {
        $original = Invoke-TestEvals
        $state = $global:ProvisioningTestDataPlane
        foreach ($kind in @('agents', 'toolboxes')) {
            $name = if ($kind -eq 'agents') { $original.EvalsAgentName } else { $original.EvalsToolboxName }
            $participant = $state.Foundry[$kind][$name][0] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -AsHashtable
            $participant.version = '2'
            $participant.id = "participant-$kind"
            if ($kind -eq 'agents') { $participant.definition.instructions = 'Participant fixed routing.' } else {
                $participant.tools = @(@{ type = 'web_search' })
            }
            $state.Foundry[$kind][$name] += $participant
        }
        $state.EvalsPageSize = 1
        $state.EvalsMcpSse = $true
        $before = $state.Requests.Count
        $rerun = Invoke-TestEvals
        $rerun.EvalsAgentVersion | Should -Be $original.EvalsAgentVersion
        $rerun.EvalsToolboxVersion | Should -Be $original.EvalsToolboxVersion
        $rerun.EvalsVectorStoreId | Should -Be $original.EvalsVectorStoreId
        @($state.Requests | Select-Object -Skip $before | Where-Object {
            $_.Method -in @('Put', 'Patch', 'Delete') -or
            ($_.Method -eq 'Post' -and $_.Uri -notlike '*/search' -and $_.Uri -notlike '*/mcp?*')
        }).Count | Should -Be 0
        $state.Foundry.agents[$original.EvalsAgentName][1].definition.instructions | Should -Be 'Participant fixed routing.'
        $state.Foundry.toolboxes[$original.EvalsToolboxName][1].tools[0].type | Should -Be 'web_search'
    }

    It 'stops on incompatible existing eval <Resource> without overwriting it' -ForEach @(
        @{ Resource = 'dataset'; Message = '*dataset*incompatible*not overwritten*' }
        @{ Resource = 'file'; Message = '*file*different content*not replaced*' }
        @{ Resource = 'store'; Message = '*vector store*incompatible*not modified*' }
        @{ Resource = 'toolbox'; Message = '*toolboxes*no compatible*not modified*' }
        @{ Resource = 'connection'; Message = '*connection*incompatible*not overwritten*' }
        @{ Resource = 'agent'; Message = '*agents*no compatible*not modified*' }
    ) {
        $assets = Invoke-TestEvals
        $state = $global:ProvisioningTestDataPlane
        switch ($Resource) {
            dataset { $state.Foundry.Datasets['support-golden-v2/1'].tags.sha256 = 'participant' }
            file { $state.Foundry.Files['file-1'].Content = 'participant content' }
            store { $state.Foundry.Stores[$assets.EvalsVectorStoreId].metadata['bootcamp-source-sha256'] = 'participant' }
            toolbox { $state.Foundry.toolboxes[$assets.EvalsToolboxName][0].tools = @(@{ type = 'web_search' }) }
            connection { $state.Foundry.Connections['bootcamp-evals-toolbox'].properties.authType = 'None' }
            agent { $state.Foundry.agents[$assets.EvalsAgentName][0].definition.model = 'participant-model' }
        }
        $before = $state.Requests.Count
        { Invoke-TestEvals } | Should -Throw $Message
        @($state.Requests | Select-Object -Skip $before | Where-Object {
            $_.Method -in @('Put', 'Patch', 'Delete') -or
            ($_.Method -eq 'Post' -and $_.Uri -notlike '*/search' -and $_.Uri -notlike '*/mcp?*')
        }).Count | Should -Be 0
    }

    It 'does not replay an uncertain file create and reconciles the partial upload on rerun' {
        Mock Invoke-WebRequest {
            if ($Uri -eq 'https://foundry.example/api/projects/bootcamp/openai/v1/files' -and $Method -eq 'Post' -and
                $global:ProvisioningTestDataPlane.Foundry.Files.Count -eq 2) {
                return [pscustomobject]@{ StatusCode = 500; Content = 'Uncertain create'; Headers = @{} }
            }
            Invoke-FakeAzureDataPlane -Uri $Uri -Method $Method -Headers $Headers -Body $Body -State $global:ProvisioningTestDataPlane
        }
        { Invoke-TestEvals } | Should -Throw '*HTTP 500*'
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly -ParameterFilter {
            $Uri -eq 'https://foundry.example/api/projects/bootcamp/openai/v1/files' -and $Method -eq 'Post'
        }
        Mock Invoke-WebRequest {
            Invoke-FakeAzureDataPlane -Uri $Uri -Method $Method -Headers $Headers -Body $Body -State $global:ProvisioningTestDataPlane
        }
        Invoke-TestEvals | Out-Null
        $global:ProvisioningTestDataPlane.Foundry.Files.Count | Should -Be 3
        $global:ProvisioningTestDataPlane.Foundry.Stores.Count | Should -Be 1
    }

    It 'does not provision the toolbox before <Status> knowledge ingestion is resolved' -ForEach @(
        @{ Status = 'failed'; Message = '*ingestion failed*' }
        @{ Status = 'in_progress'; Message = '*ingestion did not finish*' }
    ) {
        $state = $global:ProvisioningTestDataPlane
        $state.EvalsIngestionStatus = $Status
        { Invoke-TestEvals } | Should -Throw $Message
        $state.Foundry.toolboxes.Count | Should -Be 0
        $state.Foundry.agents.Count | Should -Be 0
    }

    It 'refuses an incomplete existing store rather than silently replacing it' {
        $assets = Invoke-TestEvals
        $state = $global:ProvisioningTestDataPlane
        $state.Foundry.Stores[$assets.EvalsVectorStoreId].file_ids = @('file-1', 'file-2')
        { Invoke-TestEvals } | Should -Throw '*exactly the three expected knowledge files*'
        $state.Foundry.Stores.Count | Should -Be 1
    }

    It 'publishes no credentials when eval knowledge is not queryable' {
        $global:ProvisioningTestDataPlane.EvalsSearchEmpty = $true
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw '*did not retrieve the urgent support policy*'
        $published.Count | Should -Be 0
    }

    It 'does not create an agent when toolbox discovery returns a JSON-RPC error' {
        $global:ProvisioningTestDataPlane.EvalsMcpError = $true
        { Invoke-TestEvals } | Should -Throw '*toolbox MCP initialize failed*Toolbox denied*'
        $global:ProvisioningTestDataPlane.Foundry.agents.Count | Should -Be 0
    }

    It 'publishes nothing when the new required <Output> is missing' -ForEach @(
        @{ Output = 'SecondaryFoundryProjectEndpoint' }
        @{ Output = 'SecondaryChatDeploymentName' }
        @{ Output = 'McpServerUrl' }
        @{ Output = 'McpConnectionName' }
        @{ Output = 'JudgeDeploymentName' }
        @{ Output = 'FoundryProjectResourceId' }
    ) {
        Mock Invoke-MhhDeploymentWithRegionFallback {
            $outputs = @{
                FoundryProjectEndpoint = 'https://foundry.example/api/projects/bootcamp'
                ChatDeploymentName = 'bootcamp-chat'
                JudgeDeploymentName = 'bootcamp-judge'
                FoundryProjectResourceId = '/subscriptions/sub/resourceGroups/participant/providers/Microsoft.CognitiveServices/accounts/foundry/projects/bootcamp'
                EmbeddingDeploymentName = 'bootcamp-embedding'
                SecondaryFoundryProjectEndpoint = 'https://foundry-alt.example/api/projects/bootcamp'
                SecondaryChatDeploymentName = 'bootcamp-chat-nano'
                McpServerUrl = 'https://mcp.example/mcp'
                McpConnectionName = 'bootcamp-date-time'
                SearchEndpoint = 'https://srch.example.search.windows.net'
                StorageAccountName = 'stexample'
                StorageBaselineContainerName = 'baseline'
            }
            $outputs.Remove($Output)
            @{ Success = $true; LocationUsed = 'region-first'; Outputs = $outputs }
        }
        $published = [System.Collections.Generic.List[object]]::new()
        { & $script:Hook @script:Inputs | ForEach-Object { $published.Add($_) } } |
            Should -Throw "*missing required output '$Output'*"
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
        $account.Count | Should -Be 2
        foreach ($item in $account) {
            $item.kind | Should -Be 'AIServices'
            $item.properties.allowProjectManagement | Should -BeTrue
            $item.properties.disableLocalAuth | Should -BeTrue
            $item.identity.type | Should -Be 'SystemAssigned'
        }
        ($account.name | Select-Object -Unique).Count | Should -Be 2
        $project = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/projects')
        $project.Count | Should -Be 2
        foreach ($item in $project) { $item.identity.type | Should -Be 'SystemAssigned' }
        @($project | Where-Object { $_.properties.displayName -eq 'Sir Prompts-a-Lot' }).Count | Should -Be 1
        @($project | Where-Object { $_.properties.displayName -eq 'Count Tokenstein' }).Count | Should -Be 1
        $grant = @(Get-RoleGrants $arm | Where-Object {
            $_.Role -match '53ca6127-db72-4b80-b1b0-d745d6d5456d' -and $_.Principal -match 'participantObjectIds'
        })
        $grant.Count | Should -Be 2
        foreach ($item in $grant) {
            $item.Principal | Should -Match 'participantObjectIds'
            $item.PrincipalType | Should -Be 'User'
            $item.Scope | Should -Match 'Microsoft.CognitiveServices/accounts'
        }
        ($grant.Scope | Select-Object -Unique).Count | Should -Be 2
        $arm.outputs.FoundryProjectEndpoint.type | Should -Be 'string'
        $arm.outputs.SecondaryFoundryProjectEndpoint.value | Should -Match 'secondaryAccountName'
        $arm.parameters.location.defaultValue | Should -Be '[resourceGroup().location]'
    }

    It 'selects distinctive names for new accounts while retaining legacy names and rejecting ambiguity' {
        $arm = (Get-CompiledCore).Arm
        $arm.parameters.existingFoundryAccountNames.Keys | Should -Not -Contain 'defaultValue'
        $arm.variables.existingFoundryNames | Should -Match "toLower\(lambdaVariables\('name'\)\)"
        foreach ($choice in @(
            @{ Variable = 'accountName'; Legacy = 'legacyAccountName'; LegacyPrefix = 'foundry'; Named = 'namedAccountName'; Prefix = 'foundry-sir-prompts-a-lot'; Label = 'primary' }
            @{ Variable = 'secondaryAccountName'; Legacy = 'legacySecondaryAccountName'; LegacyPrefix = 'foundry-alt'; Named = 'namedSecondaryAccountName'; Prefix = 'foundry-count-tokenstein'; Label = 'secondary' }
        )) {
            $arm.variables[$choice.Legacy] | Should -Match "format\('$($choice.LegacyPrefix)-\{0\}', variables\('suffix'\)\)"
            $arm.variables[$choice.Named] | Should -Match "format\('$($choice.Prefix)-\{0\}', variables\('suffix'\)\)"
            $expression = $arm.variables[$choice.Variable]
            $legacy = [regex]::Escape("variables('$($choice.Legacy)')")
            $named = [regex]::Escape("variables('$($choice.Named)')")
            $existing = [regex]::Escape("variables('existingFoundryNames')")
            $expression | Should -Match "if\(and\(contains\($existing, $legacy\), contains\($existing, $named\)\), fail\('Both $($choice.Label)"
            $expression | Should -Match "if\(contains\($existing, $legacy\), $legacy, $named\)"
        }
    }

    It 'adds keyless AI Search and Storage with a reusable baseline container' {
        $core = Get-CompiledCore
        $arm = $core.Arm
        $search = @($arm.resources | Where-Object type -eq 'Microsoft.Search/searchServices')
        $search.Count | Should -Be 1
        $search[0].apiVersion | Should -Be '2026-11-01'
        $arm.parameters.existingSearchServiceSkus.defaultValue.Count | Should -Be 0
        $arm.variables.existingSearchSku | Should -Match "contains\(parameters\('existingSearchServiceSkus'\), variables\('searchName'\)\)"
        $arm.variables.existingSearchSku | Should -Match ", 'serverless'\)"
        $search[0].sku.name | Should -Be "[variables('searchSku')]"
        $search[0].properties | Should -Match "if\(equals\(variables\('searchSku'\), 'basic'\), createObject\('replicaCount', 1, 'partitionCount', 1\), createObject\(\)\)"
        $search[0].properties | Should -Match "'disableLocalAuth', true"
        $search[0].properties | Should -Not -Match 'authOptions'
        $search[0].identity.type | Should -Be 'SystemAssigned'
        $storage = @($arm.resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts')
        $storage.Count | Should -Be 1
        $storage[0].tags | Should -Match 'existingStorageAccountTags'
        $storage[0].tags | Should -Match "'SecurityControl', 'Ignore'"
        $storage[0].properties.publicNetworkAccess | Should -Be 'Enabled'
        $storage[0].properties.networkAcls.defaultAction | Should -Be 'Allow'
        $storage[0].properties.allowSharedKeyAccess | Should -BeFalse
        $storage[0].properties.allowBlobPublicAccess | Should -BeFalse
        $storage[0].properties.defaultToOAuthAuthentication | Should -BeTrue
        @($arm.resources | Where-Object type -eq 'Microsoft.Authorization/policyExemptions').Count | Should -Be 0
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
        $grants.Count | Should -Be 5
    }

    It 'grants the authenticated provisioner the scoped access needed to load and verify the baseline' {
        $grants = @(Get-RoleGrants (Get-CompiledCore).Arm |
            Where-Object Principal -Match "parameters\('provisionerObjectId'\)")
        foreach ($expected in @(
            @{ Role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Scope = 'Microsoft.Storage/storageAccounts' }
            @{ Role = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '1407120a-92aa-4202-b7e9-c0e197c71c8f'; Scope = 'Microsoft.Search/searchServices' }
            @{ Role = '53ca6127-db72-4b80-b1b0-d745d6d5456d'; Scope = 'Microsoft.CognitiveServices/accounts' }
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
            @{ Role = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'; Principal = 'accounts/projects'; Scope = 'Microsoft.Storage/storageAccounts' }
        )
        foreach ($binding in $expected) {
            @($grants | Where-Object { $_.Role -match $binding.Role -and $_.Principal -match $binding.Principal -and
                $_.Scope -match $binding.Scope }).Count | Should -Be 1 -Because "$($binding.Principal) needs $($binding.Role)"
        }
        $storageConnection = @($arm.resources | Where-Object {
            $_.type -eq 'Microsoft.CognitiveServices/accounts/projects/connections' -and
            $_.properties.category -eq 'AzureStorageAccount'
        })
        $storageConnection.Count | Should -Be 1
        $storageConnection[0].name | Should -Match 'bootcamp-evals-storage'
        $storageConnection[0].properties.authType | Should -Be 'ProjectManagedIdentity'
        $storageConnection[0].properties.Keys | Should -Not -Contain 'credentials'
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
        $models.Count | Should -Be 4
        $chat = $models | Where-Object { $_.properties.model.name -eq 'gpt-5.4-mini' }
        $chat.properties.model.version | Should -Be '2026-03-17'
        $chat.sku.name | Should -Be 'GlobalStandard'
        $chat.sku.capacity | Should -Be 10
        $embedding = $models | Where-Object { $_.properties.model.name -eq 'text-embedding-3-small' }
        $embedding.properties.model.version | Should -Be '1'
        $embedding.sku.name | Should -Be 'GlobalStandard'
        $embedding.sku.capacity | Should -Be 10
        $nano = $models | Where-Object { $_.name -match 'secondaryAccountName' }
        $nano.properties.model.version | Should -Be '2026-03-17'
        $nano.name | Should -Match 'secondaryAccountName'
        $nano.sku.name | Should -Be 'GlobalStandard'
        $nano.sku.capacity | Should -Be 10
        $arm.outputs.SecondaryChatDeploymentName.value | Should -Be 'bootcamp-chat-nano'
        $judge = $models | Where-Object { $_.name -match "'bootcamp-judge'" }
        $judge.properties.model.name | Should -Be 'gpt-5.4-nano'
        $judge.properties.model.version | Should -Be '2026-03-17'
        $judge.sku.capacity | Should -Be 10
        $arm.outputs.JudgeDeploymentName.value | Should -Be 'bootcamp-judge'
        foreach ($model in $models) {
            $model.properties.model.format | Should -Be 'OpenAI'
            $model.properties.versionUpgradeOption | Should -Be 'NoAutoUpgrade'
        }
        $arm.outputs.ChatDeploymentName.value | Should -Be 'bootcamp-chat'
        $arm.outputs.EmbeddingDeploymentName.value | Should -Be 'bootcamp-embedding'
    }

    It 'serializes Foundry project and model updates on the shared account' {
        $arm = (Get-CompiledCore).Arm
        $models = @($arm.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/deployments')
        $chat = $models | Where-Object { $_.properties.model.name -eq 'gpt-5.4-mini' }
        $embedding = $models | Where-Object { $_.properties.model.name -eq 'text-embedding-3-small' }
        $chat.dependsOn | Should -Contain "[resourceId('Microsoft.CognitiveServices/accounts/projects', variables('accountName'), variables('projectName'))]"
        $embedding.dependsOn | Should -Contain "[resourceId('Microsoft.CognitiveServices/accounts/deployments', variables('accountName'), 'bootcamp-chat')]"
        $nano = $models | Where-Object { $_.name -match 'secondaryAccountName' }
        $nano.dependsOn | Should -Contain "[resourceId('Microsoft.CognitiveServices/accounts/projects', variables('secondaryAccountName'), variables('projectName'))]"
        $judge = $models | Where-Object { $_.name -match "'bootcamp-judge'" }
        $judge.dependsOn | Should -Contain "[resourceId('Microsoft.CognitiveServices/accounts/deployments', variables('accountName'), 'bootcamp-embedding')]"
    }

    It 'hosts one scale-to-zero HTTPS MCP service and exposes it only in the primary Foundry Tools' {
        $arm = (Get-CompiledCore).Arm
        $apps = @($arm.resources | Where-Object type -eq 'Microsoft.App/containerApps')
        $apps.Count | Should -Be 1
        $app = $apps[0]
        $app.properties.configuration.ingress.external | Should -BeTrue
        $app.properties.configuration.ingress.allowInsecure | Should -BeFalse
        $app.properties.configuration.ingress.targetPort | Should -Be 8000
        $app.properties.template.scale.minReplicas | Should -Be 0
        $app.properties.template.scale.maxReplicas | Should -Be 1
        $container = $app.properties.template.containers[0]
        $container.resources.cpu | Should -Be "[json('0.25')]"
        $container.resources.memory | Should -Be '0.5Gi'
        @($container.probes | Where-Object { $_.httpGet.path -eq '/healthz' }).Count | Should -Be 3
        $container.args[0] | Should -Match 'set -e'
        ($arm.variables.Values -join "`n") | Should -Match 'mcp==1\.26\.0'
        $connection = @($arm.resources | Where-Object {
            $_.type -eq 'Microsoft.CognitiveServices/accounts/projects/connections' -and
            $_.properties.category -eq 'RemoteTool'
        })
        $connection.Count | Should -Be 1
        $connection[0].name | Should -Match "variables\('accountName'\)"
        $connection[0].name | Should -Not -Match 'secondaryAccountName'
        $connection[0].properties.authType | Should -Be 'None'
        $connection[0].properties.metadata.type | Should -Be 'generic_mcp'
        $connection[0].properties.target | Should -Match 'https://\{0\}/mcp'
        $connection[0].properties.target | Should -Match '\.configuration\.ingress\.fqdn'
        $connection[0].properties.Keys | Should -Not -Contain 'credentials'
        $arm.outputs.McpConnectionName.value | Should -Be 'bootcamp-date-time'
        $arm.outputs.McpServerUrl.value | Should -Match 'accounts/projects/connections.*bootcamp-date-time.*\.target'
        $environment = @($arm.resources | Where-Object type -eq 'Microsoft.App/managedEnvironments')
        $environment.Count | Should -Be 1
        $environment[0].properties.appLogsConfiguration.destination | Should -Be 'azure-monitor'
    }
}
