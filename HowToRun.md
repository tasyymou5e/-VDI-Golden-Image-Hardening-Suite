# Omnissa Horizon VDI Golden Image Hardening Suite — How To Run

---

## Executive Summary

This suite is a **PowerShell automation framework** that hardens a **Windows 11 Enterprise 24H2** virtual machine into a production-ready, non-persistent **Omnissa Horizon** (formerly VMware Horizon) VDI golden image. It applies security hardening, performance optimization, user experience tuning, and enterprise application integration in a single automated pass — replacing manual Group Policy Object (GPO) configuration.

The suite runs **17 sequential hardening sections** via a master orchestrator script, then validates the image is ready to seal with a 20-point GO/NO-GO audit. It is designed to be executed during an image build pipeline (MDT, SCCM, Packer, or manual) as the **SYSTEM** or **Local Administrator** account before snapshotting.

**Key outcomes after a successful run:**

- Logon experience is clean and fast (no OOBE, animations, splash screens)
- Windows Recall, Cortana, Copilot, telemetry, and Bing search are disabled (data protection)
- SMBv1 disabled; NTLMv2 enforced; SMB signing required; RDP hardened (STIG/CIS compliance)
- Horizon Blast/PCoIP firewall rules open; Blast codec tuned for performance
- FSLogix Office Data Container (ODFC) configured for Office/Teams profile persistence
- OneDrive for Business silently SSO'd with corporate tenant restrictions
- Microsoft Teams configured for VDI media optimization (Omnissa Virtualization Pack)
- Smart Card / CAC authentication ready (DoD PIV mapping, True SSO, DoD Root CAs)
- Xbox, SysMain, Windows Update (in-session), and other unnecessary services disabled
- All changes logged to `C:\VDI_GPO_Logs\` for audit and troubleshooting

---

## Prerequisites

### Infrastructure Requirements

Before running any scripts, the following infrastructure must be in place and reachable from the golden image VM:

| Requirement | Details |
|-------------|---------|
| **FSLogix Agent** | Installed on the image; `frxsvc` service must be present |
| **FSLogix Share** | UNC path for ODFC VHDXs (e.g., `\\fileserver\FSLogix-ODFC`) — replace placeholder in Section 05 |
| **DEM FlexEngine** | Installed if using VMware Dynamic Environment Manager; `FlexEngine` service must be present |
| **DEM Config Share** | UNC path (e.g., `\\fileserver\DEM-Config`) — replace placeholder in Section 06 |
| **DEM Archive Share** | UNC path (e.g., `\\fileserver\DEM-Archive`) — replace placeholder in Section 06 |
| **Omnissa Horizon Agent** | Installed on the image before running this suite |
| **Microsoft Teams** | Machine-wide MSIX (Teams 2.x) installed |
| **OneDrive for Business** | Per-machine OneDrive installed |
| **Active Directory** | Machine joined to domain; NlaSvc functional |
| **Smart Card (if used)** | ActivClient or equivalent middleware installed; DoD Root CAs present |
| **Horizon True SSO (if used)** | Enrollment Server configured in the Horizon environment |

### Machine Requirements

| Requirement | Minimum |
|-------------|---------|
| OS | Windows 11 **Enterprise** Edition 24H2 (build 26100+) |
| PowerShell | **7.0 or later** (`pwsh.exe`) — Windows PowerShell 5.1 is **not supported** |
| Account | Local **Administrator** or **SYSTEM** |
| Disk space | 500 MB free on C:\ (logs + registry backups) |
| Network | Reachable to FSLogix, DEM, and domain shares during build |

### Placeholder Values to Replace Before Running

Open each file listed below and substitute the placeholder strings with your environment's values. Refer to `info.for.environment.txt` for the full checklist.

| Script | Placeholder | Replace With |
|--------|-------------|--------------|
| `03_Microsoft_Teams.ps1` | `YOUR-TENANT-GUID` | Your Entra ID (Azure AD) tenant GUID |
| `04_OneDrive_ForBusiness.ps1` | `YOUR-TENANT-GUID` | Your Entra ID tenant GUID |
| `05_FSLogix_OfficeContainer.ps1` | `\\YOUR-SERVER\FSLogix-ODFC` | Your FSLogix ODFC share UNC path |
| `06_DEM_ProfileManagement.ps1` | `\\YOUR-SERVER\DEM-Config` | Your DEM Config share UNC path |
| `06_DEM_ProfileManagement.ps1` | `\\YOUR-SERVER\DEM-Archive` | Your DEM Archive share UNC path |
| `16_Network_OfflineFiles.ps1` | `YOUR-DOMAIN.com` | Your primary DNS search domain |

> **Warning:** Running scripts with unreplaced placeholders will result in misconfigured applications and failed validation checks.

---

## What Each Section Does

### Section 01 — First Run & Welcome Suppression
**Script:** `01_FirstRun_WelcomeSuppression.ps1`

Eliminates all first-logon noise that appears to users on a fresh non-persistent desktop:
- Disables the first-logon animation ("Getting things ready...")
- Suppresses OOBE (Out-of-Box Experience) screens
- Disables Microsoft Edge first-run wizard and import prompts
- Removes Teams splash/loading screens
- Blocks Windows feedback and consumer feature prompts

---

### Section 02 — Logon Speed & Animation
**Script:** `02_Logon_Speed_Animation.ps1`

Speeds up the logon process and ensures Group Policy applies correctly:
- Disables logon screen blur (Acrylic effect)
- Removes Windows startup sounds
- Removes Teams from the Run key (prevents background Teams launch at logon)
- Enables synchronous foreground Group Policy processing (ensures GPO applies before desktop appears)
- Disables Automatic Restart Sign-On (ARSO) — prevents auto-logon after updates, which is unsafe in VDI

---

### Section 03 — Microsoft Teams
**Script:** `03_Microsoft_Teams.ps1`

Configures Teams 2.x for a managed, VDI-optimized deployment:
- Disables Teams auto-update (version controlled via golden image)
- Applies Entra ID tenant restrictions (blocks personal/consumer accounts)
- Sets Outlook Meeting Add-in `LoadBehavior=3` (always-on, no user override)
- Removes consumer Teams Chat icon from taskbar/system
- Disables Teams GPU hardware acceleration (reduces resource contention in VDI)
- Configures Omnissa Virtualization Pack registry keys for media optimization
- Enables Teams media offload (audio/video processed on endpoint, not in the VM)

---

### Section 04 — OneDrive for Business
**Script:** `04_OneDrive_ForBusiness.ps1`

Configures OneDrive for silent, managed enterprise operation:
- Enables Silent Account Configuration (SSO using Windows credentials — no user sign-in prompt)
- Forces Files On-Demand (content stays in cloud; only placeholders on disk)
- Restricts sync to corporate tenant only (blocks personal OneDrive accounts)
- Disables personal OneDrive sync entirely
- Sets enterprise update ring (Deferred) to avoid unexpected client updates
- Configures Known Folder Move (Desktop/Documents/Pictures redirect to OneDrive) if enabled

---

### Section 05 — FSLogix Office Data Container (ODFC)
**Script:** `05_FSLogix_OfficeContainer.ps1`

Configures FSLogix to store Office application data (Outlook cache, Teams data, OneNote) in a VHDX on a file share — essential for non-persistent VDI where local data is lost at logoff:
- Verifies FSLogix agent is installed (`frxsvc` service present)
- Enables Office Data Container (ODFC) mode with a 30 GB maximum VHDX size
- Configures inclusion of Outlook, Teams, and OneNote profile data in the container
- Disables FSLogix Profile Container (ODFC-only mode, assuming DEM handles full profile)
- Creates FSLogix local security groups (`FSLogix ODFC Include` / `Exclude`)
- Validates the ODFC UNC share is reachable before applying configuration

---

### Section 06 — DEM Profile Management
**Script:** `06_DEM_ProfileManagement.ps1`

Configures VMware Dynamic Environment Manager (DEM) FlexEngine for user persona management in non-persistent VDI:
- Auto-detects the DEM FlexEngine service name
- Sets Config Share path (where DEM policy files are stored)
- Sets Archive Share path (where captured user settings are stored)
- Enables DirectFlex mode (settings applied on-demand at app launch, not all at logon)
- Detects and warns if conflicting GPO-based folder redirection is configured

---

### Section 07 — Start Menu & Taskbar
**Script:** `07_StartMenu_Taskbar.ps1`

Simplifies and locks down the Windows 11 24H2 Start Menu and Taskbar for a clean VDI experience:
- Hides the "Recommended" section in Start Menu (24H2-specific registry key)
- Disables Widgets and News & Interests panel
- Removes the Teams Chat icon from the taskbar
- Disables Task View button on taskbar
- Locks taskbar configuration (prevents user customization)

---

### Section 08 — Search, Cortana & AI Features
**Script:** `08_Search_Cortana_AI.ps1`

Disables AI and cloud-connected search features for privacy and resource conservation:
- Disables Cortana (above-lock and in-session)
- Disables Bing web search in Start Menu
- Disables Windows Copilot AI assistant
- **Disables Windows Recall and snapshot saving** *(mandatory — data protection compliance)*
- Disables "Click to Do" AI feature
- Disables Windows Spotlight (rotating lock screen content from Microsoft)

---

### Section 09 — Privacy & Telemetry
**Script:** `09_Privacy_Telemetry.ps1`

Minimizes data collection sent to Microsoft — edition-aware to stay within supported policy:
- Sets `AllowTelemetry=0` (Security level) for Enterprise and Education editions
- Falls back to `AllowTelemetry=1` (Basic) for Pro edition (Microsoft does not support 0 on Pro)
- Disables Activity History (prevents local and cloud activity recording)
- Disables Consumer Features (app suggestions, tips, third-party app installs)
- Stops and disables `DiagTrack` (Connected User Experiences and Telemetry) service
- Stops and disables `WerSvc` (Windows Error Reporting) service

---

### Section 10 — Notifications & Action Center
**Script:** `10_Notifications_ActionCenter.ps1`

Suppresses all non-essential notifications that distract users and pollute the VDI session:
- Disables toast notifications on the lock screen
- Disables Windows tips, tricks, and suggestions
- Blocks all application toast notifications (`NoToastApplicationNotification=1`)
- Preserves system tray and critical system notifications

---

### Section 11 — Windows Update & Patching
**Script:** `11_WindowsUpdate_Patching.ps1`

Prevents Windows Update from running inside an active VDI session — updates are applied to the golden image during scheduled rebuild cycles, not pushed to live sessions:
- Disables automatic update downloads and installs (`NoAutoUpdate=1`, `AUOptions=1`)
- Excludes driver updates from Windows Update
- Blocks access to the Windows Update user interface
- Disables Teams auto-update mechanism
- Disables OneDrive auto-update mechanism

---

### Section 12 — Security & Windows Defender
**Script:** `12_Security_Defender.ps1`

The largest security hardening section — applies defense-in-depth across multiple layers:

**Defender Exclusions (performance):**
- Adds path exclusions for FSLogix VHDX mount points, OneDrive sync folders, and Teams cache

**Network Protocol Hardening:**
- Disables SMBv1 server and client (via registry and DISM feature removal)
- Requires SMB signing on all connections

**Services:**
- Disables Remote Registry service

**Firewall Rules (Horizon protocols):**
- Opens inbound rules for PCoIP (UDP 4172, TCP 4172), Blast Extreme (TCP/UDP 8443, TCP 443), USB redirection (TCP 32111), Multimedia Redirection (TCP 9427)
- Opens Teams STUN/TURN rules for media offload

**STIG/CIS Authentication Hardening:**
- Sets LAN Manager Authentication Level to 5 (NTLMv2 only — refuse LM and NTLM)
- Sets RDP `SecurityLayer=2` (Network Level Authentication required)
- Disables `LmCompatibilityLevel` downgrade attacks

---

### Section 13 — Horizon-Specific Settings
**Script:** `13_Horizon_Specific.ps1`

Applies Horizon-specific performance and protocol tuning directly to registry paths used by the Horizon Agent:
- Activates the High Performance power plan
- Disables hibernation
- Configures Blast Extreme codec baseline: H.264 primary, HEVC secondary, MaxFPS=60
- Marks H.264 YUV 4:4:4 chroma sampling enabled (higher color fidelity)
- Sets QoS DSCP marking to Expedited Forwarding (EF, DSCP 46) for Blast traffic priority on managed networks

---

### Section 14 — Power & Performance
**Script:** `14_Power_Performance.ps1`

Ensures the VM always operates at maximum performance with no idle power-saving behavior:
- Activates the High Performance power plan using its fixed GUID (`8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`)
- Disables hibernate (`powercfg /h off`)
- Sets monitor timeout to 0 (never turn off display)
- Sets standby/sleep timeout to 0 (never sleep)
- Sets disk timeout to 0 (never spin down)
- Disables USB selective suspend on both AC and DC power
- Sets minimum and maximum processor performance state to 100%

---

### Section 15 — Services
**Script:** `15_Services.ps1`

Right-sizes the Windows service footprint — disabling unnecessary services and ensuring required ones are always running:

**Disabled (Startup Type = Disabled):**
- `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`, `XboxGipSvc` — Xbox services (no gaming in VDI)
- `SysMain` (Superfetch) — unnecessary prefetching in non-persistent VDI
- `WerSvc` — Windows Error Reporting
- `DPS` — Diagnostic Policy Service
- `WaaSMedicSvc` — Windows Update Medic Service (prevents WU self-repair)

**Set Automatic (required for VDI operation):**
- `SCardSvr` — Smart Card service
- `ScDeviceEnum` — Smart Card Device Enumeration
- `frxsvc` — FSLogix Agent
- `NlaSvc` — Network Location Awareness (required for GPO and domain auth)
- DEM FlexEngine service (auto-detected by name)

---

### Section 16 — Network & Offline Files
**Script:** `16_Network_OfflineFiles.ps1`

Configures networking for a managed VDI environment and disables features incompatible with non-persistent operation:
- Disables Offline Files / Client-Side Caching (CSC) — incompatible with non-persistent VDI; causes profile bloat
- Disables WPAD (Web Proxy Auto-Discovery) — prevents unauthenticated proxy discovery attacks
- Configures DNS suffix search list for the corporate domain
- Ensures NlaSvc is set to Automatic
- Conditionally disables IPv6 if not required in the environment
- Verifies SMBv2 is enabled (required for file share access)

---

### Section 17 — Smart Card & CAC Login
**Script:** `17_SmartCard_CAC_Login.ps1`

Configures the image for Common Access Card (CAC) / Smart Card authentication — required for DoD and federal environments:
- Sets `SCardSvr` and `ScDeviceEnum` to Automatic start
- Enforces PKINIT Kerberos (certificate-based authentication)
- Enables the Smart Card credential provider
- Disables Windows Hello for Business (PIN/biometric — Smart Card is the required method)
- Auto-detects ActivClient middleware installation and applies compatibility settings
- Configures PIN caching (900-second timeout)
- Applies DoD PIV card mapping (subject-to-UPN mapping)
- Enables Horizon True SSO (certificate passed through to Horizon Broker for seamless logon)
- Verifies DoD Root CA certificates are present in the machine store

---

## Optional Post-Section Scripts

### Section 18 — Horizon Blast Display Configuration
**Script:** `18_Horizon_Blast_Display_Configuration.ps1`

Run separately after the main 17 sections to tune display settings per workload type. This script is self-bootstrapping and parameterized — run it once per target resolution/workload profile.

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-MaxFPS` | `60` | Maximum frames per second (15–60) |
| `-MaxMonitors` | `2` | Maximum monitors per session (1–9) |
| `-MaxResolutionPerMonitor` | `1920x1080` | Maximum resolution per monitor |
| `-EnableHEVC` | `$true` | Enable HEVC (H.265) codec |
| `-EnableAV1` | `$false` | Enable AV1 codec (requires Horizon 8.x) |
| `-EncoderQuality` | `5` | Encoder quality (0=lowest, 9=highest) |
| `-ForceUDP` | `$true` | Force UDP transport for Blast |
| `-EnableHiDPI` | `$false` | Enable HiDPI/Retina display support |

