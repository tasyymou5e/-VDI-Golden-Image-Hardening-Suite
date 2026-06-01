#Requires -Version 7.0
<#
.SYNOPSIS
    Shared helper functions for all VDI GPO deployment scripts.
    Dot-source this file from each section script:
        . "$PSScriptRoot\Shared_Helpers.ps1"
#>

$Script:LogDir  = "C:\VDI_GPO_Logs"
$Script:LogFile = $null   # Set by each section script before calling any helper

function Initialize-Log {
    param([string]$SectionName)
    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }
    $Script:LogFile = Join-Path $Script:LogDir "$SectionName.log"
    $header = @"
================================================================================
  VDI Golden Image — GPO Deployment Script
  Section : $SectionName
  Host    : $($env:COMPUTERNAME)
  User    : $($env:USERNAME)
  Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  PS Ver  : $($PSVersionTable.PSVersion)
================================================================================
"@
    Add-Content -Path $Script:LogFile -Value $header
    Write-Host $header -ForegroundColor Cyan
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","SKIP")][string]$Level = "INFO"
    )
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$($Level.PadRight(7))] $Message"
    Add-Content -Path $Script:LogFile -Value $entry
    $color = switch ($Level) {
        "SUCCESS" { "Green"  }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red"    }
        "SKIP"    { "Gray"   }
        default   { "White"  }
    }
    Write-Host $entry -ForegroundColor $color
}

function Close-Log {
    param([int]$Errors = 0, [int]$Warnings = 0, [int]$Skipped = 0)
    $footer = @"
================================================================================
  Completed : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Errors    : $Errors
  Warnings  : $Warnings
  Skipped   : $Skipped
  Log file  : $Script:LogFile
================================================================================
"@
    Add-Content -Path $Script:LogFile -Value $footer
    $col = if ($Errors -gt 0) { "Red" } elseif ($Warnings -gt 0) { "Yellow" } else { "Green" }
    Write-Host $footer -ForegroundColor $col
}

function Set-RegValue {
    <#
    .SYNOPSIS Sets a registry value, creating the key path if needed.
    .PARAMETER Hive   HKLM or HKCU
    .PARAMETER Path   Registry path (without hive prefix)
    .PARAMETER Name   Value name
    .PARAMETER Value  Value data
    .PARAMETER Type   REG type: DWORD, String, ExpandString, MultiString, QWord, Binary
    #>
    param(
        [string]$Hive  = "HKLM",
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type  = "DWORD"
    )
    $fullPath = "${Hive}:\$Path"
    try {
        if (-not (Test-Path $fullPath)) {
            New-Item -Path $fullPath -Force | Out-Null
            Write-Log "Created registry key: $fullPath" "INFO"
        }
        $before = try { (Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction Stop).$Name } catch { "<not set>" }
        Set-ItemProperty -Path $fullPath -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        $after  = (Get-ItemProperty -Path $fullPath -Name $Name).$Name
        Write-Log "SET  $fullPath\$Name  [ $before  ->  $after ]  (Type: $Type)" "SUCCESS"
        return $true
    } catch {
        Write-Log "FAIL $fullPath\$Name  Error: $_" "ERROR"
        return $false
    }
}

function Remove-RegValue {
    param([string]$Hive = "HKLM", [string]$Path, [string]$Name)
    $fullPath = "${Hive}:\$Path"
    try {
        if (Test-Path $fullPath) {
            $prop = Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop) {
                Remove-ItemProperty -Path $fullPath -Name $Name -Force -ErrorAction Stop
                Write-Log "REMOVED $fullPath\$Name" "SUCCESS"
            } else {
                Write-Log "SKIP    $fullPath\$Name  (value not present)" "SKIP"
            }
        } else {
            Write-Log "SKIP    $fullPath  (key not present)" "SKIP"
        }
        return $true
    } catch {
        Write-Log "FAIL    $fullPath\$Name  Error: $_" "ERROR"
        return $false
    }
}

function Set-ServiceConfig {
    param([string]$Name, [string]$StartupType, [bool]$StopNow = $false)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $before = $svc.StartType
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        Write-Log "SERVICE $Name  StartupType: $before -> $StartupType" "SUCCESS"
        if ($StopNow -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction Stop
            Write-Log "SERVICE $Name  Stopped." "SUCCESS"
        }
        return $true
    } catch {
        Write-Log "FAIL SERVICE $Name  Error: $_" "ERROR"
        return $false
    }
}

