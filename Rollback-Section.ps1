#Requires -Version 7.0
<#
.SYNOPSIS
    Per-section registry rollback using pre-build backup files.

.DESCRIPTION
    Uses reg export backups (created by Backup-RegistrySection in Shared_Helpers.ps1)
    to restore the registry state of a specific section. Useful when a section
    breaks something and you need to undo it without rebuilding from scratch.

    Backup files are created in C:\VDI_GPO_Logs\ as:
        reg_backup_<Tag>_<yyyyMMdd_HHmmss>.reg

    NOTE: This tool rolls back REGISTRY changes only. It does NOT:
      • Restore service startup type changes (use Set-Service manually)
      • Undo DISM feature changes (SMBv1 removal etc.)
      • Restore files written or deleted by section scripts
      • Un-import any .reg files applied during the section

    The most recent backup for each section tag is used by default.
    Use -ListBackups to see all available backup files.

.PARAMETER Section
    Section number (1-19) or tag name. Examples: 12, "09", "12_Security_Defender"

.PARAMETER BackupFile
    Full path to a specific .reg backup file. Overrides automatic selection.

.PARAMETER ListBackups
    List all available backup .reg files without restoring anything.

.PARAMETER DryRun
    Show the reg import command that would run without executing it.

.PARAMETER BackupDir
    Directory to search for .reg backup files.
    Default: C:\VDI_GPO_Logs\

.EXAMPLE
    # Roll back Section 12 (uses most recent backup for that section)
    .\Rollback-Section.ps1 -Section 12

    # List all available backups
    .\Rollback-Section.ps1 -ListBackups

    # Roll back using a specific backup file
    .\Rollback-Section.ps1 -BackupFile "C:\VDI_GPO_Logs\reg_backup_12_20260521_143022.reg"

    # Preview without executing
    .\Rollback-Section.ps1 -Section 12 -DryRun

.NOTES
    Run As : Local Administrator / SYSTEM
    Pre-req: Shared_Helpers.ps1 Backup-RegistrySection must have been called during
             the section's execution to create the backup files.
             If no backup exists for a section, rollback is not possible.
#>

