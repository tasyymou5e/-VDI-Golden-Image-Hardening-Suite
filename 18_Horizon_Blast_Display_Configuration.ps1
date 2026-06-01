#Requires -Version 7.0<#
.SYNOPSIS  Section 18 — Horizon_Blast_Display_Configuration
           Frame Rate · Resolution · Multi-Monitor · Encoder Codec

.DESCRIPTION
    Forces and locks Blast Extreme display settings on the golden image.
    Covers:
      - Maximum frame rate (MaxFPS) — smooth scrolling / screen refresh
      - Encoder codec priority — H.264 YUV 4:4:4, HEVC, AV1
      - Hardware GPU encoder preference
      - Encoder quality level
      - Maximum resolution per monitor
      - Multi-monitor count and topology
      - High-DPI / display scaling
      - UDP transport enforcement (required for Blast performance)
      - Adaptive quality settings — prevent quality throttling in good networks
      - Bandwidth floor/ceiling per session
      - JPG/PNG quality for screen regions

    REGISTRY PATHS
      HKLM:\SOFTWARE\VMware, Inc.\VMware Blast\Config
          Agent-side Blast codec and display configuration
      HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware VDM\Agent\Configuration
          Agent policy settings (GPO equivalent)
      HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware Blast\Config
          Policy-managed Blast settings (override the Config path if both set)

    IMPORTANT — ADMX vs Registry
      Many Blast settings are exposed via Omnissa Horizon ADMX templates in GPO.
      The registry paths below are the direct equivalent of those ADMX policies.
      If your environment applies Omnissa ADMX GPOs, they write to the Policies
      path and will override the Config path. This script writes to BOTH paths
      so settings survive regardless of whether ADMX GPO is applied.

    MULTI-MONITOR NOTE
      Blast multi-monitor is negotiated between the client and agent.
      The agent controls the ceiling (max monitors, max resolution).
      The client controls actual layout (which monitors, arrangement).
      Forcing multi-monitor requires: (1) the pool is configured to allow it,
      (2) the agent allows it (this script), (3) the Horizon client is
      configured to use multiple monitors in full-screen mode.

.PARAMETER MaxFPS
    Maximum frames per second. Default: 60. Range: 15-60.
    Lower for shared/dense hosts with CPU constraints.
    60 is optimal for smooth CAC-inserted logon screens and fluid desktop use.

.PARAMETER MaxMonitors
    Maximum number of monitors allowed per session. Default: 4.
    Range 1-9. Set to match your hardware layout.

.PARAMETER MaxResolutionPerMonitor
    Maximum resolution per monitor as "WxH". Default: "3840x2160" (4K).
    Common values: "1920x1080", "2560x1440", "3840x2160"

.PARAMETER EnableHEVC
    Enable HEVC (H.265) hardware encoding. Default: $true.
    Requires GPU with HEVC encode support (NVIDIA, AMD, Intel ARC).
    Provides better quality at same bandwidth vs H.264.

.PARAMETER EnableAV1
    Enable AV1 encoding (Horizon 2306+). Default: $false.
    Better compression than HEVC but requires newer GPU (NVIDIA Ada/Lovelace).

.PARAMETER EncoderQuality
    Quality level 0-9. Default: 8 (high quality).
    5 = balanced (default in Horizon), 8 = high quality, 9 = lossless-like.

.EXAMPLE
    # Standard dual 1080p workstation
    pwsh -File 18_Blast_Display_Config.ps1 -MaxFPS 60 -MaxMonitors 2 -MaxResolutionPerMonitor "1920x1080"

    # Triple 1440p analyst station
    pwsh -File 18_Blast_Display_Config.ps1 -MaxFPS 60 -MaxMonitors 3 -MaxResolutionPerMonitor "2560x1440"

    # Single 4K with HEVC
    pwsh -File 18_Blast_Display_Config.ps1 -MaxFPS 60 -MaxMonitors 1 -MaxResolutionPerMonitor "3840x2160" -EnableHEVC $true