**Example — Standard 1080p:**
```powershell
pwsh -ExecutionPolicy Bypass -File ".\18_Horizon_Blast_Display_Configuration.ps1" -MaxFPS 60 -MaxMonitors 2 -MaxResolutionPerMonitor "1920x1080"
```

**Example — High-Resolution Knowledge Worker:**
```powershell
pwsh -ExecutionPolicy Bypass -File ".\18_Horizon_Blast_Display_Configuration.ps1" -MaxFPS 60 -MaxMonitors 3 -MaxResolutionPerMonitor "2560x1440" -EnableHEVC $true -EnableHiDPI $true
```

---

### Section 19 — Pre-Seal Validation
**Script:** `19_PreSeal_Validation.ps1`

Run this after all sections complete and before taking the golden image snapshot. It performs a 20-point audit and returns a GO or NO-GO result.

**Checks include:**
- No temporary or orphaned user profiles
- Event logs cleared
- Temp directories empty
- All 17 section log files present in `C:\VDI_GPO_Logs\`
- Critical service startup types correct
- Machine password rotation disabled
- No pending Windows Updates
- FSLogix ODFC configured
- Horizon Agent installed
- DoD Root CAs present
- SMBv1 disabled
- High Performance power plan active
- Hibernation disabled
- Screen saver disabled
- Hello for Business disabled
- Telemetry policy applied
- True SSO configured
- Windows Recall disabled

**Run:**
```powershell
pwsh -ExecutionPolicy Bypass -File ".\19_PreSeal_Validation.ps1"
```

**Strict mode** (treats warnings as failures):
```powershell
pwsh -ExecutionPolicy Bypass -File ".\19_PreSeal_Validation.ps1" -Strict
```

---

## How To Run

### Step 1 — Prepare the Environment

1. Deploy a clean **Windows 11 Enterprise 24H2** VM in your Horizon environment.
2. Install all required software: Horizon Agent, FSLogix, DEM FlexEngine, Teams (machine-wide MSIX), OneDrive (per-machine), ActivClient (if using CAC).
3. Join the machine to your Active Directory domain.
4. Copy the entire `Build\` folder to the VM (e.g., `C:\Build\`).
5. **Replace all placeholder values** in the scripts listed in the Prerequisites section above.

### Step 2 — Open an Elevated PowerShell 7 Session

```powershell
# Verify you are running PS 7+
$PSVersionTable.PSVersion

