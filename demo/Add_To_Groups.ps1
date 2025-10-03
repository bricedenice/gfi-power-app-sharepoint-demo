# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

# Function for audit logging
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "Add_To_Groups"
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

Connect-PnPOnline -Url $config.SharePointSiteUrl \
    -ClientId $config.ClientId \
    -Thumbprint $config.CertificateThumbprint \
    -Tenant $config.TenantId
Write-AuditLog -Message "Connected to SharePoint Online at $config.SharePointSiteUrl" -Level "INFO"

# Create custom groups if not exists
$groups = @("SCD Editors", "JCD Reviewers")
foreach ($g in $groups) {
    $fullGroupName = "GFI Strategic Concepts $g"
    if (-not (Get-PnPGroup -Identity $fullGroupName -ErrorAction SilentlyContinue)) {
        New-PnPGroup -Title $fullGroupName -Owner "GFI Strategic Concepts Owners"
        if ($g -eq "SCD Editors") { Set-PnPGroupPermissions -Identity $fullGroupName -AddRole "Contribute" }
        if ($g -eq "JCD Reviewers") { Set-PnPGroupPermissions -Identity $fullGroupName -AddRole "Read" }
        Write-AuditLog -Message "Created group $fullGroupName with appropriate permissions" -Level "SUCCESS"
    } else {
        Write-AuditLog -Message "Group $fullGroupName already exists, skipping creation" -Level "INFO"
    }
}

$roleMap = @{ 
    "Director"="GFI Strategic Concepts Owners"; "Deputy Director"="GFI Strategic Concepts Owners"; "Chief of Staff"="GFI Strategic Concepts Owners";
    "SCD Director"="GFI Strategic Concepts Members"; "Lead Analyst"="GFI Strategic Concepts SCD Editors"; 
    "JCD Director"="GFI Strategic Concepts Members"; "Lead Developer"="GFI Strategic Concepts JCD Reviewers"; 
    "Lead Data Scientist"="GFI Strategic Concepts JCD Reviewers"; "Senior Data Engineer"="GFI Strategic Concepts JCD Reviewers" 
}

$users = Import-Csv $config.UsersCSVPath
foreach ($u in $users) {
    $g = $roleMap[$u.JobTitle]; if (-not $g) { $g = "GFI Strategic Concepts Visitors" }
    try { Add-PnPGroupMember -LoginName $u.Email -Identity $g -ErrorAction Stop; Write-Host "Added $($u.Email) to $g"; Write-AuditLog -Message "Added $($u.Email) to $g" -Level "SUCCESS" }
    catch { Write-Warning "Could not add $($u.Email) to $($_.Exception.Message)"; Write-AuditLog -Message "Failed to add $($u.Email) to $g: $($_.Exception.Message)" -Level "ERROR" }
}

Write-AuditLog -Message "Script execution completed for adding users to groups" -Level "INFO"
