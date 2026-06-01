#Requires -Version 7.0

<#
.SYNOPSIS  
    Section 12 — Security & Microsoft Defender Tuning
.NOTES
    Log : C:\VDI_GPO_Logs\12_Security_Defender.log
#>

. "$PSScriptRoot\Shared_Helpers.ps1"

Confirm-Prerequisites

# ── NEW: Compatibility Imports for PowerShell 7 ──────────────────────────────
# These modules are native to Windows PS 5.1 and require a compatibility session
try {
    Import-Module Defender -UseWindowsPowerShell -ErrorAction SilentlyContinue
    Import-Module NetSecurity -UseWindowsPowerShell -ErrorAction SilentlyContinue
    Import-Module SmbShare -UseWindowsPowerShell -ErrorAction SilentlyContinue
    Import-Module Dism -UseWindowsPowerShell -ErrorAction SilentlyContinue
} catch {
    Write-Log "Failed to load Windows compatibility modules." "WARN"
}
# ─────────────────────────────────────────────────────────────────────────────

Initialize-Log "12_Security_Defender"

$errors = 0; $warns = 0; $skipped = 0
Write-Log "=== Configuring Security and Defender tuning ===" "INFO"

# ── 1. Defender path exclusions ───────────────────────────────────────────────
Write-Log "--- 1. Configure Defender path exclusions" "INFO"
$excludePaths = @(
    "C:\Program Files\FSLogix\Apps",
    "C:\ProgramData\FSLogix",
    "C:\Program Files\VMware\VMware View\Agent",
    "C:\ProgramData\VMware",
    "C:\Program Files\Immidio",
    "C:\ProgramData\Immidio",
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe",
    "$env:LOCALAPPDATA\Microsoft\Teams"
)

foreach ($ep in $excludePaths) {
    try {
        Add-MpPreference -ExclusionPath $ep -ErrorAction Stop
        Write-Log "Defender path exclusion: $ep" "SUCCESS"
    } catch {
        Write-Log "FAILED Defender path exclusion $ep : $_" "WARN"; $warns++
    }
}

# ── 2. Defender process exclusions ────────────────────────────────────────────
Write-Log "--- 2. Configure Defender process exclusions" "INFO"
$excludeProcs = @("frxsvc.exe","frxdrvvt.exe","frxccds.exe","frxrender.exe","OneDrive.exe","ms-teams.exe","Teams.exe")

foreach ($ep in $excludeProcs) {
    try {
        Add-MpPreference -ExclusionProcess $ep -ErrorAction Stop
        Write-Log "Defender process exclusion: $ep" "SUCCESS"
    } catch {
        Write-Log "FAILED Defender process exclusion $ep : $_" "WARN"; $warns++
    }
}

# ── 3. Disable SMBv1 ─────────────────────────────────────────────────────────
Write-Log "--- 3. Disable SMBv1 server and client" "INFO"
try {
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
    Write-Log "SMBv1 Server disabled." "SUCCESS"
} catch { Write-Log "SMBv1 Server disable failed: $_" "WARN"; $warns++ }

try {
    Set-SmbClientConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
    Write-Log "SMBv1 Client disabled." "SUCCESS"
} catch { Write-Log "SMBv1 Client disable failed: $_" "WARN"; $warns++ }

try {
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
    Write-Log "SMB1Protocol feature removed from image." "SUCCESS"
} catch { Write-Log "SMB1Protocol feature removal: $_" "INFO" }

# ── 4. Disable Remote Registry service ───────────────────────────────────────
Write-Log "--- 4. Disable Remote Registry service" "INFO"
if (-not (Set-ServiceConfig -Name "RemoteRegistry" -StartupType Disabled -StopNow $true)) { $warns++ }

# ── 5. Horizon firewall rules ────────────────────────────────────────────────
Write-Log "--- 5. Create Horizon protocol firewall rules" "INFO"
$horizonRules = @(
    @{ Name="VDI-Horizon-PCoIP-TCP-4172";  Proto="TCP"; Port="4172"; Dir="Inbound"  },
    @{ Name="VDI-Horizon-PCoIP-UDP-4172";  Proto="UDP"; Port="4172"; Dir="Inbound"  },
    @{ Name="VDI-Horizon-Blast-TCP-443";   Proto="TCP"; Port="443";  Dir="Inbound"  },
    @{ Name="VDI-Horizon-Blast-TCP-8443";  Proto="TCP"; Port="8443"; Dir="Inbound"  },
    @{ Name="VDI-Horizon-Blast-UDP-8443";  Proto="UDP"; Port="8443"; Dir="Inbound"  },
    @{ Name="VDI-Horizon-USB-TCP-32111";   Proto="TCP"; Port="32111";Dir="Inbound"  },
    @{ Name="VDI-Horizon-MMR-TCP-9427";    Proto="TCP"; Port="9427"; Dir="Inbound"  }
)

foreach ($r in $horizonRules) {
    if (-not (Add-FirewallRule -DisplayName $r.Name -Protocol $r.Proto -LocalPort $r.Port -Direction $r.Dir)) {
        $warns++
    }
}

# ── 6. Teams media optimization firewall rules (NEW) ─────────────────────────
Write-Log "--- 6. Create Teams VDI media optimization firewall rules (NEW)" "INFO"
$teamsRules = @(
    @{ Name="VDI-Teams-STUN-UDP-3478"; Proto="UDP"; Port="3478"; Dir="Inbound" },
    @{ Name="VDI-Teams-STUN-UDP-3479"; Proto="UDP"; Port="3479"; Dir="Inbound" },
    @{ Name="VDI-Teams-STUN-UDP-3480"; Proto="UDP"; Port="3480"; Dir="Inbound" },
    @{ Name="VDI-Teams-STUN-UDP-3481"; Proto="UDP"; Port="3481"; Dir="Inbound" }
)

foreach ($r in $teamsRules) {
    if (-not (Add-FirewallRule -DisplayName $r.Name -Protocol $r.Proto -LocalPort $r.Port -Direction $r.Dir)) {
        $warns++
    }
}

# ── 7. STIG / CIS Network Security Hardening ─────────────────────────────────
Write-Log "--- 7. Apply STIG/CIS network security hardening" "INFO"

# NTLMv2 enforcement — level 5 = Send NTLMv2 responses only, refuse LM and NTLM
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LmCompatibilityLevel" -Value 5)) { $errors++ }

# Restrict anonymous SAM enumeration
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "RestrictAnonymousSAM" -Value 1)) { $errors++ }

if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "RestrictAnonymous" -Value 1)) { $errors++ }

# SMB signing required (prevents MITM relay attacks on UNC paths)
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
    -Name "RequireSecuritySignature" -Value 1)) { $errors++ }

if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
    -Name "EnableSecuritySignature" -Value 1)) { $errors++ }

# RDP security layer 2 = TLS (most secure; required for NLA and CAC pass-through)
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name "SecurityLayer" -Value 2)) { $errors++ }

# ── 8. Defender exclusion fallback via registry ───────────────────────────────
# If Defender is MDE-managed, Add-MpPreference is silently ignored.
# Registry-based exclusions act as a belt-and-braces backup.
Write-Log "--- 8. Apply Defender exclusions via registry (MDE fallback)" "INFO"
$regExcludePath = "SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths"
foreach ($ep in $excludePaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $regExcludePath -Name $ep -Value 0 -Type String)) { $warns++ }
}

Write-Log "=== Section 12 complete ===" "INFO"
Write-Log "NOTE: SMBv1 feature removal requires a REBOOT to take effect." "WARN"
$warns++
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