# Verify you are running as Administrator
[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### Step 3 — Run All Sections (Recommended)

Navigate to the Build folder and run the master orchestrator:

```powershell
cd C:\Build
pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1"
```

**Dry-run first (preview without applying changes):**
```powershell
pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1" -DryRun
```

**Run specific sections only:**
```powershell
pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1" -SectionsToRun @(1,2,7,8,9)
```

### Step 4 — Run Optional Display Tuning

```powershell
pwsh -ExecutionPolicy Bypass -File ".\18_Horizon_Blast_Display_Configuration.ps1" -MaxFPS 60 -MaxMonitors 2
```

### Step 5 — Run Pre-Seal Validation

```powershell
pwsh -ExecutionPolicy Bypass -File ".\19_PreSeal_Validation.ps1"
```

Review the output:
- **GO** — All checks passed. Safe to seal the image.
- **NO-GO** — One or more checks failed. Review the output for remediation hints, fix the issue, and re-run validation before sealing.

### Step 6 — Seal the Golden Image

Once `19_PreSeal_Validation.ps1` returns GO:
1. Run Sysprep or your image capture tool as required by your deployment pipeline
2. Snapshot the VM in vCenter
3. Update the Horizon Desktop Pool to use the new snapshot
4. Test a linked-clone session before rolling out to production pools

---

## Logs

All section logs are written to `C:\VDI_GPO_Logs\`:

| File | Contents |
|------|---------|
| `<SectionName>.log` | Per-section timestamped log (created by each script) |
| `MasterRun_<timestamp>.log` | Master orchestrator summary log |
| `PreSeal_Validation_<timestamp>.log` | Validation audit results |

Retain these logs as evidence for change management and compliance audits.

---

## Rollback a Section

If a section causes an issue, restore its registry state using the rollback script:

```powershell
# List available backups
pwsh -ExecutionPolicy Bypass -File ".\Rollback-Section.ps1" -ListBackups

# Roll back Section 12 (most recent backup)
pwsh -ExecutionPolicy Bypass -File ".\Rollback-Section.ps1" -Section 12

# Roll back to a specific backup timestamp
pwsh -ExecutionPolicy Bypass -File ".\Rollback-Section.ps1" -Section 12 -BackupTimestamp "20250601-143000"

# Preview what would be restored (dry-run)
pwsh -ExecutionPolicy Bypass -File ".\Rollback-Section.ps1" -Section 12 -DryRun
```

> **Note:** Rollback restores registry values only. Service startup type changes, DISM feature removals (e.g., SMBv1), and file system changes are **not** reversed.

---

## Quick Reference

| Task | Command |
|------|---------|
| Run everything | `pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1"` |
| Dry-run preview | `pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1" -DryRun` |
| Run specific sections | `pwsh -ExecutionPolicy Bypass -File ".\00_Master_RunAll.ps1" -SectionsToRun @(1,3,12)` |
| Run one section | `pwsh -ExecutionPolicy Bypass -File ".\12_Security_Defender.ps1"` |
| Display tuning | `pwsh -ExecutionPolicy Bypass -File ".\18_Horizon_Blast_Display_Configuration.ps1"` |
| Pre-seal validation | `pwsh -ExecutionPolicy Bypass -File ".\19_PreSeal_Validation.ps1"` |
| Rollback a section | `pwsh -ExecutionPolicy Bypass -File ".\Rollback-Section.ps1" -Section <N>` |
| View logs | `Get-ChildItem C:\VDI_GPO_Logs\` |