.NOTES
    Log     : C:\VDI_GPO_Logs\18_Blast_Display_Config.log
    Run As  : Local Administrator / SYSTEM during golden image build
    Horizon : Tested against Omnissa Horizon 8 (2309 / 2312 / 2403+)
#>

[CmdletBinding()]
param(
    [ValidateRange(15, 60)]
    [int]$MaxFPS                     = 60,

    [ValidateRange(1, 9)]
    [int]$MaxMonitors                = 4,

    [ValidatePattern("^\d+x\d+$")]
    [string]$MaxResolutionPerMonitor = "3840x2160",

    [bool]$EnableHEVC                = $true,
    [bool]$EnableAV1                 = $false,

    [ValidateRange(0, 9)]
    [int]$EncoderQuality             = 8,

    [bool]$ForceUDP                  = $true,
    [bool]$EnableHighDPI             = $true,
    [bool]$DisableAdaptiveQuality    = $false   # Set $true to prevent quality throttle on good networks
)

# ── Self-bootstrap ──────────────────────────────────────────────────────────────
# If Shared_Helpers.ps1 is present in the same directory (full suite deployment),
# dot-source it.  If running standalone, the inline fallback functions below are
# used automatically — no other files required.
$Script:_helpersPath = Join-Path $PSScriptRoot "Shared_Helpers.ps1"
if (Test-Path $Script:_helpersPath) {
    . $Script:_helpersPath
} else {
    # ── Inline helper fallback (standalone mode) ─────────────────────────────
    $Script:LogDir  = "C:\VDI_GPO_Logs"
    $Script:LogFile = $null

    function Initialize-Log {
        param([string]$SectionName)
        if (-not (Test-Path $Script:LogDir)) {
            New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
        }
        $Script:LogFile = Join-Path $Script:LogDir "$SectionName.log"
        $header = @"
================================================================================
  Omnissa Horizon VDI — Blast Display Configuration (Standalone)
  Section : $SectionName
  Host    : $($env:COMPUTERNAME)
  User    : $($env:USERNAME)
  Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  PS Ver  : $($PSVersionTable.PSVersion)
================================================================================
"@
        Add-Content -Path $Script:LogFile -Value $header
        Write-Host $header -ForegroundColor Cyan
    }

    function Write-Log {
        param([string]$Message,
              [ValidateSet("INFO","SUCCESS","WARN","ERROR","SKIP","FAIL")]
              [string]$Level = "INFO")
        $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "[$ts] [$($Level.PadRight(7))] $Message"
        if ($Script:LogFile) { Add-Content -Path $Script:LogFile -Value $entry }
        $color = switch ($Level) {
            "SUCCESS" { "Green"   }
            "WARN"    { "Yellow"  }
            "ERROR"   { "Red"     }
            "FAIL"    { "Red"     }
            "SKIP"    { "Gray"    }
            default   { "White"   }
        }
        Write-Host $entry -ForegroundColor $color
    }

    function Close-Log {
        param([int]$Errors = 0, [int]$Warnings = 0, [int]$Skipped = 0)
        $footer = @"
================================================================================
  Completed : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Errors    : $Errors
  Warnings  : $Warnings
  Skipped   : $Skipped
  Log       : $Script:LogFile
================================================================================
"@
        if ($Script:LogFile) { Add-Content -Path $Script:LogFile -Value $footer }
        $col = if ($Errors -gt 0) { "Red" } elseif ($Warnings -gt 0) { "Yellow" } else { "Green" }
        Write-Host $footer -ForegroundColor $col
    }

    function Set-RegValue {
        param(
            [string]$Hive  = "HKLM",
            [string]$Path,
            [string]$Name,
            $Value,
            [string]$Type  = "DWORD"
        )
        $fullPath = "${Hive}:\$Path"
        try {
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -Force | Out-Null
                Write-Log "Created registry key: $fullPath" "INFO"
            }
            $before = try {
                (Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction Stop).$Name
            } catch { "<not set>" }
            Set-ItemProperty -Path $fullPath -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            $after = (Get-ItemProperty -Path $fullPath -Name $Name).$Name
            Write-Log "SET  $fullPath\$Name  [ $before -> $after ]  (Type: $Type)" "SUCCESS"
            return $true
        } catch {
            Write-Log "FAIL $fullPath\$Name  Error: $_" "ERROR"
            return $false
        }
    }

    function Set-ServiceConfig {
        param([string]$Name, [string]$StartupType, [bool]$StopNow = $false)
        try {
            $svc = Get-Service -Name $Name -ErrorAction Stop
            Set-Service  -Name $Name -StartupType $StartupType -ErrorAction Stop
            Write-Log "SERVICE $Name  StartupType -> $StartupType" "SUCCESS"
            if ($StopNow -and $svc.Status -eq "Running") {
                Stop-Service -Name $Name -Force -ErrorAction Stop
                Write-Log "SERVICE $Name  Stopped." "SUCCESS"
            }
            return $true
        } catch {
            Write-Log "FAIL SERVICE $Name  Error: $_" "ERROR"
            return $false
        }
    }

    function Add-FirewallRule {
        param(
            [string]$DisplayName,
            [string]$Protocol,
            [string]$LocalPort,
            [string]$Direction = "Inbound",
            [string]$Action    = "Allow",
            [string]$Profile   = "Any",
            [string]$Program   = $null
        )
        try {
            if (Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue) {
                Write-Log "SKIP Firewall rule '$DisplayName' already exists" "SKIP"
                return $true
            }
            $p = @{ DisplayName=$DisplayName; Protocol=$Protocol; LocalPort=$LocalPort
                    Direction=$Direction; Action=$Action; Profile=$Profile; Enabled="True" }
            if ($Program) { $p.Program = $Program }
            New-NetFirewallRule @p | Out-Null
            Write-Log "Firewall rule CREATED: $DisplayName ($Protocol $LocalPort $Direction)" "SUCCESS"
            return $true
        } catch {
            Write-Log "FAIL Firewall rule '$DisplayName'  Error: $_" "ERROR"
            return $false
        }
    }

    function Confirm-Prerequisites {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "ERROR: Must run as Administrator." -ForegroundColor Red; exit 1
        }
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Write-Host "ERROR: PowerShell 7+ required." -ForegroundColor Red; exit 1
        }
    }
    # ── end inline helpers ────────────────────────────────────────────────────
}

