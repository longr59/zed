[CmdletBinding()]
Param(
    [Parameter()][Alias('i')][switch]$Install,
    [Parameter()][Alias('h')][switch]$Help,
    [Parameter()][string]$Name
)

# https://stackoverflow.com/questions/57949031/powershell-script-stops-if-program-fails-like-bash-set-o-errexit
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$buildSuccess = $false

if ($Help) {
    Write-Output "Usage: test.ps1 [-Install] [-Help]"
    Write-Output "Build the installer for Windows.\n"
    Write-Output "Options:"
    Write-Output "  -Install, -i  Run the installer after building."
    Write-Output "  -Help, -h     Show this help message."
    exit 0
}

Push-Location -Path crates/zed
$channel = Get-Content "RELEASE_CHANNEL"
$env:ZED_RELEASE_CHANNEL = $channel
Pop-Location

function CheckEnviromentVariables {
    $requiredVars = @(
        'ZED_WORKSPACE', 'RELEASE_VERSION', 'ZED_RELEASE_CHANNEL', 
        'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
        'ACCOUNT_NAME', 'CERT_PROFILE_NAME', 'ENDPOINT',
        'FILE_DIGEST', 'TIMESTAMP_DIGEST', 'TIMESTAMP_SERVER'
    )
    
    foreach ($var in $requiredVars) {
        if (-not (Test-Path "env:$var")) {
            Write-Error "$var is not set"
            exit 1
        }
    }
}

function BuildZedAndItsFriends {
    Write-Output "Building Zed and its friends, for channel: $channel"
    # Build zed.exe and cli.exe
    cargo build --release --package zed --package cli
    Copy-Item -Path ".\target\release\zed.exe" -Destination ".\crates\zed\resources\windows\Zed.exe" -Force
    Copy-Item -Path ".\target\release\cli.exe" -Destination ".\crates\zed\resources\windows\cli.exe" -Force
    # Build explorer_command_injector.dll
    switch ($channel) {
        "stable" {
            cargo build --release --features stable --no-default-features --package explorer_command_injector
        }
        "preview" {
            cargo build --release --features preview --no-default-features --package explorer_command_injector
        }
        default {
            cargo build --release --package explorer_command_injector
        }
    }
    Copy-Item -Path ".\target\release\explorer_command_injector.dll" -Destination ".\crates\zed\resources\windows\zed_explorer_command_injector.dll" -Force
}

function MakeAppx {
    mkdir -p "$env:ZED_WORKSPACE\windows" -ErrorAction Ignore
    switch ($channel) {
        "stable" {
            $manifestFile = "$env:ZED_WORKSPACE\crates\explorer_command_injector\AppxManifest.xml"
        }
        "preview" {
            $manifestFile = "$env:ZED_WORKSPACE\crates\explorer_command_injector\AppxManifest-Preview.xml"
        }
        default {
            $manifestFile = "$env:ZED_WORKSPACE\crates\explorer_command_injector\AppxManifest-Nightly.xml"
        }
    }
    Copy-Item -Path "$manifestFile" -Destination "$env:ZED_WORKSPACE\windows\AppxManifest.xml"
    # Add makeAppx.exe to Path
    $sdk = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
    $env:Path += ';' + $sdk
    makeAppx.exe pack /d "$env:ZED_WORKSPACE\windows" /p "$env:ZED_WORKSPACE\crates\zed\resources\windows\zed_explorer_command_injector.appx" /nv
}

function SignZedAndItsFriends {
    $baseDir = "$env:ZED_WORKSPACE\crates\zed\resources\windows"
    $files = "$baseDir\Zed.exe,$baseDir\cli.exe,$baseDir\zed_explorer_command_injector.dll,$baseDir\zed_explorer_command_injector.appx"
    & "$baseDir\installer\sign.ps1" $files
}

function CollectFiles {
    $windowsDir = "$env:ZED_WORKSPACE\crates\zed\resources\windows"
    mkdir -p $windowsDir\installer\appx -ErrorAction Ignore
    Move-Item -Path "$windowsDir\zed_explorer_command_injector.appx" -Destination "$windowsDir\installer\appx\zed_explorer_command_injector.appx" -Force
    Move-Item -Path "$windowsDir\zed_explorer_command_injector.dll" -Destination "$windowsDir\installer\appx\zed_explorer_command_injector.dll" -Force
    mkdir -p "$windowsDir\installer\bin" -ErrorAction Ignore
    Move-Item -Path "$windowsDir\cli.exe" -Destination "$windowsDir\installer\bin\zed.exe" -Force
}

