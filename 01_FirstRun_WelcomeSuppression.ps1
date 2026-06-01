#Requires -Version 7.0
<#
.SYNOPSIS  Section 01 — First-Run & Welcome Suppression
.NOTES
    Stack  : Omnissa Horizon 8 | Windows 11 24H2 | Non-Persistent | DEM | FSLogix ODFC
    Log    : C:\VDI_GPO_Logs\01_FirstRun_WelcomeSuppression.log
    Source : Microsoft / Omnissa best practices
    Run As : Local Administrator (SYSTEM preferred during image build)
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "01_FirstRun_WelcomeSuppression"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Disabling First-Run, OOBE, and Welcome Screen policies ===" "INFO"

# ── 1. First Logon Animation (policy key) ──────────────────────────────────────
Write-Log "--- 1. First Logon Animation (policy)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableFirstLogonAnimation" -Value 0)) { $errors++ }

# ── 2. First Logon Animation (Winlogon key — belt AND braces for 24H2) ─────────
Write-Log "--- 2. First Logon Animation (Winlogon)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -Name "EnableFirstLogonAnimation" -Value 0)) { $errors++ }

# ── 3. Windows Consumer Features (blocks suggested apps on new profiles) ────────
Write-Log "--- 3. Disable Windows Consumer Features" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsConsumerFeatures" -Value 1)) { $errors++ }

# ── 4. Welcome Experience / What's New pages ───────────────────────────────────
Write-Log "--- 4. Disable Windows Welcome Experience" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsSpotlightWindowsWelcomeExperience" -Value 1)) { $errors++ }

# ── 5. Soft Landing / New Feature Tips ─────────────────────────────────────────
Write-Log "--- 5. Disable Soft Landing (new feature tips)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableSoftLanding" -Value 1)) { $errors++ }

# ── 6. Edge — Hide First Run Experience ────────────────────────────────────────
Write-Log "--- 6. Suppress Microsoft Edge first-run wizard" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Edge" `
    -Name "HideFirstRunExperience" -Value 1)) { $errors++ }

# ── 7. Edge — Disable browser data auto-import ─────────────────────────────────
Write-Log "--- 7. Disable Edge auto-import on first run" "INFO"
# AutoImportAtFirstRun: 4 = DisabledAutoImport
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Edge" `
    -Name "AutoImportAtFirstRun" -Value 4)) { $errors++ }

# ── 8. Teams 2.x — Suppress first-launch splash (NEW — Teams in stack) ─────────
Write-Log "--- 8. NEW: Suppress Teams first-launch splash screen" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\MicrosoftTeams" `
    -Name "PreventFirstLaunchAfterInstall" -Value 1)) { $errors++ }

# ── 9. Disable 'Finish setting up your device' prompt ──────────────────────────
Write-Log "--- 9. Disable 'Finish setting up' device prompt" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "EnableFirstLogonAnimation" -Value 0)) { $errors++ }

# ── 10. Feedback notifications (DoNotShowFeedbackNotifications) ────────────────
Write-Log "--- 10. Disable feedback notifications" "INFO"
# Applied at machine level — affects all users
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "DoNotShowFeedbackNotifications" -Value 1)) { $errors++ }

Write-Log "=== Section 01 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