Confirm-Prerequisites
Initialize-Log "18_Blast_Display_Config"

$errors = 0; $warns = 0; $skipped = 0

# ── Parse resolution ──────────────────────────────────────────────────────────
$resParts  = $MaxResolutionPerMonitor -split 'x'
$resWidth  = [int]$resParts[0]
$resHeight = [int]$resParts[1]

# ── Registry paths ─────────────────────────────────────────────────────────────
# VMware legacy paths (Horizon < 2312 / pre-Omnissa rebrand)
$BLAST_CFG     = "SOFTWARE\VMware, Inc.\VMware Blast\Config"
$BLAST_POL     = "SOFTWARE\Policies\VMware, Inc.\VMware Blast\Config"
$AGENT_CFG     = "SOFTWARE\VMware, Inc.\VMware VDM\Agent\Configuration"
$AGENT_POL     = "SOFTWARE\Policies\VMware, Inc.\VMware VDM\Agent\Configuration"

# Omnissa paths (Horizon 2312+ / post-rebrand) — WRITE TO BOTH for version safety
$BLAST_CFG_OMN = "SOFTWARE\Omnissa\Horizon\Blast\Config"
$BLAST_POL_OMN = "SOFTWARE\Policies\Omnissa\Horizon\Blast\Config"
$AGENT_CFG_OMN = "SOFTWARE\Omnissa\Horizon\Agent\Configuration"
$AGENT_POL_OMN = "SOFTWARE\Policies\Omnissa\Horizon\Agent\Configuration"