function Add-DefenderExclusion {
    param(
        [string[]]$Paths      = @(),
        [string[]]$Processes  = @(),
        [string[]]$Extensions = @()
    )
    try {
        if ($Paths)      { Add-MpPreference -ExclusionPath      $Paths      -ErrorAction Stop; Write-Log "Defender PATH exclusions added: $($Paths -join ', ')" "SUCCESS" }
        if ($Processes)  { Add-MpPreference -ExclusionProcess   $Processes  -ErrorAction Stop; Write-Log "Defender PROCESS exclusions added: $($Processes -join ', ')" "SUCCESS" }
        if ($Extensions) { Add-MpPreference -ExclusionExtension $Extensions -ErrorAction Stop; Write-Log "Defender EXTENSION exclusions added: $($Extensions -join ', ')" "SUCCESS" }
        return $true
    } catch {
        Write-Log "FAIL Defender exclusion  Error: $_" "ERROR"
        return $false
    }
}

function Add-FirewallRule {
    param(
        [string]$DisplayName,
        [string]$Protocol,
        [string]$LocalPort,
        [string]$Direction  = "Inbound",
        [string]$Action     = "Allow",
        [string]$Profile    = "Any",
        [string]$Program    = $null
    )
    try {
        $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "SKIP Firewall rule '$DisplayName' already exists" "SKIP"
            return $true
        }
        $params = @{
            DisplayName = $DisplayName; Protocol = $Protocol; LocalPort  = $LocalPort
            Direction   = $Direction;  Action   = $Action;   Profile    = $Profile
            Enabled     = "True"
        }
        if ($Program) { $params.Program = $Program }
        New-NetFirewallRule @params | Out-Null
        Write-Log "Firewall rule CREATED: $DisplayName ($Protocol $LocalPort $Direction)" "SUCCESS"
        return $true
    } catch {
        Write-Log "FAIL Firewall rule '$DisplayName'  Error: $_" "ERROR"
        return $false
    }
}

function Backup-RegistrySection {
    <#
    .SYNOPSIS Exports a registry hive path to a .reg file before the section modifies it.
    .PARAMETER Hive  HKLM or HKCU
    .PARAMETER Path  Registry path (without hive prefix)
    .PARAMETER Tag   Label used in the backup filename (e.g. section number)
    #>
    param([string]$Hive = "HKLM", [string]$Path, [string]$Tag = "backup")
    $backupFile = Join-Path $Script:LogDir "reg_backup_${Tag}_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    $fullPath   = "${Hive}\$Path"
    try {
        $result = reg export $fullPath $backupFile /y 2>&1
        Write-Log "Registry backup: $fullPath -> $backupFile" "INFO"
        return $true
    } catch {
        Write-Log "Registry backup FAILED for $fullPath : $_" "WARN"
        return $false
    }
}

function Test-RegValue {
    <#
    .SYNOPSIS Verifies a registry value matches an expected value. Logs PASS or FAIL.
    .RETURNS  $true if the value matches; $false otherwise.
    #>
    param(
        [string]$Hive  = "HKLM",
        [string]$Path,
        [string]$Name,
        $Expected
    )
    $fullPath = "${Hive}:\$Path"
    try {
        $actual = (Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction Stop).$Name
        if ($actual -eq $Expected) {
            Write-Log "VERIFY PASS  $fullPath\$Name = $actual" "SUCCESS"
            return $true
        } else {
            Write-Log "VERIFY FAIL  $fullPath\$Name  Expected: $Expected  Actual: $actual" "WARN"
            return $false
        }
    } catch {
        Write-Log "VERIFY FAIL  $fullPath\$Name  (not readable: $_)" "WARN"
        return $false
    }
}

function Get-OSEdition {
    <#
    .SYNOPSIS Returns 'Enterprise', 'Education', 'Pro', or 'Other' based on OS caption.
    #>
    $caption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    if ($caption -match 'Enterprise') { return 'Enterprise' }
    if ($caption -match 'Education')  { return 'Education'  }
    if ($caption -match '\bPro\b')    { return 'Pro'        }
    return 'Other'
}

function Test-AdminPrivilege {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Prerequisites {
    if (-not (Test-AdminPrivilege)) {
        Write-Host "ERROR: This script must run as Administrator." -ForegroundColor Red
        exit 1
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "ERROR: PowerShell 7.0 or higher is required." -ForegroundColor Red
        exit 1
    }
}
