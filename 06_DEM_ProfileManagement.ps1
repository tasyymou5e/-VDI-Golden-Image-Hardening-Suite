#Requires -Version 7.0
<#
.SYNOPSIS  Section 06 — Omnissa DEM (Dynamic Environment Manager) Profile Management
.NOTES
    Log : C:\VDI_GPO_Logs\06_DEM_ProfileManagement.log
    Configures DEM FlexEngine for non-persistent Horizon sessions.
    DEM manages the user profile, personalisation, folder redirection,
    and application settings in place of roaming profiles or GPO folder redir.

    DEM is the profile/personalisation layer:
      - Section 05 (FSLogix ODFC) handles Office DATA files (OST, Teams cache)
      - Section 06 (DEM) handles user SETTINGS, desktop, app preferences

    IMPORTANT: Do NOT configure GPO Folder Redirection alongside DEM folder
               redirection — they conflict and can cause data loss.

    PLACEHOLDER: Update $demConfigShare before deployment.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "06_DEM_ProfileManagement"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG — must be updated before deployment ─────────────────────────────────
$demConfigShare  = "\\YOUR-SERVER\DEM-Config"   # <-- UNC path to DEM config share
$demArchivePath  = "\\YOUR-SERVER\DEM-Archive"  # <-- UNC path to DEM profile archive (can be same server)
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring Omnissa DEM Profile Management ===" "INFO"

foreach ($placeholder in @($demConfigShare, $demArchivePath)) {
    if ($placeholder -like "*YOUR-SERVER*") {
        Write-Log "WARNING: DEM path placeholder not replaced: $placeholder" "WARN"; $warns++
    }
}

# ── 0. Detect DEM FlexEngine service (name varies by DEM version) ─────────────
Write-Log "--- 0. Detect DEM FlexEngine service" "INFO"
$demService = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*DEM*" -or
                   $_.DisplayName -like "*Dynamic Environment*" -or
                   $_.DisplayName -like "*FlexEngine*" -or
                   $_.Name        -like "*FlexEngine*" } |
    Select-Object -First 1

if ($null -eq $demService) {
    Write-Log "ERROR: DEM FlexEngine service not found. Install DEM agent before running this script." "ERROR"
    $errors++
} else {
    Write-Log "DEM service found: $($demService.Name) ($($demService.DisplayName))" "SUCCESS"
    # Ensure service is set to Automatic
    if (-not (Set-ServiceConfig -Name $demService.Name -StartupType Automatic)) { $errors++ }
}

# ── 1. Set DEM Config Share path ──────────────────────────────────────────────
Write-Log "--- 1. Set DEM configuration share path" "INFO"
$demRegBase = "SOFTWARE\Policies\Immidio\Flex Profiles"

if ($demConfigShare -notlike "*YOUR-SERVER*") {
    if (-not (Set-RegValue -Hive HKLM `
        -Path $demRegBase `
        -Name "FlexConfigsPath" -Value $demConfigShare -Type String)) { $errors++ }

    # Validate reachability
    if (Test-Path $demConfigShare) {
        Write-Log "DEM config share reachable: $demConfigShare" "SUCCESS"
    } else {
        Write-Log "WARNING: DEM config share not reachable: $demConfigShare" "WARN"; $warns++
    }
} else {
    Write-Log "SKIP: demConfigShare placeholder not replaced." "SKIP"; $skipped++
}

# ── 2. Set DEM profile archive path ───────────────────────────────────────────
Write-Log "--- 2. Set DEM profile archive (personalisation storage) path" "INFO"
if ($demArchivePath -notlike "*YOUR-SERVER*") {
    if (-not (Set-RegValue -Hive HKLM `
        -Path $demRegBase `
        -Name "DesktopContainerPath" -Value $demArchivePath -Type String)) { $errors++ }
} else {
    Write-Log "SKIP: demArchivePath placeholder not replaced." "SKIP"; $skipped++
}

# ── 3. Enable DEM logging for build validation ────────────────────────────────
Write-Log "--- 3. Enable DEM verbose logging (for build validation — reduce after seal)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path $demRegBase `
    -Name "LogLevel" -Value 1)) { $warns++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path $demRegBase `
    -Name "LogPath" -Value "C:\VDI_GPO_Logs\DEM_FlexEngine.log" -Type String)) { $warns++ }

# ── 4. Disable GPO Folder Redirection conflict check ──────────────────────────
Write-Log "--- 4. Verify GPO Folder Redirection is not active (conflicts with DEM)" "INFO"
$gpoFolderRedir = @(
    "SOFTWARE\Policies\Microsoft\Windows\System\FolderRedirection",
    "SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore"
)
foreach ($path in $gpoFolderRedir) {
    if (Test-Path "HKLM:\$path") {
        $keys = Get-ItemProperty -Path "HKLM:\$path" -ErrorAction SilentlyContinue
        if ($null -ne $keys) {
            Write-Log "WARNING: GPO Folder Redirection registry keys found at HKLM:\$path — this may conflict with DEM folder redirection." "WARN"
            $warns++
        }
    }
}

# ── 5. Set DEM sync mode for non-persistent VDI ───────────────────────────────
Write-Log "--- 5. Set DEM sync behaviour for non-persistent sessions" "INFO"
# DirectFlex = DEM writes settings directly to network on change (not just at logoff)
# This is critical for non-persistent VDI where logoff can be abrupt
if (-not (Set-RegValue -Hive HKLM `
    -Path $demRegBase `
    -Name "DirectFlexEnabled" -Value 1)) { $warns++ }

Write-Log "=== Section 06 complete ===" "INFO"
Write-Log "REMINDER: DEM folder redirection rules (Desktop, Documents, Pictures) must be configured in the DEM Administration Console — they cannot be scripted here." "WARN"
Write-Log "REMINDER: DEM Action Sets (logon/logoff scripts) must be configured in the DEM console, not via this script." "WARN"
Write-Log "REMINDER: FSLogix Profile Container must remain DISABLED (Section 05). DEM manages the user profile." "WARN"
Write-Log "REMINDER: Reduce DEM LogLevel from 1 back to 0 after golden image validation is complete." "WARN"
$warns += 4
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