# Consolidated arrays — every setting writes to all four (VMware legacy + Omnissa current)
$AllBlastPaths = @($BLAST_CFG, $BLAST_POL, $BLAST_CFG_OMN, $BLAST_POL_OMN)
$AllAgentPaths = @($AGENT_CFG, $AGENT_POL, $AGENT_CFG_OMN, $AGENT_POL_OMN)

Write-Log "=== Omnissa Horizon Blast Extreme Display Configuration ===" "INFO"
Write-Log "MaxFPS                  : $MaxFPS" "INFO"
Write-Log "MaxMonitors             : $MaxMonitors" "INFO"
Write-Log "MaxResolutionPerMonitor : $MaxResolutionPerMonitor ($resWidth x $resHeight)" "INFO"
Write-Log "EnableHEVC              : $EnableHEVC" "INFO"
Write-Log "EnableAV1               : $EnableAV1" "INFO"
Write-Log "EncoderQuality          : $EncoderQuality" "INFO"
Write-Log "ForceUDP                : $ForceUDP" "INFO"
Write-Log "EnableHighDPI           : $EnableHighDPI" "INFO"

# ══════════════════════════════════════════════════════════════════════════════
# 1. FRAME RATE — SCREEN REFRESH
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 1. Frame rate / screen refresh" "INFO"

# MaxFPS — the single most important Blast display setting.
# Default in Horizon is 30fps. Forces smooth scrolling, video playback,
# and CAC-inserted logon screen rendering.
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MaxFPS" -Value $MaxFPS)) { $errors++ }
}
Write-Log "MaxFPS = $MaxFPS fps" "SUCCESS"

# MinFPS — floor to prevent slideshow when network degrades
# Set to 15 minimum — below this Blast feels unusable
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MinFPS" -Value 15)) { $errors++ }
}
Write-Log "MinFPS = 15 fps (floor)" "SUCCESS"

# ══════════════════════════════════════════════════════════════════════════════
# 2. ENCODER CODEC SELECTION
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 2. Encoder codec selection (H.264 / HEVC / AV1)" "INFO"

# H.264 YUV 4:4:4 — ALWAYS enable.
# Default Blast uses H.264 YUV 4:2:0 — visible color fringing on coloured text,
# security classification banners, and fine UI elements.
# YUV 4:4:4 eliminates this entirely at a modest bandwidth increase (~15%).
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "H264YUV444Enabled" -Value 1)) { $errors++ }
}
Write-Log "H.264 YUV 4:4:4 enabled — crisp text and color rendering" "SUCCESS"

# H.264 base codec — must remain enabled as fallback
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AllowH264" -Value 1)) { $errors++ }
}

# HEVC (H.265) — better compression at same quality vs H.264.
# Recommended where GPU supports encode (most modern vSphere hosts with NVIDIA/AMD GPU)
$hevcVal = if ($EnableHEVC) { 1 } else { 0 }
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "HevcEnabled" -Value $hevcVal)) { $errors++ }
}
Write-Log "HEVC = $hevcVal $(if ($EnableHEVC) {'(enabled — better quality-to-bandwidth ratio)'} else {'(disabled)'})" "SUCCESS"

# AV1 — Horizon 2306+. Best compression but requires NVIDIA Ada Lovelace / Intel Arc
$av1Val = if ($EnableAV1) { 1 } else { 0 }
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AV1Enabled" -Value $av1Val)) { $warns++ }
}
Write-Log "AV1 = $av1Val $(if ($EnableAV1) {'(enabled — requires NVIDIA Ada/Lovelace GPU)'} else {'(disabled — enable for Ada/Arc GPU hosts)'})" "INFO"

# ══════════════════════════════════════════════════════════════════════════════
# 3. HARDWARE GPU ENCODER
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 3. Hardware GPU encoder" "INFO"

