#Requires -Version 7.0
<#
.SYNOPSIS  Section 09 — Privacy & Telemetry
.NOTES
    Log : C:\VDI_GPO_Logs\09_Privacy_Telemetry.log
    Federal/STIG: AllowTelemetry = 0 (Security tier).
    M365/Teams telemetry is controlled separately via M365 Cloud Policy.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "09_Privacy_Telemetry"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG ─────────────────────────────────────────────────────────────────────
# 0 = Security (Enterprise/Education only — federal/STIG requirement)
# 1 = Required (minimum for Pro/Home)
$telemetryLevel = 0   # Set to 1 if not Enterprise/Education edition
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring Privacy and Telemetry policies ===" "INFO"

# ── OS Edition check — telemetry level 0 requires Enterprise or Education ──────
$osEdition = Get-OSEdition
Write-Log "OS Edition detected: $osEdition" "INFO"
if ($telemetryLevel -eq 0 -and $osEdition -notin @('Enterprise','Education')) {
    Write-Log "WARNING: AllowTelemetry = 0 (Security) is not honored on $osEdition. Falling back to level 1 (Required)." "WARN"
    $telemetryLevel = 1
    $warns++
}

# ── 1. Set Diagnostic Data level ──────────────────────────────────────────────
Write-Log "--- 1. Set AllowTelemetry = $telemetryLevel" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "AllowTelemetry" -Value $telemetryLevel)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "LimitDiagnosticLogCollection" -Value 1)) { $errors++ }

# ── 2. Disable Advertising ID ─────────────────────────────────────────────────
Write-Log "--- 2. Disable Advertising ID" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
    -Name "DisabledByGroupPolicy" -Value 1)) { $errors++ }

# ── 3. Disable Activity History / Timeline ────────────────────────────────────
Write-Log "--- 3. Disable Activity History and Timeline" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableActivityFeed" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "PublishUserActivities" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "UploadUserActivities" -Value 0)) { $errors++ }

# ── 4. Disable Consumer Features ─────────────────────────────────────────────
Write-Log "--- 4. Disable Windows Consumer Features" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsConsumerFeatures" -Value 1)) { $errors++ }

# ── 5. Disable Feedback notifications ────────────────────────────────────────
Write-Log "--- 5. Disable feedback notifications" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "DoNotShowFeedbackNotifications" -Value 1)) { $errors++ }

# ── 6. Disable DiagTrack (Connected User Experiences) service ─────────────────
Write-Log "--- 6. Disable DiagTrack telemetry service" "INFO"
if (-not (Set-ServiceConfig -Name "DiagTrack" -StartupType Disabled -StopNow $true)) { $warns++ }

# ── 7. Disable Error Reporting ───────────────────────────────────────────────
Write-Log "--- 7. Disable Windows Error Reporting" "INFO"
if (-not (Set-ServiceConfig -Name "WerSvc" -StartupType Disabled)) { $warns++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
    -Name "Disabled" -Value 1)) { $errors++ }

Write-Log "=== Section 09 complete ===" "INFO"
Write-Log "REMINDER: M365/Teams telemetry must be configured separately via Microsoft 365 Cloud Policy Service." "WARN"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
