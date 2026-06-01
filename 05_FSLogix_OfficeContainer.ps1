#Requires -Version 7.0
<#
.SYNOPSIS  Section 05 — FSLogix Office Data File Container (ODFC)
.NOTES
    Log : C:\VDI_GPO_Logs\05_FSLogix_OfficeContainer.log
    Configures the FSLogix ODFC container to roam Office data files
    (Outlook OST, OneNote notebooks, Teams cache, Skype history) across
    non-persistent Horizon sessions.

    ODFC vs Profile Container:
      ODFC stores ONLY Office data files (not the full profile).
      The full user profile is managed by DEM (Section 06).
      Do NOT enable FSLogix Profile Container (that conflicts with DEM).

    PLACEHOLDER: Update $vhdLocation before deployment.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "05_FSLogix_OfficeContainer"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG — must be updated before deployment ─────────────────────────────────
$vhdLocation   = "\\YOUR-SERVER\FSLogix-ODFC"  # <-- UNC path to ODFC share
$odfcSizeMB    = 30720                          # 30 GB default; power users may need 51200 (50 GB)
$volumeType    = "VHDX"                         # VHDX (recommended) or VHD
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring FSLogix Office Data File Container ===" "INFO"

if ($vhdLocation -like "*YOUR-SERVER*") {
    Write-Log "WARNING: vhdLocation placeholder not replaced. ODFC will not function without a valid UNC path." "WARN"
    $warns++
}

# ── Verify FSLogix agent is installed ─────────────────────────────────────────
Write-Log "--- 0. Verify FSLogix agent installation" "INFO"
$fslogixReg = "HKLM:\SOFTWARE\FSLogix\Apps"
if (-not (Test-Path $fslogixReg)) {
    Write-Log "ERROR: FSLogix registry key not found at $fslogixReg. Install FSLogix agent before running this script." "ERROR"
    $errors++
} else {
    $fslogixVer = (Get-ItemProperty $fslogixReg -Name "InstallVersion" -ErrorAction SilentlyContinue).InstallVersion
    Write-Log "FSLogix agent found. Version: $($fslogixVer ?? 'unknown')" "SUCCESS"
}

# ── Verify FSLogix service is running ─────────────────────────────────────────
if (-not (Set-ServiceConfig -Name "frxsvc" -StartupType Automatic)) { $errors++ }

# ── 1. Enable ODFC container ──────────────────────────────────────────────────
Write-Log "--- 1. Enable FSLogix ODFC container" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "Enabled" -Value 1)) { $errors++ }

# ── 2. Set VHD storage location ───────────────────────────────────────────────
Write-Log "--- 2. Set ODFC VHD storage location: $vhdLocation" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "VHDLocations" -Value $vhdLocation -Type String)) { $errors++ }

# Validate UNC path reachability
if ($vhdLocation -notlike "*YOUR-SERVER*") {
    if (Test-Path $vhdLocation) {
        Write-Log "UNC path reachable: $vhdLocation" "SUCCESS"
        # Quick write-permission test
        $testFile = Join-Path $vhdLocation ".vdi_write_test_$(Get-Random)"
        try {
            [System.IO.File]::WriteAllText($testFile, "test")
            Remove-Item $testFile -Force
            Write-Log "Write permission confirmed on: $vhdLocation" "SUCCESS"
        } catch {
            Write-Log "WARNING: No write permission to $vhdLocation. Check NTFS and share permissions." "WARN"; $warns++
        }
    } else {
        Write-Log "WARNING: UNC path not reachable: $vhdLocation — verify share is online and permissions are correct." "WARN"
        $warns++
    }
}

# ── 3. Set VHD size ───────────────────────────────────────────────────────────
Write-Log "--- 3. Set ODFC VHD size: $odfcSizeMB MB" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "SizeInMBs" -Value $odfcSizeMB)) { $errors++ }

# ── 4. Set volume type ────────────────────────────────────────────────────────
Write-Log "--- 4. Set volume type: $volumeType" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "VolumeType" -Value $volumeType -Type String)) { $errors++ }

# ── 5. Mount at logon, dismount at logoff ─────────────────────────────────────
Write-Log "--- 5. Set attach/detach policy (OnLogon)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "AttachVHDSDDL" -Value "" -Type String)) { $skipped++ }  # Use default

# ── 6. What to include in ODFC ────────────────────────────────────────────────
Write-Log "--- 6. Configure ODFC include flags" "INFO"
# OneDrive sync database managed by OneDrive itself (Section 04), not ODFC
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "IncludeOneDrive" -Value 0)) { $errors++ }
# Outlook OST — always include; critical for non-persistent sessions
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "IncludeOutlook" -Value 1)) { $errors++ }
# Outlook OST archive
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "IncludeOutlookPersonalFolders" -Value 1)) { $errors++ }
# OneNote notebooks
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "IncludeOneNote" -Value 1)) { $errors++ }
# Teams cache (new Teams 2.x writes to %LOCALAPPDATA%; include it)
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "IncludeTeams" -Value 1)) { $errors++ }

# ── 7. Profile container — MUST remain disabled (DEM manages the profile) ──────
Write-Log "--- 7. Verify FSLogix Profile Container is DISABLED (DEM manages profile)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\Profiles" `
    -Name "Enabled" -Value 0)) { $errors++ }
Write-Log "FSLogix Profile Container disabled — DEM manages user profile via Section 06." "SUCCESS"

# ── 8. Flip-flop directory name (prevents multi-session conflicts) ─────────────
Write-Log "--- 8. Enable flip-flop profile directory naming" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\FSLogix\ODFC" `
    -Name "FlipFlopProfileDirectoryName" -Value 1)) { $warns++ }

# ── 9. Ensure FSLogix local groups exist ──────────────────────────────────────
Write-Log "--- 9. Ensure FSLogix ODFC local groups exist" "INFO"
foreach ($groupName in @("FSLogix ODFC Include List", "FSLogix ODFC Exclude List")) {
    try {
        Get-LocalGroup -Name $groupName -ErrorAction Stop | Out-Null
        Write-Log "Group exists: $groupName" "SUCCESS"
    } catch {
        try {
            New-LocalGroup -Name $groupName -Description "Managed by FSLogix ODFC" | Out-Null
            Write-Log "Created group: $groupName" "SUCCESS"
        } catch {
            Write-Log "Failed to create group $groupName : $_" "WARN"; $warns++
        }
    }
}

Write-Log "=== Section 05 complete ===" "INFO"
Write-Log "REMINDER: Update vhdLocation placeholder and re-run if ODFC share path was left as placeholder." "WARN"
Write-Log "REMINDER: Verify FSLogix ODFC share NTFS permissions: Users = Modify, CREATOR OWNER = Full Control, SYSTEM = Full Control." "WARN"
Write-Log "REMINDER: DEM manages the user profile (Section 06). FSLogix Profile Container must remain DISABLED." "WARN"
$warns += 3
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