# Hardware encoding offloads the encode workload from CPU to GPU.
# Critical for high-FPS / high-resolution sessions or dense hosts.
# 0 = software encode (CPU), 1 = hardware encode (GPU preferred, CPU fallback)
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "HardwareEncoderEnabled" -Value 1)) { $errors++ }
}
Write-Log "Hardware GPU encoder enabled — encodes on GPU, falls back to CPU if no GPU" "SUCCESS"

# ══════════════════════════════════════════════════════════════════════════════
# 4. ENCODER QUALITY
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 4. Encoder quality level (0-9)" "INFO"

# Quality level controls the compression/quality tradeoff.
# 0 = maximum compression (low quality), 9 = maximum quality (high bandwidth)
# Default: 5 (balanced). Recommended for DoD/government: 8 (high quality)
# Especially important for legibility of classification banners and fine text.
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "EncoderQuality" -Value $EncoderQuality)) { $errors++ }
}
Write-Log "Encoder quality = $EncoderQuality/9" "SUCCESS"

# ══════════════════════════════════════════════════════════════════════════════
# 5. MULTI-MONITOR CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 5. Multi-monitor configuration" "INFO"

# Enable multi-monitor at the agent policy level
foreach ($path in $AllAgentPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AllowMultipleMonitor" -Value 1)) { $errors++ }
}
Write-Log "Multi-monitor: AllowMultipleMonitor = 1" "SUCCESS"

# Set maximum monitor count — ceiling for client requests
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MaxNumMonitors" -Value $MaxMonitors)) { $errors++ }
}
Write-Log "Max monitors = $MaxMonitors" "SUCCESS"

# Maximum resolution per monitor — applied per display
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MaxResolutionWidth"  -Value $resWidth))  { $errors++ }
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MaxResolutionHeight" -Value $resHeight)) { $errors++ }
}
Write-Log "Max resolution per monitor = ${resWidth}x${resHeight}" "SUCCESS"

# Total pixel limit — prevents excessive bandwidth on wide/multi-monitor setups
# Default is typically 4096x4096 aggregate, raise for multi-4K
$totalPixels = $resWidth * $resHeight * $MaxMonitors
Write-Log "Estimated total pixel budget = $totalPixels pixels ($MaxMonitors x ${resWidth}x${resHeight})" "INFO"

# ══════════════════════════════════════════════════════════════════════════════
# 6. RESOLUTION LOCKING — FORCE SPECIFIC DISPLAY MODE
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 6. Display mode and resolution forcing" "INFO"

# Lock Windows display scaling to 100% for consistent resolution behavior.
# DPI scaling at 125%+ can confuse Blast resolution negotiation and cause
# blurry rendering of the remote desktop even at correct resolution.
# Note: This sets a default — users with accessibility needs may need override.

if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Display" `
    -Name "DisableColorSpaceConversion" -Value 0)) { $warns++ }

# Prevent Windows from auto-adjusting display scaling on remote sessions
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Hardware Profiles\Current\Software\Fonts" `
    -Name "LogPixels" -Value 96)) { $warns++ }
Write-Log "Base DPI set to 96 (100% scaling) — prevents Blast DPI negotiation mismatch" "SUCCESS"

# Remove any stale Display1_DownScaleFactor entries that can force lower resolution
try {
    $monitorKeys = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" `
        -ErrorAction SilentlyContinue
    foreach ($key in $monitorKeys) {
        foreach ($subKey in Get-ChildItem $key.PSPath -ErrorAction SilentlyContinue) {
            $scaleFactor = Get-ItemProperty $subKey.PSPath -Name "Scaling" -ErrorAction SilentlyContinue
            if ($scaleFactor.Scaling -and $scaleFactor.Scaling -gt 1) {
                Write-Log "Found non-1x display scale factor at $($subKey.PSPath) — resetting to 1" "WARN"
                Set-ItemProperty $subKey.PSPath -Name "Scaling" -Value 1
                $warns++
            }
        }
    }
} catch { Write-Log "Display scale factor check skipped: $_" "INFO" }

