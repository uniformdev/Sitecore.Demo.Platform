##########################################################################
# This is the Cake bootstrapper script for PowerShell.
# This file was downloaded from https://github.com/cake-build/resources
# Feel free to change this file to fit your needs.
##########################################################################

<#

.SYNOPSIS
This is a Powershell script to bootstrap a Cake build.

.DESCRIPTION
This Powershell script will download NuGet if missing, restore NuGet tools (including Cake)
and execute your Cake build script with the parameters you provide.

.PARAMETER Script
The build script to execute.
.PARAMETER Target
The build script target to run.
.PARAMETER Configuration
The build configuration to use.
.PARAMETER Verbosity
Specifies the amount of information to be displayed.
.PARAMETER ShowDescription
Shows description about tasks.
.PARAMETER DryRun
Performs a dry run.
.PARAMETER SkipToolPackageRestore
Skips restoring of packages.
.PARAMETER ScriptArgs
Remaining arguments are added here.

.LINK
https://cakebuild.net

#>

[CmdletBinding()]
Param(
    [string]$Script = "build.cake",
    [string]$Target,
    [string]$Configuration,
    [ValidateSet("Quiet", "Minimal", "Normal", "Verbose", "Diagnostic")]
    [string]$Verbosity,
    [switch]$ShowDescription,
    [Alias("WhatIf", "Noop")]
    [switch]$DryRun,
    [switch]$SkipToolPackageRestore,
    [Parameter(Position = 0, Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs,
    [ValidateSet("IIS", "Docker", "DockerBuild")]
    [string]$DeploymentTarget,
    [switch]$PreRelease
)

# Check if PowerShell is running in Admministrative mode and exit if not:

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
    Break
}
# Attempt to set highest encryption available for SecurityProtocol.
# PowerShell will not set this by default (until maybe .NET 4.6.x). This
# will typically produce a message for PowerShell v2 (just an info
# message though)
try {
    # Set TLS 1.2 (3072), then TLS 1.1 (768), then TLS 1.0 (192), finally SSL 3.0 (48)
    # Use integers because the enumeration values for TLS 1.2 and TLS 1.1 won't
    # exist in .NET 4.0, even though they are addressable if .NET 4.5+ is
    # installed (.NET 4.5 is an in-place upgrade).
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192 -bor 48
}
catch {
    Write-Output 'Unable to set PowerShell to use TLS 1.2 and TLS 1.1 due to old .NET Framework installed. If you see underlying connection closed or trust errors, you may need to upgrade to .NET Framework 4.5+ and PowerShell v3'
}

[Reflection.Assembly]::LoadWithPartialName("System.Security") | Out-Null
function MD5HashFile([string] $filePath) {
    if ([string]::IsNullOrEmpty($filePath) -or !(Test-Path $filePath -PathType Leaf)) {
        return $null
    }

    [System.IO.Stream] $file = $null;
    [System.Security.Cryptography.MD5] $md5 = $null;
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $file = [System.IO.File]::OpenRead($filePath)
        return [System.BitConverter]::ToString($md5.ComputeHash($file))
    }
    finally {
        if ($null -ne $file) {
            $file.Dispose()
        }
    }
}

function GetProxyEnabledWebClient {
    $wc = New-Object System.Net.WebClient
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $wc.Proxy = $proxy
    return $wc
}

Write-Host "Preparing to run build script..."

if (!$PSScriptRoot) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$TOOLS_DIR = Join-Path $PSScriptRoot "tools"
$ADDINS_DIR = Join-Path $TOOLS_DIR "Addins"
$MODULES_DIR = Join-Path $TOOLS_DIR "Modules"
$NUGET_EXE = Join-Path $TOOLS_DIR "nuget.exe"
$CAKE_EXE = Join-Path $TOOLS_DIR "Cake/Cake.exe"
$NUGET_URL = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$PACKAGES_CONFIG = Join-Path $TOOLS_DIR "packages.config"
$PACKAGES_CONFIG_MD5 = Join-Path $TOOLS_DIR "packages.config.md5sum"
$ADDINS_PACKAGES_CONFIG = Join-Path $ADDINS_DIR "packages.config"
$MODULES_PACKAGES_CONFIG = Join-Path $MODULES_DIR "packages.config"

# Make sure tools folder exists
if ((Test-Path $PSScriptRoot) -and !(Test-Path $TOOLS_DIR)) {
    Write-Verbose -Message "Creating tools directory..."
    New-Item -Path $TOOLS_DIR -Type directory | out-null
}

# Try find NuGet.exe in path if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Trying to find nuget.exe in PATH..."
    $existingPaths = $Env:Path -Split ';' | Where-Object { (![string]::IsNullOrEmpty($_)) -and (Test-Path $_ -PathType Container) }
    $NUGET_EXE_IN_PATH = Get-ChildItem -Path $existingPaths -Filter "nuget.exe" | Select-Object -First 1
    if ($null -ne $NUGET_EXE_IN_PATH -and (Test-Path $NUGET_EXE_IN_PATH.FullName)) {
        Write-Verbose -Message "Found in PATH at $($NUGET_EXE_IN_PATH.FullName)."
        $NUGET_EXE = $NUGET_EXE_IN_PATH.FullName
    }
}

