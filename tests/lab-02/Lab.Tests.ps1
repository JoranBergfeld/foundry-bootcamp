BeforeAll {
    $script:Lab = Join-Path $PSScriptRoot '../../labs/02-build-advanced/lab.ps1'
}

Describe 'Lab 02 participant path' {
    BeforeEach {
        $global:LASTEXITCODE = 0
        $global:lab02Test = @{
            requests = [System.Collections.Generic.List[object]]::new()
            source = $null
            kb = $null
            conflict = $false
            index = @{
            name = 'baseline'
            '@odata.etag' = '"original"'
            fields = @('ticket_id', 'initial_message', 'agent_first_reply', 'resolution_summary' |
                ForEach-Object { @{ name = $_; searchable = $true; retrievable = $true } })
            semantic = @{
                defaultConfiguration = 'participant-default'
                configurations = @(@{ name = 'participant-default'; prioritizedFields = @{ prioritizedContentFields = @(@{ fieldName = 'initial_message' }) } })
            }
            customProperty = 'retained'
            }
        }

        Mock az { 'test-token' }
        Mock Invoke-WebRequest {
            $path = ([uri]$Uri).AbsolutePath
            $global:lab02Test.requests.Add(@{ method = $Method; path = $path; headers = $Headers; body = $Body })
            $status = 200
            $payload = $null
            if ($path -match '^/indexes') {
                if ($Method -eq 'Get') {
                    $payload = $global:lab02Test.index
                } else {
                    if ($global:lab02Test.conflict -or $Headers['If-Match'] -ne $global:lab02Test.index['@odata.etag']) {
                        $status = 412
                    } else {
                        $global:lab02Test.index = $Body | ConvertFrom-Json -AsHashtable
                        $global:lab02Test.index['@odata.etag'] = '"updated"'
                        $payload = $global:lab02Test.index
                    }
                }
            } elseif ($path -match '^/knowledgesources') {
                if ($Method -eq 'Get') {
                    if ($null -eq $global:lab02Test.source) { $status = 404 } else { $payload = $global:lab02Test.source }
                } elseif ($Headers['If-None-Match'] -ne '*' -or $null -ne $global:lab02Test.source) {
                    $status = 412
                } else {
                    $global:lab02Test.source = $Body | ConvertFrom-Json -AsHashtable
                    $payload = $global:lab02Test.source
                }
            } elseif ($path -match '/retrieve$') {
                $payload = @{ response = @(@{ content = @(@{ text = 'ticket evidence' }) }); references = @(@{ id = 1 }) }
            } elseif ($path -match '^/knowledgebases') {
                if ($Method -eq 'Get') {
                    if ($null -eq $global:lab02Test.kb) { $status = 404 } else { $payload = $global:lab02Test.kb }
                } elseif ($Headers['If-None-Match'] -ne '*' -or $null -ne $global:lab02Test.kb) {
                    $status = 412
                } else {
                    $global:lab02Test.kb = $Body | ConvertFrom-Json -AsHashtable
                    $payload = $global:lab02Test.kb
                }
            } else { throw "Unexpected request $Method $Uri" }
            @{
                StatusCode = $status
                Content = if ($null -ne $payload) { ConvertTo-Json -InputObject $payload -Depth 100 -Compress } else { '' }
            }
        }
    }

    It 'sets up and safely reruns without replacing existing participant resources' {
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        $global:lab02Test.index.semantic.defaultConfiguration | Should -Be 'participant-default'
        $global:lab02Test.index.customProperty | Should -Be 'retained'
        @($global:lab02Test.index.semantic.configurations).Count | Should -Be 2
        $global:lab02Test.source.searchIndexParameters.searchIndexName | Should -Be 'baseline'
        @($global:lab02Test.source.searchIndexParameters.sourceDataFields.name) | Should -Be @('ticket_id', 'initial_message', 'agent_first_reply', 'resolution_summary')
        $global:lab02Test.kb.retrievalReasoningEffort.kind | Should -Be 'minimal'
        $writes = @($global:lab02Test.requests | Where-Object method -eq 'Put').Count
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be $writes
    }

    It 'stops on an index concurrent update before creating other resources' {
        $global:lab02Test.conflict = $true
        { & $script:Lab Setup 'https://example.search.windows.net' baseline abc } | Should -Throw '*HTTP 412*'
        $global:lab02Test.source | Should -BeNullOrEmpty
        $global:lab02Test.kb | Should -BeNullOrEmpty
    }

    It 'adds a semantic configuration when the baseline has none' {
        $global:lab02Test.index.semantic = $null
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        $global:lab02Test.index.semantic.configurations[0].name | Should -Be 'lab02-abc-semantic'
        $global:lab02Test.index.semantic.defaultConfiguration | Should -BeNullOrEmpty
    }

    It 'refuses to update an index without an ETag' {
        $global:lab02Test.index.Remove('@odata.etag')
        { & $script:Lab Setup 'https://example.search.windows.net' baseline abc } | Should -Throw '*ETag*'
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be 0
    }

    It 'does not overwrite a conflicting source on rerun' {
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        $global:lab02Test.source.searchIndexParameters.searchIndexName = 'other'
        $writes = @($global:lab02Test.requests | Where-Object method -eq 'Put').Count
        { & $script:Lab Setup 'https://example.search.windows.net' baseline abc } | Should -Throw '*differs*'
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be $writes
    }

    It 'does not reuse or overwrite a source with restricted search fields' {
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        $global:lab02Test.source.searchIndexParameters.searchFields = @(@{ name = 'initial_message' })
        $writes = @($global:lab02Test.requests | Where-Object method -eq 'Put').Count
        { & $script:Lab Setup 'https://example.search.windows.net' baseline abc } | Should -Throw '*differs*'
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be $writes
        $global:lab02Test.source.searchIndexParameters.searchFields[0].name | Should -Be 'initial_message'
        $global:lab02Test.source.searchIndexParameters.searchFields = @(
            @{ name = 'initial_message' }, @{ name = 'resolution_summary' }
        )
        { & $script:Lab Setup 'https://example.search.windows.net' baseline abc } | Should -Throw '*differs*'
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be $writes
    }

    It 'reuses a source with <Description> search fields' -ForEach @(
        @{ Description = 'null'; Value = $null }
        @{ Description = 'empty'; Value = @() }
        @{ Description = 'wildcard'; Value = @(@{ name = '*' }) }
    ) {
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc
        $global:lab02Test.source.searchIndexParameters.searchFields = $Value
        $writes = @($global:lab02Test.requests | Where-Object method -eq 'Put').Count
        & $script:Lab Setup 'https://example.search.windows.net' baseline abc | Should -Match '^Ready:'
        @($global:lab02Test.requests | Where-Object method -eq 'Put').Count | Should -Be $writes
    }

    It 'requests extractive retrieval with evidence and references' {
        $result = & $script:Lab Retrieve 'https://example.search.windows.net' baseline abc -Question 'How was login fixed?' | ConvertFrom-Json
        $request = ($global:lab02Test.requests | Where-Object method -eq 'Post').body | ConvertFrom-Json
        $request.intents[0].search | Should -Be 'How was login fixed?'
        $request.retrievalReasoningEffort.kind | Should -Be 'minimal'
        $request.knowledgeSourceParams[0].includeReferenceSourceData | Should -BeTrue
        $request.knowledgeSourceParams[0].failOnError | Should -BeTrue
        $result.references[0].id | Should -Be 1
    }

    It 'rejects non-Search endpoints before obtaining a token' {
        { & $script:Lab Setup 'https://example.com' baseline abc } | Should -Throw '*Azure Search*'
        Should -Invoke az -Times 0
    }
}
