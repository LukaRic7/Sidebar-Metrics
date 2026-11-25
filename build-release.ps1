param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist\SidebarMetrics'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot $OutputDirectory
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$compiler = Join-Path $env:ProgramFiles 'AutoHotkey\Compiler\Ahk2Exe.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compilerCommand = Get-Command Ahk2Exe.exe -ErrorAction SilentlyContinue
    if ($compilerCommand) {
        $compiler = $compilerCommand.Source
    } else {
        throw 'Ahk2Exe.exe was not found. Install AutoHotkey v2 with the compiler component.'
    }
}

$baseInterpreter = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $baseInterpreter)) {
    throw "AutoHotkey v2 64-bit base file was not found: $baseInterpreter"
}

$serviceProject = Join-Path $repositoryRoot 'HardwareMonitor.Service\HardwareMonitor.Service.csproj'
$mainScript = Join-Path $repositoryRoot 'UserInterface\main.ahk'
$sourceAssets = Join-Path $repositoryRoot 'UserInterface\assets'
$daemonOutput = Join-Path $OutputDirectory 'HardwareMonitor.Service'
$assetsOutput = Join-Path $OutputDirectory 'assets'
$uiExecutable = Join-Path $OutputDirectory 'SidebarMetrics.exe'

if (-not (Test-Path -LiteralPath $sourceAssets -PathType Container)) {
    throw "The UI assets directory was not found: $sourceAssets"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory, $daemonOutput, $assetsOutput | Out-Null

$publishArguments = @(
    'publish',
    $serviceProject,
    '--configuration', 'Release',
    '--runtime', 'win-x64',
    '--self-contained', 'true',
    '--output', $daemonOutput
)
& dotnet @publishArguments
if ($LASTEXITCODE -ne 0) {
    throw "Daemon publish failed with exit code $LASTEXITCODE."
}

& $compiler '/in' $mainScript '/out' $uiExecutable '/base' $baseInterpreter
if ($LASTEXITCODE -ne 0) {
    throw "AHK compilation failed with exit code $LASTEXITCODE."
}

Copy-Item -Path (Join-Path $sourceAssets '*') -Destination $assetsOutput -Recurse -Force

Write-Output "Release output: $OutputDirectory"
Write-Output "Start: $uiExecutable"
