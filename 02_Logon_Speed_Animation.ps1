#Requires -Version 7.0
<#
.SYNOPSIS  Section 02 — Logon Speed & Animation
.NOTES
    Log : C:\VDI_GPO_Logs\02_Logon_Speed_Animation.log
    Removes visual effects, enforces network-ready logon, defers Teams startup.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "02_Logon_Speed_Animation"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Logon Speed and Animation settings ===" "INFO"

# ── 1. Disable Acrylic / Blur at logon screen ──────────────────────────────────
Write-Log "--- 1. Disable logon background blur (Acrylic)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "DisableAcrylicBackgroundOnLogon" -Value 1)) { $errors++ }

# ── 2. Disable Windows startup sound ──────────────────────────────────────────
Write-Log "--- 2. Disable Windows startup/logon sound" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" `
    -Name "DisableStartupSound" -Value 1)) { $errors++ }

# Also via policy key
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "DisableStartupSound" -Value 1)) { $errors++ }

# ── 3. Always wait for network at startup and logon ────────────────────────────
Write-Log "--- 3. Enable SyncForegroundPolicy (wait for network)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -Name "SyncForegroundPolicy" -Value 1)) { $errors++ }

# ── 4. Disable logon animation (Winlogon) ──────────────────────────────────────
Write-Log "--- 4. Disable first logon animation (Winlogon key)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -Name "EnableFirstLogonAnimation" -Value 0)) { $errors++ }

# ── 5. Disable screen saver (Horizon manages idle) ────────────────────────────
Write-Log "--- 5. Disable screen saver via machine policy" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaveActive" -Value "0" -Type String)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaverIsSecure" -Value "0" -Type String)) { $errors++ }

# ── 6. Disable 'Getting Windows ready' hold screen on shutdown/startup ─────────
Write-Log "--- 6. Disable apps-blocked-on-shutdown hold screen" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "DisableShutdownAppsBlockedOnUpdates" -Value 1)) { $errors++ }

# ── 7. Teams startup — Remove from machine-level Run key (NEW) ────────────────
Write-Log "--- 7. NEW: Remove Teams from HKLM Run key (defer to DEM action set)" "INFO"
$teamsRunPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$teamsRunKey  = "HKLM:\$teamsRunPath"
try {
    $runVals = Get-ItemProperty -Path $teamsRunKey -ErrorAction SilentlyContinue
    $removed = $false
    foreach ($prop in $runVals.PSObject.Properties) {
        if ($prop.Name -notlike "PS*" -and $prop.Value -like "*Teams*") {
            Remove-RegValue -Hive HKLM -Path $teamsRunPath -Name $prop.Name
            $removed = $true
        }
    }
    if (-not $removed) { Write-Log "No Teams entry found in HKLM Run key" "SKIP"; $skipped++ }
} catch {
    Write-Log "Could not check HKLM Run key for Teams: $_" "WARN"; $warns++
}

# ── 8. Disable RunLogonScriptSync (let DEM run async) ─────────────────────────
Write-Log "--- 8. Disable synchronous logon scripts (let DEM run async)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "RunLogonScriptSync" -Value 0)) { $errors++ }

# ── 9. Disable automatic restart sign-on (ARSO) ───────────────────────────────
Write-Log "--- 9. Disable automatic restart sign-on (ARSO)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
    -Name "DisableAutomaticRestartSignOn" -Value 1)) { $errors++ }

Write-Log "=== Section 02 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
