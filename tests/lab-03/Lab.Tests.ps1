BeforeAll {
    $script:Lab = Join-Path $PSScriptRoot '../../labs/03-evaluate/lab.ps1'
    $script:Endpoint = 'https://example.search.windows.net'
}

Describe 'Lab 03 participant path' {
    BeforeEach {
        $global:LASTEXITCODE = 0
        $global:lab03Test = @{
            requests = [System.Collections.Generic.List[object]]::new()
            index = $null
            docs = @{}
        }

        Mock az { 'test-token' }
        Mock Start-Sleep {}
        Mock Invoke-WebRequest {
            $path = [uri]::UnescapeDataString(([uri]$Uri).AbsolutePath)
            $global:lab03Test.requests.Add(@{ method = $Method; path = $path; headers = $Headers; body = $Body })
            $status = 200
            $payload = $null
            if ($path -match "^/indexes\('[^']+'\)$") {
                if ($Method -eq 'Get') {
                    if ($null -eq $global:lab03Test.index) { $status = 404 } else { $payload = $global:lab03Test.index }
                } elseif ($Headers['If-None-Match'] -ne '*' -or $null -ne $global:lab03Test.index) {
                    $status = 412
                } else {
                    $global:lab03Test.index = $Body | ConvertFrom-Json -AsHashtable
                    $payload = $global:lab03Test.index
                }
            } elseif ($path -match "/docs\('([^']+)'\)$") {
                $doc = $global:lab03Test.docs[$Matches[1]]
                if ($null -eq $doc) { $status = 404 } else { $payload = $doc }
            } elseif ($path -match '/docs/search\.index$') {
                $batch = $Body | ConvertFrom-Json -AsHashtable
                $payload = @{ value = @($batch.value | ForEach-Object {
                    $doc = @{} + $_
                    $doc.Remove('@search.action')
                    $global:lab03Test.docs[$doc.id] = $doc
                    @{ key = $doc.id; status = $true; statusCode = 201 }
                }) }
            } elseif ($path -match '/docs/\$count$') {
                $payload = $global:lab03Test.docs.Count
            } elseif ($path -match '/docs/search\.post\.search$') {
                $payload = @{ value = @(@{ id = 'support-policy-01'; '@search.score' = 1.5; title = 'Policy'; source = 'support-policy.txt'; content = 'On call' }) }
            } else { throw "Unexpected request $Method $Uri" }
            @{
                StatusCode = $status
                Content = if ($null -ne $payload) { ConvertTo-Json -InputObject $payload -Depth 100 -Compress } else { '' }
            }
        }
    }

    AfterEach { Remove-Variable lab03Test -Scope Global -ErrorAction Ignore }

    It 'creates the suffix index create-only and uploads every knowledge passage' {
        $output = & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc'

        $put = @($global:lab03Test.requests | Where-Object method -eq 'Put')
        $put.Count | Should -Be 1
        $put[0].path | Should -Be "/indexes('lab03-abc-support')"
        $put[0].headers['If-None-Match'] | Should -Be '*'
        $global:lab03Test.docs.Count | Should -Be 20
        @($global:lab03Test.docs.Values.source | Sort-Object -Unique) | Should -Be @(
            'KB-BIL-003_invoice-doesnt-match-plan-discrepancies-and-refunds.md'
            'KB-DEX-005_exporting-data-formats-limits-and-scheduling.md'
            'support-policy.txt')
        $global:lab03Test.docs['support-policy-01'].content | Should -Match '24/7'
        $output | Should -Match '20 knowledge passages \(20 added\)'
    }

    It 'never indexes the golden dataset' {
        & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc' | Out-Null

        $golden = Get-Content (Join-Path $PSScriptRoot '../../labs/03-evaluate/dataset/support-golden-v2.jsonl') |
            ForEach-Object { ($_ | ConvertFrom-Json).ground_truth }
        foreach ($doc in $global:lab03Test.docs.Values) {
            $doc.source | Should -Not -Match '\.jsonl$'
            $golden | Where-Object { $doc.content.Contains($_) } | Should -BeNullOrEmpty
        }
    }

    It 'reuses an identical index and passages without writing on rerun' {
        & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc' | Out-Null
        $global:lab03Test.requests.Clear()

        $output = & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc'

        @($global:lab03Test.requests | Where-Object method -in 'Put', 'Post') | Should -BeNullOrEmpty
        $output | Should -Match '\(0 added\)'
    }

    It 'stops without writing when an existing passage differs' {
        & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc' | Out-Null
        $global:lab03Test.docs['kb-dex-005-01'].content = 'changed by someone else'
        $global:lab03Test.requests.Clear()

        { & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc' } | Should -Throw '*kb-dex-005-01*choose another suffix*'
        @($global:lab03Test.requests | Where-Object method -in 'Put', 'Post') | Should -BeNullOrEmpty
    }

    It 'stops without writing when the existing index is incompatible' {
        $global:lab03Test.index = @{ name = 'lab03-abc-support'; fields = @(@{ name = 'id'; type = 'Edm.String'; key = $true }) }

        { & $script:Lab -Action Setup -SearchEndpoint $script:Endpoint -Suffix 'abc' } | Should -Throw '*incompatible*choose another suffix*'
        @($global:lab03Test.requests | Where-Object method -in 'Put', 'Post') | Should -BeNullOrEmpty
    }

    It 'searches the suffix index with a simple query' {
        $output = & $script:Lab -Action Search -SearchEndpoint $script:Endpoint -Suffix 'abc' -Question 'weekend urgent'

        $request = $global:lab03Test.requests | Where-Object path -match 'search\.post\.search$'
        $request.path | Should -Be "/indexes('lab03-abc-support')/docs/search.post.search"
        ($request.body | ConvertFrom-Json).queryType | Should -Be 'simple'
        ($output | ConvertFrom-Json).id | Should -Be 'support-policy-01'
    }

    It 'rejects a non-Search endpoint before requesting a token' {
        { & $script:Lab -Action Setup -SearchEndpoint 'https://example.com/' -Suffix 'abc' } | Should -Throw '*Azure Search service root URL*'
        Should -Invoke az -Times 0
    }

    It 'validates the shipped dataset without Azure' {
        $output = & $script:Lab -Action CheckDataset

        $output | Should -Be 'Valid: 8 rows (W1, W2, W3, W4, B1, B2, E1, E2).'
        Should -Invoke az -Times 0
    }

    It 'rejects a dataset with <Case>' -ForEach @(
        @{ Case = 'a duplicate id'; Lines = @('{"id":"A","query":"q","context":"c","ground_truth":"g"}', '{"id":"A","query":"q","context":"c","ground_truth":"g"}'); Message = "*repeats id 'A'*" }
        @{ Case = 'a missing field'; Lines = @('{"id":"A","query":"q","context":"c"}'); Message = "*ground_truth*" }
        @{ Case = 'invalid JSON'; Lines = @('{"id":'); Message = '*not valid JSON*' }
    ) {
        $path = Join-Path $TestDrive 'golden.jsonl'
        Set-Content -LiteralPath $path -Value $Lines

        { & $script:Lab -Action CheckDataset -DatasetPath $path } | Should -Throw $Message
    }
}
