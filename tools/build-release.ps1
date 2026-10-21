# build-release.ps1 - builds the friend zip: release\ChainedTeams-v<version>.zip
# 1) downloads RE-UE4SS (experimental-latest) from its official GitHub release (first run only)
# 2) builds ChainedTeams.exe with the C# compiler that ships with Windows
# 3) copies the mod in and zips everything
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$launcher = Join-Path $root "launcher"
$ue4ss = Join-Path $launcher "ue4ss"

if (-not (Test-Path (Join-Path $ue4ss "UE4SS.dll"))) {
    Write-Host "Downloading RE-UE4SS..."
    $rel = Invoke-RestMethod https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest
    $asset = $rel.assets | Where-Object { $_.name -like "UE4SS_v*" } | Select-Object -First 1
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip
    $tmp = Join-Path $env:TEMP "ue4ss-extract"; if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive $zip $tmp
    Copy-Item (Join-Path $tmp "ue4ss") $launcher -Recurse -Force   # no dwmapi.dll: the launcher injects instead
    $ini = Join-Path $ue4ss "UE4SS-settings.ini"
    (Get-Content $ini) -replace '^ConsoleEnabled = .*','ConsoleEnabled = 0' -replace '^GuiConsoleEnabled = .*','GuiConsoleEnabled = 0' | Set-Content $ini
}

# mod + mods.txt (only what we need, Keybinds last)
Copy-Item (Join-Path $root "mod\ChainedTeams") (Join-Path $ue4ss "Mods") -Recurse -Force
New-Item -ItemType Directory -Force (Join-Path $ue4ss "Mods\ChainedTeams\data") | Out-Null
$mods = Join-Path $ue4ss "Mods\mods.txt"
$keep = Get-Content $mods | Where-Object { $_ -match "^(BPML_GenericFunctions|BPModLoaderMod|SplitScreenMod|LineTraceMod) " }
($keep + "ChainedTeams : 1" + "Keybinds : 1") | Set-Content $mods

# launcher exe
& (Join-Path $launcher "build.bat")

# version from the mod
$ver = ([regex]::Match((Get-Content (Join-Path $root "mod\ChainedTeams\Scripts\main.lua") -Raw), 'VERSION = "([^"]+)"')).Groups[1].Value
$stage = Join-Path $env:TEMP "ct-release\ChainedTeams"
if (Test-Path (Split-Path $stage)) { Remove-Item (Split-Path $stage) -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $launcher "ChainedTeams.exe") $stage
Copy-Item (Join-Path $root "docs\FRIEND_GUIDE.md") (Join-Path $stage "HOW TO PLAY.md")
Copy-Item (Join-Path $root "docs\HOST_GUIDE.md") (Join-Path $stage "HOST GUIDE.md")
Copy-Item $ue4ss $stage -Recurse
Get-ChildItem $stage -Recurse -Filter *.log | Remove-Item -Force
$out = Join-Path $root "release"; New-Item -ItemType Directory -Force $out | Out-Null
$zipOut = Join-Path $out "ChainedTeams-v$ver.zip"
Compress-Archive -Path $stage -DestinationPath $zipOut -Force
Write-Host "Built $zipOut"
