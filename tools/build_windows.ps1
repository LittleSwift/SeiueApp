param(
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') {
    throw 'Windows builds require Windows with Visual Studio Desktop development with C++ installed.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    $localFlutter = Join-Path $projectRoot '.tools/flutter/bin/flutter.bat'
    if ($null -ne $flutterCommand) {
        $flutterExe = $flutterCommand.Source
    } elseif (Test-Path $localFlutter) {
        $flutterExe = $localFlutter
    } else {
        throw 'Install Flutter 3.47.7 and add flutter/bin to PATH.'
    }
    function Invoke-Flutter {
        & $flutterExe @args
        if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $args" }
    }

    # Bootstrap the tool before parsing its machine-readable version output.
    Invoke-Flutter --version
    $sdkOutput = & $flutterExe --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Flutter SDK version.' }
    $sdk = $sdkOutput | ConvertFrom-Json
    if ($sdk.frameworkVersion -eq '0.0.0-unknown' -or $sdk.frameworkVersion -notmatch '^\d+\.\d+\.\d+') {
        throw 'Flutter SDK version is unknown. Check out the official release tag, not an untagged shallow commit.'
    }

    Invoke-Flutter pub get --enforce-lockfile
    if (-not $SkipChecks) {
        Invoke-Flutter analyze --no-pub
        Invoke-Flutter test --no-pub
    }
    # Flutter selects the Windows target architecture from the host runner.
    Invoke-Flutter build windows --release --no-pub

    $release = Join-Path $projectRoot 'build/windows/x64/runner/Release'
    if (-not (Test-Path (Join-Path $release 'Seiue.exe'))) {
        throw 'Seiue.exe was not produced by the Windows build.'
    }
    $versionMatch = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^\s+]+)'
    $version = $versionMatch.Matches[0].Groups[1].Value
    $destination = Join-Path $projectRoot "dist/Seiue-Windows-$version-x64"
    if (Test-Path $destination) { Remove-Item -Recurse -Force $destination }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem $release | Where-Object { $_.Extension -ne '.pdb' } |
        Copy-Item -Destination $destination -Recurse -Force
    # Include the redistributable CRT from the installed Visual Studio toolchain.
    # All Flutter/plugin DLLs and data/ remain beside the executable.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio vswhere.exe was not found.' }
    $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vsRoot)) {
        throw 'The Visual C++ toolchain was not found.'
    }
    # A wildcard in a parent path combined with -Filter can filter out the
    # x64 parent itself in PowerShell. Enumerate actual CRT directories instead.
    $redistRoot = Join-Path $vsRoot 'VC/Redist/MSVC'
    $crt = Get-ChildItem -LiteralPath $redistRoot -Directory -Recurse -Filter 'Microsoft.VC*.CRT' |
        Where-Object { $_.Parent.Name -eq 'x64' } |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $crt) { throw 'Visual C++ redistributable DLLs were not found.' }
    Copy-Item (Join-Path $crt.FullName '*.dll') $destination -Force
    foreach ($runtime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path (Join-Path $destination $runtime))) {
            throw "Required Visual C++ runtime is missing from the portable bundle: $runtime"
        }
    }

    $zip = "$destination.zip"
    Compress-Archive -Path $destination -DestinationPath $zip -Force
    Write-Host "Built: $zip"
} finally {
    Pop-Location
}
