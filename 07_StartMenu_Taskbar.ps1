#Requires -Version 7.0
<#
.SYNOPSIS  Section 07 — Start Menu & Taskbar
.NOTES
    Log : C:\VDI_GPO_Logs\07_StartMenu_Taskbar.log
    24H2 Start layout uses LayoutModification.json — deploy via DEM.
    This script handles registry-based Taskbar and Start menu policies.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "07_StartMenu_Taskbar"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Start Menu and Taskbar policies ===" "INFO"

# ── 1. Disable 'Recommended' section in Start (24H2) ─────────────────────────
Write-Log "--- 1. Hide Recommended section in Start menu (24H2)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "HideRecommendedSection" -Value 1)) { $errors++ }

# ── 2. Remove Widgets / News and Interests button ─────────────────────────────
Write-Log "--- 2. Disable Widgets (News and Interests) on Taskbar" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Dsh" `
    -Name "AllowNewsAndInterests" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" `
    -Name "EnableFeeds" -Value 0)) { $errors++ }

# ── 3. Disable consumer Teams Chat icon on Taskbar ────────────────────────────
Write-Log "--- 3. Disable consumer Teams Chat Taskbar icon" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Chat" `
    -Name "ChatIcon" -Value 3)) { $errors++ }

# ── 4. Disable Task View button ───────────────────────────────────────────────
Write-Log "--- 4. Disable Task View / Timeline button" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "HideTaskViewButton" -Value 1)) { $errors++ }

# ── 5. Lock Taskbar position (prevent user repositioning) ─────────────────────
Write-Log "--- 5. Lock Taskbar to bottom — prevent repositioning" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "LockTaskbar" -Value 1)) { $errors++ }

# ── 6. Disable People bar / Contact bar on Taskbar ───────────────────────────
Write-Log "--- 6. Disable People bar on Taskbar" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "HidePeopleBar" -Value 1)) { $errors++ }

Write-Log "=== Section 07 complete ===" "INFO"
Write-Log "REMINDER: Deploy LayoutModification.json via DEM File/Folder Operations to pin Teams, OneDrive, Outlook." "WARN"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
