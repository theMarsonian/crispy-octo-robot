<#
.SYNOPSIS
  Akdamar - TeamViewer: postavlja lozinku za nenadzirani pristup i allowlistu iz .tvopt datoteke.

.DESCRIPTION
  1. Iz .tvopt datoteke uzima SAMO HKLM postavke (allowlista, sigurnost, DefaultSettings).
     HKCU dijelovi se preskacu (inace bi pod SYSTEM-om zavrsili u profilu SYSTEM-a).
     Vrijednost ServerPasswordAES se preskace - lozinku postavlja korak 3.
  2. Zaustavlja TeamViewer, uvozi postavke, pokrece ga.
  3. Postavlja lozinku naredbom "TeamViewer.exe setpassword".
  4. Provjerava da je allowlista ukljucena i ispisuje dopustene racune.
  Log: C:\ProgramData\Akdamar\tv-setup.log

  Pokretanje: 64-bitni PowerShell kao Administrator, ili kao SYSTEM preko RMM-a.
  TeamViewer (full verzija, 15+) mora biti vec instaliran.

.PARAMETER Password
  Nova lozinka za nenadzirani pristup.

.PARAMETER SettingsFile
  Putanja do .tvopt exporta. Default: prva *.tvopt datoteka u mapi skripte.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\tv-setup.ps1 -Password "NovaLozinka123!"

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\tv-setup.ps1 -Password "NovaLozinka123!" -SettingsFile "C:\Temp\0112JT_template_tv.tvopt"
#>
param(
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$SettingsFile
)

$ErrorActionPreference = 'Stop'

# --- Log -------------------------------------------------------------------
$logDir = Join-Path $env:ProgramData 'Akdamar'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'tv-setup.log') -Append | Out-Null

function Fail([string]$msg, [int]$code) {
    Write-Host "GRESKA: $msg" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit $code
}

# --- 0. Preduvjeti ---------------------------------------------------------
# Admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Pokreni PowerShell kao Administrator (ili kao SYSTEM preko RMM-a).' 1
}

# 32-bitni PowerShell na 64-bitnom Windowsu (cesto kod RMM agenata) -> ponovno pokreni u 64-bitnom
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Host 'Pokrenuto u 32-bitnom PowerShellu, prebacujem u 64-bitni...'
    Stop-Transcript | Out-Null
    $ps64 = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Password', "`"$Password`"")
    if ($SettingsFile) { $argList += @('-SettingsFile', "`"$SettingsFile`"") }
    $p = Start-Process $ps64 -ArgumentList $argList -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# TeamViewer.exe i lokacija u registryju
$tv64 = Join-Path $env:ProgramFiles 'TeamViewer\TeamViewer.exe'
$tv32 = Join-Path ${env:ProgramFiles(x86)} 'TeamViewer\TeamViewer.exe'
if (Test-Path $tv64) {
    $tvExe = $tv64; $regBase = 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer'
} elseif ($tv32 -and (Test-Path $tv32)) {
    $tvExe = $tv32; $regBase = 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\TeamViewer'
} else {
    Fail 'TeamViewer.exe nije pronaden (Program Files ni Program Files (x86)).' 2
}
$tvVersion = (Get-Item $tvExe).VersionInfo.ProductVersion
Write-Host "TeamViewer: $tvExe (verzija $tvVersion)"
Write-Host "Registry:   $regBase"

# .tvopt datoteka
if (-not $SettingsFile) {
    $SettingsFile = Get-ChildItem -Path $PSScriptRoot -Filter '*.tvopt' -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $SettingsFile) { Fail "Nije zadan -SettingsFile i nema *.tvopt datoteke u $PSScriptRoot." 3 }
}
if (-not (Test-Path $SettingsFile)) { Fail "Ne postoji: $SettingsFile" 3 }
Write-Host "Postavke:   $SettingsFile"

# --- 1. Priprema .reg datoteke (samo HKLM, bez ServerPasswordAES) ----------
$lines = Get-Content -Path $SettingsFile    # Get-Content prepoznaje UTF-16/UTF-8 BOM
if (-not ($lines | Select-Object -First 3 | Where-Object { $_ -match 'Windows Registry Editor' })) {
    Fail 'Datoteka nije TeamViewer export u registry formatu.' 3
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add('Windows Registry Editor Version 5.00')
$out.Add('')

$inHKLM = $false
$skipValue = $false
foreach ($line in $lines) {
    # Nastavak viselinijske hex vrijednosti (prethodna linija zavrsila s "\")
    if ($skipValue) {
        if (-not $line.TrimEnd().EndsWith('\')) { $skipValue = $false }
        continue
    }

    if ($line -match '^\[(.+)\]\s*$') {
        $key = $Matches[1]
        $inHKLM = $key -like 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer*'
        if ($inHKLM) {
            $newKey = $key -replace '^HKEY_LOCAL_MACHINE\\SOFTWARE\\TeamViewer', $regBase
            $out.Add("[$newKey]")
        }
        continue
    }

    if (-not $inHKLM) { continue }

    if ($line -match '^"ServerPasswordAES"=') {
        if ($line.TrimEnd().EndsWith('\')) { $skipValue = $true }
        continue
    }

    $out.Add($line)
}

$tmpReg = Join-Path $env:TEMP ("tv-import-{0}.reg" -f [guid]::NewGuid())
[IO.File]::WriteAllLines($tmpReg, $out, [Text.Encoding]::Unicode)

# --- 2. Uvoz -----------------------------------------------------------------
Write-Host 'Zaustavljam TeamViewer...'
Stop-Service -Name 'TeamViewer' -Force -ErrorAction SilentlyContinue
Get-Process -Name 'TeamViewer*' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

Write-Host 'Uvozim postavke...'
$p = Start-Process -FilePath "$env:WINDIR\System32\reg.exe" -ArgumentList "import `"$tmpReg`"" -Wait -PassThru -NoNewWindow
Remove-Item $tmpReg -Force -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) {
    Start-Service -Name 'TeamViewer' -ErrorAction SilentlyContinue
    Fail "reg import nije uspio (exit $($p.ExitCode))." 4
}

Write-Host 'Pokrecem TeamViewer servis...'
Start-Service -Name 'TeamViewer'
(Get-Service -Name 'TeamViewer').WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
Start-Sleep -Seconds 10   # servis treba par sekundi da ucita postavke

# --- 3. Lozinka --------------------------------------------------------------
Write-Host 'Postavljam lozinku...'
$p = Start-Process -FilePath $tvExe -ArgumentList "setpassword `"$Password`"" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) {
    Fail "setpassword nije uspio (exit $($p.ExitCode)). Provjeri je li full verzija TeamViewera 15+." 5
}

# --- 4. Provjera -------------------------------------------------------------
$psKey = 'Registry::' + $regBase
$props = Get-ItemProperty -Path $psKey
Write-Host ''
Write-Host "UseWhitelist   = $($props.UseWhitelist)"
Write-Host "WhitelistBuddy = $(($props.WhitelistBuddy | Where-Object { $_ }) -join ', ')"
Write-Host "Lozinka        = $(if ($props.SecurityPasswordAES -or $props.ServerPasswordAES -or $props.PermanentPassword) { 'postavljena' } else { 'nije pronadena u registryju (provjeri rucno)' })"

if ($props.UseWhitelist -ne 1) { Fail 'Allowlista NIJE ukljucena nakon uvoza.' 6 }

Write-Host ''
Write-Host 'Gotovo: allowlista uvezena, lozinka postavljena.' -ForegroundColor Green
Stop-Transcript | Out-Null
exit 0