# ══════════════════════════════════════════════════════════════════════════════
# 7. HIGH DPI / DISPLAY SCALING FOR BLAST
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 7. High-DPI display scaling" "INFO"

if ($EnableHighDPI) {
    # Enable DPI-aware Blast rendering — allows client HiDPI displays (4K laptops etc.)
    # to receive a properly scaled remote desktop without pixelation
    foreach ($path in $AllBlastPaths) {
        if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AllowHighColorAccuracy" -Value 1)) { $warns++ }
    }

    # Allow client-side DPI scaling override
    foreach ($path in $AllAgentPaths) {
        if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AllowHighDPI" -Value 1)) { $warns++ }
    }
    Write-Log "High-DPI scaling enabled for client-side 4K/HiDPI displays" "SUCCESS"
} else {
    Write-Log "SKIP: High-DPI disabled (EnableHighDPI = false)" "SKIP"
    $skipped++
}

# ══════════════════════════════════════════════════════════════════════════════
# 8. UDP TRANSPORT — REQUIRED FOR BLAST PERFORMANCE
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 8. UDP transport enforcement" "INFO"

# Blast Extreme REQUIRES UDP for optimal performance.
# TCP-only Blast is significantly degraded — higher latency, lower FPS, more artifacts.
# UDP 8443 (Blast over UDP) must be open through the network path.
# This sets the agent to prefer UDP with TCP fallback.

if ($ForceUDP) {
    foreach ($path in $AllBlastPaths) {
        if (-not (Set-RegValue -Hive HKLM -Path $path -Name "UDPEnabled" -Value 1)) { $errors++ }
    }
    Write-Log "UDP transport = enabled (required for full Blast performance)" "SUCCESS"
    Write-Log "Firewall rule for UDP 8443 verified in Section 12" "INFO"

    # Verify the Blast UDP firewall rule exists (should have been set in Section 12/13)
    $udpRule = Get-NetFirewallRule -DisplayName "*Blast*UDP*" -ErrorAction SilentlyContinue
    if ($udpRule) {
        Write-Log "Blast UDP firewall rule found: $($udpRule.DisplayName)" "SUCCESS"
    } else {
        Write-Log "Blast UDP firewall rule not found — adding now" "WARN"
        $warns++
        try {
            New-NetFirewallRule -DisplayName "Omnissa Blast UDP (VMware)" `
                -Direction Inbound -Protocol UDP -LocalPort 8443 `
                -Action Allow -Profile Any `
                -Description "Blast Extreme UDP transport for optimal VDI performance" `
                -ErrorAction Stop | Out-Null
            Write-Log "Blast UDP firewall rule created: UDP 8443 inbound" "SUCCESS"
        } catch {
            Write-Log "Could not create Blast UDP firewall rule: $_" "WARN"
            $warns++
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 9. ADAPTIVE QUALITY / NETWORK THROTTLE SETTINGS
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 9. Adaptive quality and network throttle" "INFO"

# Blast adapts quality based on network conditions by default.
# For LAN-connected VDI (on-prem Horizon connecting to on-prem endpoints),
# disable adaptive throttling to maintain consistent high quality.
# For WAN/remote users, leave adaptive enabled.

if ($DisableAdaptiveQuality) {
    foreach ($path in $AllBlastPaths) {
        if (-not (Set-RegValue -Hive HKLM -Path $path -Name "NetworkConditionDetectionEnabled" -Value 0)) { $warns++ }
    }
    Write-Log "Adaptive quality throttle DISABLED — consistent quality forced (LAN-only deployment)" "WARN"
    Write-Log "WARNING: Only appropriate if all clients are on LAN. WAN/VPN users will see degradation." "WARN"
    $warns++
} else {
    Write-Log "Adaptive quality throttle: ENABLED (default — adjusts for network conditions)" "SUCCESS"
    $skipped++
}

# Set bandwidth floor — Blast will not drop below this for quality preservation
# 10 Mbps minimum per session keeps quality acceptable on LAN
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "MinBandwidthInKbps" -Value 10000)) { $warns++ }
}
Write-Log "Minimum bandwidth floor = 10 Mbps per session" "SUCCESS"