function BuildInstaller {
    $issFilePath = "$env:ZED_WORKSPACE/crates/zed/resources/windows/installer/zed.iss"
    switch ($channel) {
        "stable" {
            $appId = "{{2DB0DA96-CA55-49BB-AF4F-64AF36A86712}"
            $appName = "Zed Editor"
            $appDisplayName = "Zed Editor (User)"
            $appSetupName = "ZedEditorUserSetup-x64-$env:RELEASE_VERSION"
            # The mutex name here should match the mutex name in crates\zed\src\zed\windows_only_instance.rs
            $appMutex = "Zed-Editor-Stable-Instance-Mutex"
            $appExeName = "Zed"
            $regValueName = "ZedEditor"
            $appUserId = "ZedIndustries.Zed"
            $appShellNameShort = "Z&ed Editor"
            # TODO: Update this value
            $appAppxFullName = "ZedIndustries.Zed_1.0.0.0_neutral__jr6ek54py7bac"
        }
        "preview" {
            $appId = "{{F70E4811-D0E2-4D88-AC99-D63752799F95}"
            $appName = "Zed Editor Preview"
            $appDisplayName = "Zed Editor Preview (User)"
            $appSetupName = "ZedEditorUserSetup-x64-$env:RELEASE_VERSION-preview"
            # The mutex name here should match the mutex name in crates\zed\src\zed\windows_only_instance.rs
            $appMutex = "Zed-Editor-Preview-Instance-Mutex"
            $appExeName = "Zed"
            $regValueName = "ZedEditorPreview"
            $appUserId = "ZedIndustries.Zed.Preview"
            $appShellNameShort = "Z&ed Editor Preview"
            # TODO: Update this value
            $appAppxFullName = "ZedIndustries.Zed.Preview_1.0.0.0_neutral__jr6ek54py7bac"
        }
        "nightly" {
            $appId = "{{1BDB21D3-14E7-433C-843C-9C97382B2FE0}"
            $appName = "Zed Editor Nightly"
            $appDisplayName = "Zed Editor Nightly (User)"
            $appSetupName = "ZedEditorUserSetup-x64-$env:RELEASE_VERSION-nightly"
            # The mutex name here should match the mutex name in crates\zed\src\zed\windows_only_instance.rs
            $appMutex = "Zed-Editor-Nightly-Instance-Mutex"
            $appExeName = "Zed"
            $regValueName = "ZedEditorNightly"
            $appUserId = "ZedIndustries.Zed.Nightly"
            $appShellNameShort = "Z&ed Editor Nightly"
            # TODO: Update this value
            $appAppxFullName = "ZedIndustries.Zed.Nightly_1.0.0.0_neutral__jr6ek54py7bac"
        }
        default {
            Write-Error "can't bundle installer for $channel."
            exit 1
        }
    }

    # Windows runner 2022 default has iscc in PATH, https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md
    # Currently, we are using Windows 2022 runner.
    # Windows runner 2025 doesn't have iscc in PATH for now, https://github.com/actions/runner-images/issues/11228
    # $innoSetupPath = "iscc.exe"
    $innoSetupPath = "C:\zjk\apps\Inno Setup 6\ISCC.exe"

    $definitions = @{
        "AppId"          = $appId
        "OutputDir"      = "$env:ZED_WORKSPACE/target"
        "AppSetupName"   = $appSetupName
        "AppName"        = $appName
        "AppDisplayName" = $appDisplayName
        "RegValueName"   = $regValueName
        "AppMutex"       = $appMutex
        "AppExeName"     = $appExeName
        "ResourcesDir"   = "$env:ZED_WORKSPACE/crates/zed/resources/windows"
        "ShellNameShort" = $appShellNameShort
        "AppUserId"      = $appUserId
        "Version"        = "$env:RELEASE_VERSION"
        "SourceDir"      = "$env:ZED_WORKSPACE"
        "AppxFullName"   = $appAppxFullName
    }

    $signTool = "pwsh.exe -ExecutionPolicy Bypass -File $env:ZED_WORKSPACE/crates/zed/resources/windows/installer/sign.ps1 `$f"

    $defs = @()
    foreach ($key in $definitions.Keys) {
        $defs += "/d$key=`"$($definitions[$key])`""
    }

    $innoArgs = @($issFilePath) + $innoFilePath + $defs + "/sDefaultsign=`"$signTool`""

    # Execute Inno Setup
    Write-Host "🚀 Running Inno Setup: $innoSetupPath $innoArgs"
    $process = Start-Process -FilePath $innoSetupPath -ArgumentList $innoArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "✅ Inno Setup successfully compiled the installer"
        # Write-Output "SETUP_PATH=target/$appSetupName.exe" >> $env:GITHUB_ENV
        $script:buildSuccess = $true
    }
    else {
        Write-Host "❌ Inno Setup failed: $($process.ExitCode)"
        $script:buildSuccess = $false
    }
}

CheckEnviromentVariables
BuildZedAndItsFriends
MakeAppx
SignZedAndItsFriends
CollectFiles
BuildInstaller

# TODO: upload_to_blob_store

if ($buildSuccess) {
    Write-Output "Build successful"
    if ($Install) {
        Write-Output "Installing Zed..."
        Start-Process -FilePath "$env:ZED_WORKSPACE/target/ZedEditorUserSetup-x64-$env:RELEASE_VERSION.exe"
    }
    exit 0
}
else {
    Write-Output "Build failed"
    exit 1
}
