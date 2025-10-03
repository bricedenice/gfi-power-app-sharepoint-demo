# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

# Function for audit logging
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "Find_GroupID"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    Write-Host $logEntry
    # Append to a log file for audit purposes (FedRAMP AU-2, AU-12)
    $logFile = "AuditLog_$(Get-Date -Format 'yyyyMMdd').log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# Function to check certificate expiration
function Test-CertificateExpiration {
    param([string]$Thumbprint)
    
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My\$Thumbprint -ErrorAction SilentlyContinue
    if (-not $cert) {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My\$Thumbprint -ErrorAction SilentlyContinue
    }
    
    if (-not $cert) {
        throw "Certificate $Thumbprint not found in certificate store"
    }
    
    $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
    
    if ($daysUntilExpiry -lt 0) {
        throw "Certificate expired on $($cert.NotAfter). Renewal required."
    } elseif ($daysUntilExpiry -lt 30) {
        Write-Warning "⚠️ Certificate expires in $daysUntilExpiry days ($($cert.NotAfter)). Renewal recommended."
    } else {
        Write-Host "✔ Certificate valid until $($cert.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor Green
    }
    
    return $cert
}

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome
Write-AuditLog -Message "Connected to Microsoft Graph API" -Level "INFO"

$group = Get-MgGroup -Filter "displayName eq 'GFI Strategic Concepts'"
$group.Id
Write-AuditLog -Message "Retrieved group ID for 'GFI Strategic Concepts': $($group.Id)" -Level "SUCCESS"