# Try download NuGet.exe if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Downloading NuGet.exe..."
    try {
        $wc = GetProxyEnabledWebClient
        $wc.DownloadFile($NUGET_URL, $NUGET_EXE)
    }
    catch {
        Throw "Could not download NuGet.exe."
    }
}

# Save nuget.exe path to environment to be available to child processed
$ENV:NUGET_EXE = $NUGET_EXE

# Restore tools from NuGet?
if (-Not $SkipToolPackageRestore.IsPresent) {
    Push-Location
    Set-Location $TOOLS_DIR

    # Check for changes in packages.config and remove installed tools if true.
    [string] $md5Hash = MD5HashFile($PACKAGES_CONFIG)
    if ((!(Test-Path $PACKAGES_CONFIG_MD5)) -Or
        ($md5Hash -ne (Get-Content $PACKAGES_CONFIG_MD5 ))) {
        Write-Verbose -Message "Missing or changed package.config hash..."
        Get-ChildItem -Exclude packages.config, nuget.exe, Cake.Bakery |
        Remove-Item -Recurse
    }

    Write-Verbose -Message "Restoring tools from NuGet..."
    $NuGetOutput = Invoke-Expression "&`"$NUGET_EXE`" install -ExcludeVersion -OutputDirectory `"$TOOLS_DIR`""

    if ($LASTEXITCODE -ne 0) {
        Throw "An error occurred while restoring NuGet tools."
    }
    else {
        $md5Hash | Out-File $PACKAGES_CONFIG_MD5 -Encoding "ASCII"
    }
    Write-Verbose -Message ($NuGetOutput | out-string)

    Pop-Location
}

# Automatically add additional NuGet source to local feed at build time. Requires environment variables.

$accessToken = (& { if ([string]::IsNullOrEmpty("$env:INTERNAL_NUGET_SOURCE_PASSWORD")) { "$env:SYSTEM_ACCESSTOKEN" } else { "$env:INTERNAL_NUGET_SOURCE_PASSWORD" } })
$internalFeed = $env:INTERNAL_NUGET_SOURCE
$userName = $env:INTERNAL_NUGET_SOURCE_USERNAME
if ($accessToken -and $internalFeed -and $userName -and $PreRelease) {
    & "$NUGET_EXE" sources add -name "sc-internal-package-feed" -source $internalFeed -username $userName -password $accessToken -ConfigFile (Join-Path $PWD nuget.config) -StorePasswordInClearText | Out-Null
    & "$NUGET_EXE" sources update -name "sc-internal-package-feed" -source $internalFeed -username $userName -password $accessToken -ConfigFile (Join-Path $PWD nuget.config) -StorePasswordInClearText
}

# Restore addins from NuGet
if (Test-Path $ADDINS_PACKAGES_CONFIG) {
    Push-Location
    Set-Location $ADDINS_DIR

    Write-Verbose -Message "Restoring addins from NuGet..."
    $NuGetOutput = Invoke-Expression "&`"$NUGET_EXE`" install -ExcludeVersion -OutputDirectory `"$ADDINS_DIR`""

    if ($LASTEXITCODE -ne 0) {
        Throw "An error occurred while restoring NuGet addins."
    }

    Write-Verbose -Message ($NuGetOutput | out-string)

    Pop-Location
}

# Restore modules from NuGet
if (Test-Path $MODULES_PACKAGES_CONFIG) {
    Push-Location
    Set-Location $MODULES_DIR

    Write-Verbose -Message "Restoring modules from NuGet..."
    $NuGetOutput = Invoke-Expression "&`"$NUGET_EXE`" install -ExcludeVersion -OutputDirectory `"$MODULES_DIR`""

    if ($LASTEXITCODE -ne 0) {
        Throw "An error occurred while restoring NuGet modules."
    }

    Write-Verbose -Message ($NuGetOutput | out-string)

    Pop-Location
}

# Make sure that Cake has been installed.
if (!(Test-Path $CAKE_EXE)) {
    Throw "Could not find Cake.exe at $CAKE_EXE"
}

# Build Cake arguments
$cakeArguments = @("$Script");
if ($Target) { $cakeArguments += "-target=$Target" }
if ($DeploymentTarget) { $cakeArguments += "-deploymentTarget=$DeploymentTarget" }
if ($Configuration) { $cakeArguments += "-configuration=$Configuration" }
if ($Verbosity) { $cakeArguments += "-verbosity=$Verbosity" }
if ($ShowDescription) { $cakeArguments += "-showdescription" }
if ($DryRun) { $cakeArguments += "-dryrun" }
$cakeArguments += $ScriptArgs

# Start Cake
Write-Host "Running build script..."
&$CAKE_EXE $cakeArguments
exit $LASTEXITCODE
