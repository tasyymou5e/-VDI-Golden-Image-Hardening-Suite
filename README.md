# Build — GPO Hardening Scripts

Applies 17 core GPO hardening sections plus Blast display tuning to the Omnissa Horizon Windows 11 24H2 golden image. All scripts require PowerShell 7.0+ and local Administrator / SYSTEM privileges.

---

## Execution Order

### Step 1 — Master Runner (Sections 01–17)

```powershell
.\00_Master_RunAll.ps1
```

Runs all 17 core sections in sequence. Logs to `C:\VDI_GPO_Logs\`. Supports:

```powershell
.\00_Master_RunAll.ps1 -DryRun                      # Preview only — no changes
.\00_Master_RunAll.ps1 -SectionsToRun @(12,13,17)   # Run specific sections
```

### Step 2 — Blast Display Tuning (parameterized)

```powershell
# Standard dual 1080p workstation
.\18_Horizon_Blast_Display_Configuration.ps1 -MaxFPS 60 -MaxMonitors 2 -MaxResolutionPerMonitor "1920x1080"

# Analyst triple 1440p
.\18_Horizon_Blast_Display_Configuration.ps1 -MaxFPS 60 -MaxMonitors 3 -MaxResolutionPerMonitor "2560x1440"

# Single 4K with HEVC
.\18_Horizon_Blast_Display_Configuration.ps1 -MaxFPS 60 -MaxMonitors 1 -MaxResolutionPerMonitor "3840x2160" -EnableHEVC $true
```

### Step 3 — Pre-Seal Validation

```powershell
.\19_PreSeal_Validation.ps1           # Standard — WARNs are advisory
.\19_PreSeal_Validation.ps1 -StrictMode  # Strict — any WARN is a NO-GO
```

Returns **GO** or **NO-GO** with per-check detail. Only seal the image on GO.

---

## Environment Placeholders (fill before running)

| File | Variable | Replace with |
|---|---|---|
| `03_Microsoft_Teams.ps1` | `YOUR-TENANT-GUID-HERE` | Entra ID / Azure AD tenant GUID |
| `04_OneDrive_ForBusiness.ps1` | `YOUR-TENANT-GUID-HERE` | Entra ID / Azure AD tenant GUID |
| `05_FSLogix_OfficeContainer.ps1` | `\\YOUR-SERVER\FSLogix-ODFC` | FSLogix ODFC share UNC path |
| `06_DEM_ProfileManagement.ps1` | `\\YOUR-SERVER\DEM-Config` | DEM configuration share UNC path |
| `06_DEM_ProfileManagement.ps1` | `\\YOUR-SERVER\DEM-Archive` | DEM profile archive UNC path |
| `16_Network_OfflineFiles.ps1` | `YOUR-DOMAIN.com` | DNS search domain suffix(es) |

---

## Shared Library

**`Shared_Helpers.ps1`** — dot-sourced by every section script. Provides:

| Function | Purpose |
|---|---|
| `Initialize-Log` / `Write-Log` / `Close-Log` | Structured logging with timestamps and colour-coded console output |
| `Set-RegValue` | Create key path + set value, logs before/after, returns `$true`/`$false` |
| `Remove-RegValue` | Safely removes a registry value with skip-if-absent logic |
| `Set-ServiceConfig` | Sets startup type, optionally stops the service immediately |
| `Add-DefenderExclusion` | Wraps `Add-MpPreference` for paths, processes, and extensions |
| `Add-FirewallRule` | Creates a firewall rule with skip-if-exists guard |
| `Backup-RegistrySection` | `reg export` a key to `C:\VDI_GPO_Logs\reg_backup_<tag>_<ts>.reg` |
| `Test-RegValue` | Reads back a registry value and logs PASS/FAIL vs expected |
| `Get-OSEdition` | Returns `Enterprise`, `Education`, `Pro`, or `Other` |
| `Confirm-Prerequisites` | Exits with error if not running as Administrator or PS < 7.0 |

---

## Core Section Scripts (run by master runner)

| # | Script | What It Configures |
|---|---|---|
| 01 | `01_FirstRun_WelcomeSuppression.ps1` | Disables first-logon animation (Policy + Winlogon keys), OOBE/Consumer Features, Welcome Experience/Soft Landing, Edge first-run wizard + auto-import, Teams splash screen, feedback notifications |
| 02 | `02_Logon_Speed_Animation.ps1` | Disables logon background blur (Acrylic), startup sound, screen saver; enables SyncForegroundPolicy (wait for network); removes Teams from HKLM Run key; disables async logon scripts and ARSO |
| 03 | `03_Microsoft_Teams.ps1` | Disables auto-update (policy + direct key), enforces Entra tenant restriction, Outlook Meeting Add-in LoadBehavior=3 with resiliency policy, removes consumer Chat taskbar icon, disables GPU acceleration in Default User hive, configures Omnissa Virtualization Pack media optimization keys, suppresses first-launch |
| 04 | `04_OneDrive_ForBusiness.ps1` | Silent SSO (SilentAccountConfig), Files On-Demand (mandatory), AllowTenantList corporate restriction, disables personal sync + consumer OD client, blocks pre-logon network traffic, Enterprise update ring (4=Deferred), disables tutorial/first-run dialogs, enables sync health admin reports, conditional KFM (disabled when DEM folder redirection is active) |
| 05 | `05_FSLogix_OfficeContainer.ps1` | Verifies FSLogix agent + frxsvc Automatic; enables ODFC (VHDLocations, 30 GB VHDX default, UNC reachability + write permission test); include flags: Outlook=1, Teams=1, OneNote=1, OneDrive=0; Profile Container disabled; FlipFlopProfileDirectoryName=1; creates FSLogix ODFC Include/Exclude local security groups |
| 06 | `06_DEM_ProfileManagement.ps1` | Auto-detects DEM FlexEngine service name (wildcard match); sets service to Automatic; configures DEM Config Share + Archive UNC paths; enables DirectFlex for non-persistent sessions; enables build-validation logging; detects and warns on GPO Folder Redirection conflicts |
| 07 | `07_StartMenu_Taskbar.ps1` | Hides Recommended section (24H2), disables Widgets/News and Interests, disables consumer Teams Chat taskbar icon, disables Task View button, locks taskbar position, disables People bar |
| 08 | `08_Search_Cortana_AI.ps1` | Disables Cortana (including above-lock), Bing/web search (3 keys), Search Highlights, Windows Copilot, Windows Recall + snapshot saving (MANDATORY), Click to Do AI overlay (24H2), Windows Spotlight |
| 09 | `09_Privacy_Telemetry.ps1` | OS edition guard (AllowTelemetry=0 Enterprise/Education only, falls back to 1 on Pro); limits diagnostic log collection; disables Advertising ID; disables Activity History/Timeline (3 keys); disables Consumer Features + feedback notifications; stops DiagTrack + WerSvc services |
| 10 | `10_Notifications_ActionCenter.ps1` | Suppresses toast notifications on lock screen, disables tips/suggestions and Windows Spotlight soft-landing, blocks all application toasts (NoToastApplicationNotification=1), Action Center left enabled (Teams/OneDrive require system tray) |
| 11 | `11_WindowsUpdate_Patching.ps1` | Disables in-session auto-update (NoAutoUpdate + AUOptions=1), excludes driver updates, blocks Windows Update UI, disables Teams in-session auto-update, sets OneDrive to Enterprise update ring, prevents autonomous WU service firing |
| 12 | `12_Security_Defender.ps1` | Defender path + process exclusions via cmdlet AND registry fallback (MDE-managed environments); disables SMBv1 (server, client, DISM feature removal); disables Remote Registry; Horizon firewall rules (PCoIP TCP/UDP 4172, Blast TCP 443/8443, Blast UDP 8443, USB TCP 32111, MMR TCP 9427); Teams media optimization STUN firewall rules (UDP 3478–3481); STIG/CIS hardening: NTLMv2 level 5, RestrictAnonymousSAM/RestrictAnonymous=1, SMB signing required, RDP SecurityLayer=2 |
| 13 | `13_Horizon_Specific.ps1` | Disables screen saver, sets High Performance power plan, disables hibernate, ensures NLA Automatic, disables Remote Assistance; Blast codec base settings (H.264/H.264 YUV 4:4:4/HEVC, MaxFPS=60) written to all four VMware/Omnissa registry paths; QoS DSCP EF(46) marking for Blast TCP/UDP 8443 and PCoIP TCP/UDP 4172 |
| 14 | `14_Power_Performance.ps1` | Activates High Performance power plan (GUID-based with verification), disables hibernate, zeroes standby/monitor/disk timeouts, disables USB selective suspend on AC+DC (prevents CAC reader dropout), sets CPU min/max performance state to 100% |
| 15 | `15_Services.ps1` | **Disable:** XblAuthManager, XblGameSave, XboxNetApiSvc, XboxGipSvc (Xbox), SysMain (Superfetch), WerSvc (Error Reporting), DPS (Diagnostic Policy), WaaSMedicSvc via registry (protected service), conditional WSearch + Spooler. **Set Automatic:** SCardSvr, ScDeviceEnum, frxsvc, DEM service (auto-detected by DisplayName), NlaSvc |
| 16 | `16_Network_OfflineFiles.ps1` | Disables Offline Files/CSC, WPAD auto-proxy (Internet Settings + Wpad subkey), configures DNS search suffix list with placeholder validation, ensures NlaSvc Automatic, conditional IPv6 disable, verifies SMBv2 is enabled |
| 17 | `17_SmartCard_CAC_Login.ps1` | Sets SCardSvr + ScDeviceEnum Automatic; PKINIT Kerberos (UseGenericKerberosForSmartCardLogon=0); enables Smart Card credential provider; disables Windows Hello for Business + PIN logon; auto-detects ActivClient (HID Global and ActivIdentity registry paths); PIN caching 900s; DoD PIV mapping (ForceReadingAllCertificates, StrongCertificateBindingEnforcement=1); Horizon True SSO (TrueSSO=1, TrueSSO-Logging=1); imports HKLM.cred.providors.reg if present; verifies DoD Root CA certificates in LocalMachine\Root |

---

## Additional Scripts (run after master runner, in order)

### `18_Horizon_Blast_Display_Configuration.ps1`

Full parameterized Blast Extreme display configuration. Self-bootstrapping — runs standalone without the rest of the suite.

| Parameter | Default | Description |
|---|---|---|
| `-MaxFPS` | `60` | Frame rate cap (15–60). Lower for CPU-constrained dense hosts. |
| `-MaxMonitors` | `4` | Maximum monitors per session (1–9) |
| `-MaxResolutionPerMonitor` | `"3840x2160"` | Per-monitor resolution ceiling |
| `-EnableHEVC` | `$true` | HEVC (H.265) — better quality-to-bandwidth. Requires GPU encode support. |
| `-EnableAV1` | `$false` | AV1 — best compression, requires NVIDIA Ada / Intel Arc GPU |
| `-EncoderQuality` | `8` | Quality 0–9 (5=balanced, 8=high, 9=near-lossless) |
| `-ForceUDP` | `$true` | UDP 8443 required for full Blast performance |
| `-EnableHighDPI` | `$true` | Client-side HiDPI/4K display scaling support |
| `-DisableAdaptiveQuality` | `$false` | Set `$true` for LAN-only deployments to prevent quality throttle |

Settings are written to all four registry paths: VMware legacy (`SOFTWARE\VMware, Inc.\VMware Blast\Config`) and current Omnissa paths for forward/backward compatibility.

Also sets `PixelProviderForceViddCapture = "1"` (REG_SZ) to force IDD pixel capture, eliminating the black-screen-at-logon symptom common in non-persistent deployments.

### `19_PreSeal_Validation.ps1`

20-point GO / NO-GO sealing readiness check. Run immediately before snapshotting the golden image.

**Checks performed:**

| # | Check | Critical? |
|---|---|---|
| 1 | No stale user profiles under `C:\Users\` | Yes |
| 2 | Windows event logs cleared | Warn |
| 3 | Temp directories empty (`C:\Windows\Temp`, `C:\Temp`) | Warn |
| 4 | All 17 section log files present in `C:\VDI_GPO_Logs\` | Yes |
| 5 | SCardSvr, NlaSvc, Netlogon Automatic; SysMain, WSearch, Xbox Disabled | Mixed |
| 5b | DEM FlexEngine auto-detected and Automatic | Warn |
| 5c | Horizon Agent service present and Automatic | Yes |
| 6 | `DisablePasswordChange = 1` (machine password rotation disabled) | Yes |
| 7 | No pending Windows Update / CBS reboot flag | Yes |
| 8 | FSLogix ODFC Enabled=1; Profile Container Enabled=0 | Yes |
| 9 | Default user AppData clean (no orphaned build-time installs) | Warn |
| 10 | DoD Root CA certificates present in LocalMachine\Root | Yes |
| 11 | SMBv1 disabled | Yes |
| 12 | High Performance power plan active | Warn |
| 13 | Hibernation disabled | Warn |
| 14 | Screen saver suppressed | Warn |
| 15 | Windows Hello for Business disabled | Warn |
| 16–20 | Telemetry policy set, OneDrive SSO, True SSO, Recall disabled, Teams no auto-update | Warn |

---

## Maintenance Tools

### `Rollback-Section.ps1`

Restores the registry state of a specific section using pre-build `reg export` backup files. Useful when a section breaks something and you need to undo it without a full image rebuild.

```powershell
.\Rollback-Section.ps1 -ListBackups             # Show all available backup files
.\Rollback-Section.ps1 -Section 12              # Roll back Section 12 (most recent backup)
.\Rollback-Section.ps1 -Section 12 -DryRun      # Preview without executing
.\Rollback-Section.ps1 -BackupFile "C:\VDI_GPO_Logs\reg_backup_12_20260521_143022.reg"
```

**Important:** Rolls back registry changes only. Does not reverse service startup type changes, DISM feature removals, or file operations.

Backup files (`reg_backup_<tag>_<timestamp>.reg`) are created by `Backup-RegistrySection` in `Shared_Helpers.ps1`. A safety snapshot of the current registry state is taken automatically before each rollback.

---

## Other Files

| File | Notes |
|---|---|
| `HKLM.cred.providors.reg` | Credential provider lock-down registry file (Smart Card priority, Hello/NGC suppressed). Applied automatically by `17_SmartCard_CAC_Login.ps1` if present in this folder; otherwise apply manually: `reg import HKLM.cred.providors.reg` |
| `New folder\` | Archived `.txt` draft copies of scripts that have since been superseded — **not for production use** |
