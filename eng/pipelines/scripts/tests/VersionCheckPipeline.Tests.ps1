# Licensed to the .NET Foundation under one or more agreements.
# The .NET Foundation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $stepPath = '/eng/pipelines/common/steps/test-family-versions.yml@self'
}

Describe 'Family-version pipeline wiring' -Tag 'Pipeline' {
    It '<Path> runs the shared suite after installing the SDK and restoring tools' -ForEach @(
        @{ Path = 'eng/pipelines/pr/jobs/test-logging-job.yml' }
        @{ Path = 'eng/pipelines/onebranch/jobs/validate-packages-job.yml' }
    ) {
        # Arrange: inspect the actual callers, not a duplicated list in a test fixture.
        $content = Get-Content -LiteralPath (Join-Path $repoRoot $Path) -Raw
        $restoreIndex = $content.IndexOf('/eng/pipelines/common/steps/restore-dotnet-tools.yml@self')
        $installIndex = $content.IndexOf('/eng/pipelines/common/steps/install-dotnet.yml@self')
        $suiteIndex = $content.IndexOf($stepPath)

        $installIndex | Should -BeGreaterOrEqual 0
        $restoreIndex | Should -BeGreaterThan $installIndex
        $suiteIndex | Should -BeGreaterThan $restoreIndex
        [regex]::Matches($content, [regex]::Escape($stepPath)).Count | Should -Be 1
        $content | Should -Match 'testResultsPath:'
    }

    It 'adds dedicated Logging jobs to the modern PR test platforms' {
        $content = Get-Content (Join-Path $repoRoot 'eng/pipelines/pr/stages/test-stages.yml') -Raw
        $content | Should -Match ('(?m)^          - \$\{\{ if not\(contains\(platform\.dotnet, ''net4''\)\) \}\}:\r?\n' +
            '            - template: /eng/pipelines/pr/jobs/test-logging-job\.yml@self')
        $content | Should -Match 'platformDisplayName: \$\{\{ platform\.displayName \}\}'
        $content | Should -Match 'poolImage: \$\{\{ platform\.image \}\}'
    }

    It 'keeps regression fixtures out of production build and pack jobs' -ForEach @(
        @{ Path = 'eng/pipelines/pr/stages/pack-stage.yml' }
        @{ Path = 'eng/pipelines/onebranch/jobs/build-buildproj-job.yml' }
    ) {
        $content = Get-Content (Join-Path $repoRoot $Path) -Raw
        $content | Should -Not -Match ([regex]::Escape($stepPath))
    }

    It 'uses the pinned local PowerShell tool for prerequisites and tests' {
        $content = Get-Content (Join-Path $repoRoot 'eng/pipelines/common/steps/test-family-versions.yml') -Raw
        [regex]::Matches($content, 'dotnet tool run pwsh').Count | Should -Be 2
        $content | Should -Match 'Install-Module Pester -RequiredVersion 5\.7\.1'
        $content | Should -Match 'Invoke-Pester -Configuration \$configuration'
        $content | Should -Match '\$configuration\.Run\.Exit = \$true'
        $content | Should -Match '\$configuration\.TestDrive\.Enabled = \$false'
        $content | Should -Match '\$configuration\.TestResult\.OutputFormat = ''NUnitXml'''
        $content | Should -Match 'VersionChecks\.Tests\.ps1'
        $content | Should -Match 'VersionCheckPipeline\.Tests\.ps1'
        $content | Should -Not -Match 'RunVersionChecks\.ps1'
        $content | Should -Not -Match 'continueOnError: true'
    }

    It 'publishes PR Logging result artifacts with unique job/attempt names' {
        $content = Get-Content (Join-Path $repoRoot 'eng/pipelines/pr/jobs/test-logging-job.yml') -Raw
        $content | Should -Match 'PublishPipelineArtifact@1'
        $content | Should -Match '\$\(System\.JobId\)_attempt\$\(System\.JobAttempt\)'
        $content | Should -Match 'condition: succeededOrFailed\(\)'
        $content | Should -Match '\$\{\{ parameters\.platformDisplayName \}\}_logging'
    }

    It 'publishes NUnit results even on test failure and gates missing or failed results' {
        $content = Get-Content (Join-Path $repoRoot 'eng/pipelines/common/steps/test-family-versions.yml') -Raw
        $content | Should -Match 'PublishTestResults@2'
        $content | Should -Match 'condition: succeededOrFailed\(\)'
        $content | Should -Match 'testResultsFormat: NUnit'
        $content | Should -Match 'failTaskOnFailedTests: true'
        $content | Should -Match 'failTaskOnMissingResultsFile: true'
    }
}