[CmdletBinding(DefaultParameterSetName="Section")]
param(
    [Parameter(ParameterSetName="Section", Position=0)]
    [string]$Section,

    [Parameter(ParameterSetName="File")]
    [string]$BackupFile,

    [Parameter(ParameterSetName="List")]
    [switch]$ListBackups,

    [switch]$DryRun,

    [string]$BackupDir = "C:\VDI_GPO_Logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Admin guard ────────────────────────────────────────────────────────────────
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

function Write-Status {
    param([string]$Msg, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}

# ── List mode ─────────────────────────────────────────────────────────────────
if ($ListBackups) {
    Write-Status "=== Available Registry Backup Files ===" "Cyan"
    Write-Status "Directory: $BackupDir" "Gray"
    Write-Status ""

    $backupFiles = Get-ChildItem -Path $BackupDir -Filter "reg_backup_*.reg" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($backupFiles.Count -eq 0) {
        Write-Status "No backup files found in $BackupDir" "Yellow"
        Write-Status "Backup files are created by Backup-RegistrySection in Shared_Helpers.ps1" "Gray"
        Write-Status "Ensure sections were run with backup support enabled." "Gray"
    } else {
        $backupFiles | ForEach-Object {
            $sizeMB = [math]::Round($_.Length / 1MB, 2)
            Write-Host ("  {0,-50}  {1,6} MB  {2}" -f $_.Name, $sizeMB, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) -ForegroundColor Gray
        }
        Write-Status ""
        Write-Status "$($backupFiles.Count) backup file(s) found." "Green"
        Write-Status "To restore: .\Rollback-Section.ps1 -Section <number>" "Cyan"
    }
    exit 0
}

# ── Validate BackupDir ─────────────────────────────────────────────────────────
if (-not (Test-Path $BackupDir)) {
    Write-Status "ERROR: Backup directory not found: $BackupDir" "Red"
    Write-Status "No backup files available. Registry rollback is not possible." "Red"
    exit 1
}

# ── Resolve backup file ────────────────────────────────────────────────────────
$resolvedFile = $null

if ($PSCmdlet.ParameterSetName -eq "File") {
    # User specified a file directly
    if (-not (Test-Path $BackupFile)) {
        Write-Status "ERROR: Specified backup file not found: $BackupFile" "Red"
        exit 1
    }
    $resolvedFile = $BackupFile
}
elseif ($PSCmdlet.ParameterSetName -eq "Section") {
    if ([string]::IsNullOrWhiteSpace($Section)) {
        Write-Status "ERROR: Specify -Section <number>, -BackupFile <path>, or -ListBackups" "Red"
        Write-Status "  Examples: .\Rollback-Section.ps1 -Section 12" "Gray"
        Write-Status "            .\Rollback-Section.ps1 -ListBackups" "Gray"
        exit 1
    }

    # Normalise section input: "12", "12_Security_Defender", "09", etc.
    $sectionPad = $Section.PadLeft(2, '0') -replace '^(\d+).*', '$1'   # extract leading digits
    $sectionPad = $sectionPad.PadLeft(2, '0')

    Write-Status "Looking for backups matching section: $Section" "Cyan"

    # Search for backup files matching the section number or tag
    $candidates = Get-ChildItem -Path $BackupDir -Filter "reg_backup_*.reg" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.BaseName -match "_0*$sectionPad[_\-]" -or   # matches "reg_backup_12_..." or "reg_backup_12-..."
            $_.BaseName -match [regex]::Escape($Section)    # matches any tag containing the section string
        } |
        Sort-Object LastWriteTime -Descending

    if ($candidates.Count -eq 0) {
        Write-Status "ERROR: No backup files found for section '$Section'" "Red"
        Write-Status ""
        Write-Status "Available backups:" "Gray"
        Get-ChildItem -Path $BackupDir -Filter "reg_backup_*.reg" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20 |
            ForEach-Object { Write-Status "  $_" "DarkGray" }
        Write-Status ""
        Write-Status "Use -ListBackups to see all available files." "Yellow"
        exit 1
    }

    if ($candidates.Count -gt 1) {
        Write-Status "Multiple backups found for section $Section — using most recent:" "Yellow"
        $candidates | Select-Object -First 5 | ForEach-Object {
            Write-Status "  $($_.Name)  [$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))]" "DarkGray"
        }
    }

    $resolvedFile = $candidates[0].FullName
}

if (-not $resolvedFile) {
    Write-Status "ERROR: Could not resolve a backup file. Use -ListBackups to see available files." "Red"
    exit 1
}

# ── Pre-flight info ────────────────────────────────────────────────────────────
Write-Status "=== Registry Rollback ===" "Cyan"
Write-Status "Backup file : $resolvedFile" "White"
$backupItem = Get-Item $resolvedFile
Write-Status "Created     : $($backupItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Gray"
Write-Status "Size        : $([math]::Round($backupItem.Length / 1KB)) KB" "Gray"
Write-Status ""

if ($DryRun) {
    Write-Status "DRY RUN — would execute:" "Yellow"
    Write-Status "  reg import `"$resolvedFile`"" "Yellow"
    Write-Status ""
    Write-Status "Remove -DryRun to perform the actual rollback." "Yellow"
    exit 0
}

# ── Safety snapshot of current state ──────────────────────────────────────────
Write-Status "Creating a safety snapshot of current registry state before rolling back..." "Cyan"

# Determine which hive(s) are in the backup so we can snapshot just those
$backupContent = Get-Content $resolvedFile -TotalCount 50 -ErrorAction SilentlyContinue
$hivesInBackup = @()
if ($backupContent -match "HKEY_LOCAL_MACHINE") { $hivesInBackup += "HKLM" }
if ($backupContent -match "HKEY_CURRENT_USER")  { $hivesInBackup += "HKCU" }

$safetyTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safetyFiles     = @()
foreach ($hive in $hivesInBackup) {
    # Extract key path from backup file header for targeted snapshot
    # We'll take a broader snapshot of the likely affected root
    $sectionNum = if ($Section) { $Section.PadLeft(2,'0') } else { "manual" }
    $safetyFile = Join-Path $BackupDir "reg_ROLLBACK_SAFETY_sec${sectionNum}_${hive}_${safetyTimestamp}.reg"
    Write-Status "  Snapshotting $hive current state -> $safetyFile" "Gray"
    # Export a broad snapshot of the SOFTWARE hive (most policies live here)
    try {
        & reg export "${hive}\SOFTWARE" $safetyFile /y 2>&1 | Out-Null
        $safetyFiles += $safetyFile
        Write-Status "  Safety snapshot created: $safetyFile" "Gray"
    } catch {
        Write-Status "  WARNING: Safety snapshot failed for $hive : $_" "Yellow"
    }
}

# ── Confirmation ───────────────────────────────────────────────────────────────
Write-Status "" "White"
Write-Host "CAUTION: This will import the backup registry file into the live registry." -ForegroundColor Yellow
Write-Host "  Registry values in the backup file will OVERWRITE current values." -ForegroundColor Yellow
Write-Host "  This does NOT restore deleted keys that no longer exist." -ForegroundColor Yellow
if ($safetyFiles.Count -gt 0) {
    Write-Host "  A safety snapshot has been created — you can undo this rollback by importing:" -ForegroundColor Yellow
    $safetyFiles | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
}
Write-Host ""
$confirm = Read-Host "Type YES to proceed with rollback, anything else to abort"
if ($confirm -ne "YES") {
    Write-Status "Rollback aborted by user." "Yellow"
    exit 0
}

# ── Execute rollback ───────────────────────────────────────────────────────────
Write-Status "" "White"
Write-Status "Importing backup: $resolvedFile" "Cyan"
try {
    $result = & reg import $resolvedFile 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Rollback completed successfully." "Green"
        Write-Status ""
        Write-Status "IMPORTANT NOTES:" "Yellow"
        Write-Status "  • Service startup types changed by the section are NOT reversed." "Yellow"
        Write-Status "    Use Set-Service manually if needed." "Yellow"
        Write-Status "  • Reboot may be required for some registry changes to take effect." "Yellow"
        if ($safetyFiles.Count -gt 0) {
            Write-Status "  • Safety snapshot (for undo): $($safetyFiles -join ', ')" "Yellow"
        }
    } else {
        Write-Status "reg import returned exit code $LASTEXITCODE : $result" "Red"
        exit 1
    }
} catch {
    Write-Status "Rollback FAILED: $_" "Red"
    exit 1
}
