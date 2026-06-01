#Requires -Version 7.0
<#
.SYNOPSIS  Section 17 — Smart Card / CAC Seamless Login
.NOTES
    Log : C:\VDI_GPO_Logs\17_SmartCard_CAC_Login.log
    Configures CAC/PIV Smart Card credential provider for Horizon True SSO
    and seamless CAC logon in non-persistent VDI sessions.

    Prerequisites:
      - ActivClient (or DoD-approved CAC middleware) installed
      - DoD root and intermediate CA certificates in the machine certificate store
      - Horizon True SSO Enrollment Servers configured on the Connection Server
      - HKLM.cred.providors.reg reviewed and applied if needed

    This script does NOT replace Horizon True SSO infrastructure configuration.
    It configures the CLIENT (golden image) side only.

    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "17_SmartCard_CAC_Login"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Smart Card / CAC Login for Horizon VDI ===" "INFO"

# ── 1. Smart Card services — must be Automatic for CAC to function ─────────────
Write-Log "--- 1. Set Smart Card services to Automatic start" "INFO"
foreach ($svc in @("SCardSvr","ScDeviceEnum")) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $s) {
        if (-not (Set-ServiceConfig -Name $svc -StartupType Automatic)) { $errors++ }
    } else {
        Write-Log "WARNING: $svc not found — Smart Card functionality may be unavailable." "WARN"; $warns++
    }
}

# ── 2. Smart Card PKINIT / Kerberos configuration ──────────────────────────────
Write-Log "--- 2. Configure PKINIT for certificate-based Kerberos authentication" "INFO"
# These settings ensure Windows can use the PIV/CAC certificate for Kerberos TGT requests
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" `
    -Name "UseGenericKerberosForSmartCardLogon" -Value 0)) { $warns++ }

# Disable fallback to password (force CAC-only in environments that require it)
# Note: Set to 1 if password fallback is required for break-glass accounts
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\SmartCardCredentialProvider" `
    -Name "X509HintsNeeded" -Value 1)) { $warns++ }

# ── 3. Credential provider ordering — prefer Smart Card ───────────────────────
Write-Log "--- 3. Configure credential provider ordering" "INFO"

# Enable Smart Card credential provider
$scProviderGuid = "{8FD7E19C-3BF7-489B-A72C-846AB3678C96}"
Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$scProviderGuid" `
    -Name "(Default)" -Value "Smart Card" -Type String | Out-Null

# Disable Windows Hello for Business in VDI (conflicts with CAC; Hello requires TPM)
Write-Log "    Disabling Windows Hello for Business (not applicable in VDI)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\PassportForWork" `
    -Name "Enabled" -Value 0)) { $warns++ }

# Disable PIN credential provider (Hello PIN — VDI uses CAC)
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "AllowDomainPINLogon" -Value 0)) { $warns++ }

# ── 4. ActivClient integration (DoD CAC middleware) ───────────────────────────
Write-Log "--- 4. Apply ActivClient VDI registry settings" "INFO"

# Check if ActivClient is installed
$acReg = "HKLM:\SOFTWARE\HID Global\ActivClient"
$acInstalled = Test-Path $acReg
if (-not $acInstalled) {
    $acReg = "HKLM:\SOFTWARE\ActivIdentity\ActivClient"
    $acInstalled = Test-Path $acReg
}

if ($acInstalled) {
    Write-Log "ActivClient installation found." "SUCCESS"

    # Enable PIN caching (reduces repeated PIN prompts within a session)
    Set-RegValue -Hive HKLM `
        -Path "SOFTWARE\HID Global\ActivClient\AC\Smartcard\PIN" `
        -Name "Allow PIN Caching" -Value 1 | Out-Null

    # Set PIN cache timeout (seconds; 0 = cache for entire session)
    Set-RegValue -Hive HKLM `
        -Path "SOFTWARE\HID Global\ActivClient\AC\Smartcard\PIN" `
        -Name "PIN Caching Timeout" -Value 900 | Out-Null  # 15-minute cache

    Write-Log "ActivClient PIN caching configured (900 second timeout)." "SUCCESS"
} else {
    Write-Log "ActivClient not found — skipping ActivClient-specific settings." "SKIP"
    $skipped++
}

# ── 5. DoD PIV Certificate Mapping ────────────────────────────────────────────
Write-Log "--- 5. Configure DoD PIV certificate mapping" "INFO"
# Use UPN (User Principal Name) from the PIV certificate for AD authentication
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\SmartCardCredentialProvider" `
    -Name "ForceReadingAllCertificates" -Value 1)) { $warns++ }

# Strong certificate mapping (required for 2023+ Windows security updates)
if (-not (Set-RegValue -Hive HKLM `
    -Path "SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name "StrongCertificateBindingEnforcement" -Value 1)) { $warns++ }

# ── 6. Horizon True SSO registry integration ──────────────────────────────────
Write-Log "--- 6. Configure Horizon True SSO integration" "INFO"

# Enable True SSO on the agent side
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\VMware, Inc.\VMware VDM\Agent\Configuration" `
    -Name "TrueSSO" -Value 1)) { $warns++ }

# Log True SSO events for troubleshooting
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\VMware, Inc.\VMware VDM\Agent\Configuration" `
    -Name "TrueSSO-Logging" -Value 1)) { $warns++ }

# ── 7. Apply HKLM.cred.providors.reg (credential provider lock-down) ──────────
Write-Log "--- 7. Apply credential provider registry file" "INFO"
$credProvidorsReg = Join-Path $PSScriptRoot "HKLM.cred.providors.reg"
if (Test-Path $credProvidorsReg) {
    try {
        $result = & reg import $credProvidorsReg 2>&1
        Write-Log "HKLM.cred.providors.reg applied successfully." "SUCCESS"
    } catch {
        Write-Log "HKLM.cred.providors.reg import failed: $_" "WARN"; $warns++
    }
} else {
    Write-Log "SKIP: HKLM.cred.providors.reg not found in $PSScriptRoot — apply manually if credential providers need locking." "SKIP"
    $skipped++
}

# ── 8. Verify DoD certificates are present ────────────────────────────────────
Write-Log "--- 8. Verify DoD Root CA certificates" "INFO"
try {
    $dodCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop |
        Where-Object { $_.Subject -like "*DoD*" -or $_.Subject -like "*Department of Defense*" }
    if ($dodCerts.Count -gt 0) {
        Write-Log "DoD Root CA certificates found: $($dodCerts.Count) certificate(s)." "SUCCESS"
    } else {
        Write-Log "WARNING: No DoD Root CA certificates found in LocalMachine\Root. Run InstallRoot.exe to install DoD PKI certificates." "WARN"
        $warns++
    }
} catch {
    Write-Log "Certificate store check failed: $_" "WARN"; $warns++
}

Write-Log "=== Section 17 complete ===" "INFO"
Write-Log "REMINDER: Horizon True SSO requires Enrollment Servers and a CA configured on the Horizon Connection Server — this script configures the golden image (agent) side only." "WARN"
Write-Log "REMINDER: Test CAC logon with a physical card in a Horizon pool BEFORE sealing the image." "WARN"
Write-Log "REMINDER: If HKLM.cred.providors.reg was not applied by this script, apply it manually: reg import HKLM.cred.providors.reg" "WARN"
$warns += 3
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
