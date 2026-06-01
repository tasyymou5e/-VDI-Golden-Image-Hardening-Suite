#Requires -Version 7.0
<#
.SYNOPSIS  Section 16 — Network & Offline Files
.NOTES
    Log : C:\VDI_GPO_Logs\16_Network_OfflineFiles.log
    Disables Offline Files (CSC), WPAD auto-proxy, optionally IPv6.
    Configures DNS search suffix list.
    M365 proxy bypass must be configured at network/PAC file level.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "16_Network_OfflineFiles"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG ─────────────────────────────────────────────────────────────────────
$dnsSuffixes   = @("YOUR-DOMAIN.com", "YOUR-SUBDOMAIN.YOUR-DOMAIN.com")  # <-- Replace with your DNS search suffixes
$disableIPv6   = $false   # Set $true if environment is IPv4-only
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring Network and Offline Files settings ===" "INFO"

# ── 1. Disable Offline Files (CSC) — mandatory for VDI ────────────────────────
Write-Log "--- 1. Disable Offline Files / Client Side Cache (CSC)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\NetCache" `
    -Name "Enabled" -Value 0)) { $errors++ }

# ── 2. Disable WPAD auto-proxy detection ──────────────────────────────────────
Write-Log "--- 2. Disable WPAD auto-proxy detection" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings" `
    -Name "AutoDetect" -Value 0)) { $errors++ }
# Also disable via WinHTTP proxy auto-detect
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" `
    -Name "WpadOverride" -Value 1)) { $errors++ }

# ── 3. Configure DNS search suffix list ──────────────────────────────────────
Write-Log "--- 3. Configure DNS search suffix list" "INFO"
$placeholderDns = $dnsSuffixes | Where-Object { $_ -like "*YOUR-DOMAIN*" -or $_ -eq "" }
if ($placeholderDns.Count -eq $dnsSuffixes.Count) {
    Write-Log "WARNING: DNS suffixes not configured — update the dnsSuffixes variable at top of script." "WARN"; $warns++
} else {
    try {
        Set-DnsClientGlobalSetting -SuffixSearchList $dnsSuffixes -ErrorAction Stop
        Write-Log "DNS suffix search list set: $($dnsSuffixes -join ', ')" "SUCCESS"
    } catch {
        Write-Log "DNS suffix list config failed: $_" "WARN"; $warns++
    }
}

# ── 4. Ensure NLA service is Automatic ───────────────────────────────────────
Write-Log "--- 4. Ensure NLA (NlaSvc) is Automatic start" "INFO"
if (-not (Set-ServiceConfig -Name "NlaSvc" -StartupType Automatic)) { $errors++ }

# ── 5. Disable IPv6 (conditional — IPv4-only environments) ───────────────────
Write-Log "--- 5. IPv6 configuration — conditional" "INFO"
if ($disableIPv6) {
    Write-Log "Disabling IPv6 (disableIPv6 = true)" "INFO"
    if (-not (Set-RegValue -Hive HKLM `
        -Path "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
        -Name "DisabledComponents" -Value 0xFF)) { $errors++ }
} else {
    Write-Log "SKIP: IPv6 not disabled. Set disableIPv6=true if environment is IPv4-only." "SKIP"
    $skipped++
}

# ── 6. Enable SMBv2/v3 (verify after SMBv1 disable in Section 12) ────────────
Write-Log "--- 6. Verify SMBv2 is enabled (required for DEM and FSLogix shares)" "INFO"
try {
    $smb2 = (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB2Protocol
    if ($smb2) { Write-Log "SMBv2 is enabled." "SUCCESS" }
    else {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
        Write-Log "SMBv2 was disabled — re-enabled." "WARN"; $warns++
    }
} catch { Write-Log "SMBv2 check/enable failed: $_" "WARN"; $warns++ }

Write-Log "=== Section 16 complete ===" "INFO"
Write-Log "REMINDER: Configure M365 proxy bypass (*.teams.microsoft.com, *.onedrive.com, *.sharepoint.com) at PAC file or network proxy level — not in this script." "WARN"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
