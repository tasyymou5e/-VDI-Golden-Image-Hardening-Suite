#Requires -Version 7.0
<#
.SYNOPSIS  Section 13 — Horizon-Specific Settings
.NOTES
    Log : C:\VDI_GPO_Logs\13_Horizon_Specific.log
    Configures: screen saver suppression, power plan (High Performance),
    NLA service, Horizon firewall rules (also in Section 12).
    ADMX-based settings (display protocol, USB policy, Smart Policies)
    must be configured via Omnissa ADMX templates in Group Policy or
    via the Horizon Console — documented in the Word document.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "13_Horizon_Specific"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Horizon-specific image settings ===" "INFO"

# ── 1. Disable screen saver (Horizon manages idle) ───────────────────────────
Write-Log "--- 1. Disable screen saver machine policy" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaveActive" -Value "0" -Type String)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaveTimeOut" -Value "0" -Type String)) { $errors++ }

# ── 2. Set High Performance power plan ───────────────────────────────────────
Write-Log "--- 2. Set power plan to High Performance" "INFO"
try {
    $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $result = & powercfg /setactive $guid 2>&1
    Write-Log "Power plan set to High Performance ($guid)" "SUCCESS"
} catch {
    Write-Log "Failed to set power plan: $_" "WARN"; $warns++
}

# ── 3. Disable Hibernate ─────────────────────────────────────────────────────
Write-Log "--- 3. Disable Hibernate" "INFO"
try {
    & powercfg /h off 2>&1 | Out-Null
    Write-Log "Hibernate disabled." "SUCCESS"
} catch { Write-Log "Failed to disable hibernate: $_" "WARN"; $warns++ }

# ── 4. Ensure NLA (NlaSvc) is Automatic ──────────────────────────────────────
Write-Log "--- 4. Ensure NLA service is Automatic (required for domain detection)" "INFO"
if (-not (Set-ServiceConfig -Name "NlaSvc" -StartupType Automatic)) { $errors++ }

# ── 5. Disable Remote Desktop services conflict (Horizon uses own transport) ──
Write-Log "--- 5. Horizon Transport — set TermService to manual (Horizon manages)" "INFO"
Write-Log "    SKIP: TermService management depends on deployment mode — evaluate." "SKIP"
$skipped++

# ── 6. Disable Windows Remote Assistance ─────────────────────────────────────
Write-Log "--- 6. Disable Windows Remote Assistance" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Remote Assistance" `
    -Name "fAllowToGetHelp" -Value 0)) { $errors++ }

# ── 7. Blast Extreme codec and display registry settings ──────────────────────
Write-Log "--- 7. Apply Horizon Blast Extreme codec and display base settings" "INFO"
# These are the minimum registry settings for good display quality in VDI.
# Section 18 (18_Horizon_Blast_Display_Configuration.ps1) provides full parameterized
# control — run Section 18 for complete Blast tuning.
$blastPaths = @(
    "SOFTWARE\VMware, Inc.\VMware Blast\Config",
    "SOFTWARE\Policies\VMware, Inc.\VMware Blast\Config",
    "SOFTWARE\Omnissa\Horizon\Blast\Config",
    "SOFTWARE\Policies\Omnissa\Horizon\Blast\Config"
)
foreach ($bp in $blastPaths) {
    # H.264 as base codec (required fallback)
    Set-RegValue -Hive HKLM -Path $bp -Name "AllowH264"        -Value 1 | Out-Null
    # H.264 YUV 4:4:4 — eliminates colour fringing on text and banners
    Set-RegValue -Hive HKLM -Path $bp -Name "H264YUV444Enabled" -Value 1 | Out-Null
    # HEVC (H.265) — better quality-to-bandwidth; enable when GPU supports encode
    Set-RegValue -Hive HKLM -Path $bp -Name "HevcEnabled"       -Value 1 | Out-Null
    # Maximum frames per second — 60fps for fluid logon screen and desktop use
    Set-RegValue -Hive HKLM -Path $bp -Name "MaxFPS"            -Value 60 | Out-Null
}
Write-Log "Blast codec settings applied (H.264/H.264-444/HEVC, MaxFPS=60). Run 18_Horizon_Blast_Display_Configuration.ps1 for full tuning." "SUCCESS"

# ── 8. Quality of Service (QoS) — DSCP marking for Blast/PCoIP traffic ────────
Write-Log "--- 8. Apply QoS DSCP marking for Horizon Blast traffic" "INFO"
# DSCP EF (46) = Expedited Forwarding — highest priority for real-time traffic.
# Routers and switches that honour DSCP will prioritise Blast packets over bulk data,
# reducing frame drops and latency under network load.
try {
    $qosPolicies = @(
        @{ Name="Horizon-Blast-UDP-8443"; Proto="UDP"; Port=8443; DSCP=46 },
        @{ Name="Horizon-Blast-TCP-8443"; Proto="TCP"; Port=8443; DSCP=46 },
        @{ Name="Horizon-PCoIP-UDP-4172"; Proto="UDP"; Port=4172; DSCP=46 },
        @{ Name="Horizon-PCoIP-TCP-4172"; Proto="TCP"; Port=4172; DSCP=46 }
    )
    foreach ($q in $qosPolicies) {
        $existing = Get-NetQosPolicy -Name $q.Name -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            Write-Log "QoS policy already exists: $($q.Name) — skipping." "SKIP"
            $skipped++
        } else {
            New-NetQosPolicy -Name $q.Name `
                -IPProtocol $q.Proto `
                -IPDstPortStart $q.Port -IPDstPortEnd $q.Port `
                -DSCPAction $q.DSCP `
                -NetworkProfile All `
                -ErrorAction Stop | Out-Null
            Write-Log "QoS policy created: $($q.Name)  $($q.Proto) $($q.Port) DSCP=$($q.DSCP)" "SUCCESS"
        }
    }
} catch {
    Write-Log "QoS policy creation failed (non-fatal — requires Windows QoS Packet Scheduler): $_" "WARN"
    $warns++
}

Write-Log "=== Section 13 complete ===" "INFO"
Write-Log "REMINDER: For complete Blast display tuning (resolution, multi-monitor, encoder quality), run 18_Horizon_Blast_Display_Configuration.ps1 separately." "WARN"
Write-Log "REMINDER: QoS DSCP marking requires network equipment (routers/switches) to also honor DSCP values — configure at the network layer." "WARN"
Write-Log "REMINDER: Install Omnissa Virtualization Pack for Teams on the golden image for media optimization." "WARN"
$warns += 3
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