# ══════════════════════════════════════════════════════════════════════════════
# 10. STILL IMAGE (JPEG/PNG) QUALITY
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 10. Still image / screen region quality" "INFO"

# Blast uses JPEG for moving regions and PNG for static regions.
# JPEG quality affects document text legibility when scrolling stops.
# 85-100 is appropriate for DoD use where security markings must be readable.
foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "JpegQuality"  -Value 85)) { $warns++ }
    if (-not (Set-RegValue -Hive HKLM -Path $path -Name "AllowPNG"     -Value 1))  { $warns++ }
}
Write-Log "JPEG quality = 85 / PNG enabled for static regions" "SUCCESS"

# ══════════════════════════════════════════════════════════════════════════════
# 11. VMWARE SVGA — VIRTUAL DISPLAY ADAPTER CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 11. VMware SVGA virtual display adapter" "INFO"

# The VMware SVGA3D virtual display adapter must support the requested resolution
# and monitor count. These settings are in the VM hardware configuration
# (ESXi/vSphere level) but we verify the driver is present and functional here.

$svgaDriver = Get-WmiObject -Class Win32_VideoController |
    Where-Object { $_.Name -match "VMware|SVGA|Omnissa|IDD" }
if ($svgaDriver) {
    Write-Log "VMware SVGA driver found: $($svgaDriver.Name)" "SUCCESS"
    Write-Log "Current display mode: $($svgaDriver.CurrentHorizontalResolution)x$($svgaDriver.CurrentVerticalResolution) @ $($svgaDriver.CurrentRefreshRate)Hz" "INFO"

    # Verify the driver can support the configured resolution
    $maxRes = $svgaDriver.MaxRefreshRate
    if ($maxRes) {
        Write-Log "Display adapter max refresh rate: $maxRes Hz" "INFO"
        if ($maxRes -lt $MaxFPS) {
            Write-Log "Driver max refresh rate ($maxRes Hz) is below configured MaxFPS ($MaxFPS) — Blast may cap at driver limit" "WARN"
            $warns++
        }
    }
} else {
    Write-Log "VMware SVGA driver NOT detected — image may not be running in a VMware VM" "WARN"
    $warns++
}

# ══════════════════════════════════════════════════════════════════════════════
# 12. DISPLAY CONFIGURATION SUMMARY AND VERIFICATION
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 12. Verification — reading back applied settings" "INFO"

# Prefer Omnissa path for verify readback — fallback to VMware legacy
$verifyPath = if (Test-Path "HKLM:\$BLAST_CFG_OMN") { "HKLM:\$BLAST_CFG_OMN" } else { "HKLM:\$BLAST_CFG" }
if (Test-Path $verifyPath) {
    $cfg = Get-ItemProperty $verifyPath -ErrorAction SilentlyContinue
    $verifyTable = [ordered]@{
        "MaxFPS"               = $cfg.MaxFPS
        "MinFPS"               = $cfg.MinFPS
        "H264YUV444Enabled"    = $cfg.H264YUV444Enabled
        "HevcEnabled"          = $cfg.HevcEnabled
        "AV1Enabled"           = $cfg.AV1Enabled
        "HardwareEncoderEnabled" = $cfg.HardwareEncoderEnabled
        "EncoderQuality"       = $cfg.EncoderQuality
        "MaxNumMonitors"       = $cfg.MaxNumMonitors
        "MaxResolutionWidth"   = $cfg.MaxResolutionWidth
        "MaxResolutionHeight"  = $cfg.MaxResolutionHeight
        "UDPEnabled"           = $cfg.UDPEnabled
        "JpegQuality"          = $cfg.JpegQuality
        "MinBandwidthInKbps"           = $cfg.MinBandwidthInKbps
        "PixelProviderForceViddCapture" = $cfg.PixelProviderForceViddCapture
    }
    Write-Log "Current Blast Config registry values:" "INFO"
    foreach ($key in $verifyTable.Keys) {
        $val = $verifyTable[$key]
        Write-Log "  $($key.PadRight(30)) = $(if ($null -eq $val) {'NOT SET'} else {$val})" "INFO"
    }
} else {
    Write-Log "Blast Config registry path not found — Horizon Agent may not be installed yet." "WARN"
    $warns++
}

