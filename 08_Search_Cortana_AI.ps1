#Requires -Version 7.0
<#
.SYNOPSIS  Section 08 — Search, Cortana & AI Features (Windows 11 24H2)
.NOTES
    Log : C:\VDI_GPO_Logs\08_Search_Cortana_AI.log
    Disables Cortana, Bing Search, Recall, Click to Do, Copilot.
    These are MANDATORY in VDI — Recall/AI features generate GPU/disk
    overhead incompatible with non-persistent shared infrastructure.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "08_Search_Cortana_AI"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Disabling Search, Cortana, and AI features (24H2) ===" "INFO"

# ── 1. Disable Cortana ────────────────────────────────────────────────────────
Write-Log "--- 1. Disable Cortana" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "AllowCortana" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "AllowCortanaAboveLock" -Value 0)) { $errors++ }

# ── 2. Disable Bing / web search in Windows Search ───────────────────────────
Write-Log "--- 2. Disable web search (Bing) in Windows Search" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "DisableWebSearch" -Value 1)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "ConnectedSearchUseWeb" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "ConnectedSearchSafeSearch" -Value 3)) { $errors++ }

# ── 3. Disable Search Highlights ─────────────────────────────────────────────
Write-Log "--- 3. Disable Search Highlights (daily CDN hero images)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
    -Name "EnableDynamicContentInWSB" -Value 0)) { $errors++ }

# ── 4. Disable Windows Copilot ───────────────────────────────────────────────
Write-Log "--- 4. Disable Windows Copilot (separate from M365 Copilot)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
    -Name "TurnOffWindowsCopilot" -Value 1)) { $errors++ }

# ── 5. Disable Windows Recall — MANDATORY on VDI ─────────────────────────────
Write-Log "--- 5. Disable Windows Recall (MANDATORY — GPU screenshot service)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
    -Name "AllowRecall" -Value 0)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
    -Name "TurnOffSavingSnapshots" -Value 1)) { $errors++ }

# ── 6. Disable Click to Do (24H2 AI screen overlay) ──────────────────────────
Write-Log "--- 6. Disable Click to Do AI overlay (24H2 new feature)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
    -Name "DisableAIDataAnalysis" -Value 1)) { $errors++ }

# ── 7. Disable Windows Spotlight ─────────────────────────────────────────────
Write-Log "--- 7. Disable Windows Spotlight" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsSpotlightFeatures" -Value 1)) { $errors++ }

Write-Log "=== Section 08 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
