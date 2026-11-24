<#
.SYNOPSIS
    Fail-fast automated quality gate & universal multi-ABI build script for Flutter/Dart projects.
.DESCRIPTION
    Executes the complete post-edit verification pipeline:
      1. Auto-format (`dart format lib test`) + strict diff check (`--set-exit-if-changed`)
      2. Strict static analysis (`flutter analyze --fatal-infos`)
      3. Full automated test suite (`flutter test`)
      4. Universal multi-ABI debug or release APK build (`android-arm,android-arm64,android-x64`)
      5. Optional safe in-place ADB install (`-InstallDevice <serial>`, NEVER wipes app data)
.EXAMPLE
    .\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1
.EXAMPLE
    .\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1 -InstallDevice emulator-5554
.EXAMPLE
    .\.agents\skills\full-stack-verify-and-visual-qa\scripts\verify_flutter.ps1 -SkipBuild
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$Release,
    [string]$InstallDevice = ''
)

$ErrorActionPreference = 'Stop'

function Invoke-GateStep {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    Write-Host "`n==> $Title" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $Title (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "PASSED: $Title" -ForegroundColor Green
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Invoke-GateStep -Title '1/4 Dart Format (apply + strict verification)' -Action {
    dart format lib test
    if ($LASTEXITCODE -ne 0) { return }
    dart format --output=none --set-exit-if-changed lib test
}

Invoke-GateStep -Title '2/4 Flutter Static Analysis (--fatal-infos)' -Action {
    flutter analyze --fatal-infos
}

Invoke-GateStep -Title '3/4 Full Flutter Automated Test Suite' -Action {
    flutter test
}

if (-not $SkipBuild) {
    $buildMode = if ($Release) { '--release' } else { '--debug' }
    $apkPath = if ($Release) {
        'build\app\outputs\flutter-apk\app-release.apk'
    } else {
        'build\app\outputs\flutter-apk\app-debug.apk'
    }

    Invoke-GateStep -Title "4/4 Universal Multi-ABI APK Build ($buildMode)" -Action {
        flutter build apk $buildMode --target-platform android-arm,android-arm64,android-x64
    }

    if ($InstallDevice -ne '') {
        Invoke-GateStep -Title "ADB Safe In-Place Install ($InstallDevice)" -Action {
            adb -s $InstallDevice install -r $apkPath
        }
    }
} else {
    Write-Host "`n==> 4/4 APK Build skipped (-SkipBuild)" -ForegroundColor Yellow
}

$sw.Stop()
Write-Host "`nALL QUALITY GATES PASSED in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s." -ForegroundColor Green