# ══════════════════════════════════════════════════════════════════════════════
# 13. PIXEL PROVIDER — FORCE INDIRECT DISPLAY DRIVER (IDD) CAPTURE
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "--- 13. Pixel Provider — Force Indirect Display Driver (IDD) capture" "INFO"

# PixelProviderForceViddCapture = "1" (REG_SZ — must be a STRING, not DWORD)
#
# What this does:
#   Forces Blast to use the Indirect Display Driver (IDD/ViddCapture) capture
#   path instead of the 3D renderer path. The IDD path captures the display
#   output directly from the virtual display driver at the OS composition layer
#   rather than going through the DirectX/3D rendering pipeline.
#
# Why you want this:
#   On non-persistent VDI without a dedicated vGPU, the 3D renderer path can
#   introduce frame capture inconsistencies, especially during logon animation,
#   DEM profile load, and when the GPU pipeline is not fully initialized.
#   IDD capture is more deterministic — frames are captured regardless of 3D
#   renderer state, which eliminates the "black screen for 2-3 seconds after
#   logon" symptom common in non-persistent deployments.
#
#   For USAF/DoD environments with security classification banners that render
#   at logon, IDD capture ensures the banner is visible from the first frame.
#
# IMPORTANT — REG_SZ, not DWORD:
#   The value type MUST be REG_SZ (string "1") not DWORD (integer 1).
#   Setting this as a DWORD will be silently ignored by Blast.
#   This script uses -Type String to enforce the correct type.

Write-Log "Setting PixelProviderForceViddCapture = '1' (REG_SZ) on all Blast config paths" "INFO"

foreach ($path in $AllBlastPaths) {
    if (-not (Set-RegValue -Hive HKLM -Path $path `
        -Name "PixelProviderForceViddCapture" -Value "1" -Type String)) { $warns++ }
}
Write-Log "PixelProviderForceViddCapture = '1' [REG_SZ] — IDD capture forced, 3D renderer bypassed" "SUCCESS"

# Verify the type is correct — a common mistake is setting this as DWORD
foreach ($basePath in @("HKLM:\$BLAST_CFG_OMN", "HKLM:\$BLAST_CFG")) {
    if (Test-Path $basePath) {
        try {
            $regKey  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                ($basePath -replace "HKLM:\", "")
            )
            $valKind = $regKey.GetValueKind("PixelProviderForceViddCapture")
            if ($valKind -eq [Microsoft.Win32.RegistryValueKind]::String) {
                Write-Log "VERIFIED: $basePath\PixelProviderForceViddCapture type = REG_SZ (correct)" "SUCCESS"
            } else {
                Write-Log "TYPE MISMATCH at $basePath — value is $valKind, must be REG_SZ. Fixing..." "WARN"
                $warns++
                $regKey.Close()
                $rwKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    ($basePath -replace "HKLM:\", ""), $true
                )
                $rwKey.DeleteValue("PixelProviderForceViddCapture")
                $rwKey.SetValue("PixelProviderForceViddCapture", "1",
                    [Microsoft.Win32.RegistryValueKind]::String)
                $rwKey.Close()
                Write-Log "Fixed: re-written as REG_SZ" "SUCCESS"
            }
            $regKey.Close()
        } catch {
            Write-Log "Could not verify value type at ${basePath}: $_" "WARN"
            $warns++
        }
    }
}

Close-Log -Errors $errors -Warnings $warns -Skipped $skipped