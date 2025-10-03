# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

# Function for audit logging
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "Create_Users"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    Write-Host $logEntry
    # Append to a log file for audit purposes (FedRAMP AU-2, AU-12)
    $logFile = "AuditLog_$(Get-Date -Format 'yyyyMMdd').log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome
Write-AuditLog -Message "Connected to Microsoft Graph API" -Level "INFO"

# Function to generate secure random passwords
function New-SecurePassword {
    param([int]$Length = 16)
    
    $upperCase = 'ABCDEFGHKLMNPRSTUVWXYZ'
    $lowerCase = 'abcdefghkmnprstuvwxyz'
    $numbers = '23456789'
    $symbols = '!@#$%^&*'
    $allChars = $upperCase + $lowerCase + $numbers + $symbols
    
    $password = ($upperCase | Get-Random -Count 1) + 
                ($lowerCase | Get-Random -Count 1) + 
                ($numbers | Get-Random -Count 1) + 
                ($symbols | Get-Random -Count 1) + 
                ($allChars.ToCharArray() | Get-Random -Count ($Length - 4) | Join-String)
    
    return -join ($password.ToCharArray() | Get-Random -Count $Length)
}

$users = Import-Csv $config.UsersCSVPath
foreach ($u in $users) {
    $exists = Get-MgUser -Filter "userPrincipalName eq '$($u.Email)'" -ErrorAction SilentlyContinue
    if ($exists) { 
        Write-Host "Exists: $($u.Email)"
        Write-AuditLog -Message "User $($u.Email) already exists, skipping creation" -Level "INFO"
        continue 
    }
    
    # For demo purposes, use password from CSV if provided; otherwise, generate a secure one
    $password = if ($u.Password) { $u.Password } else { New-SecurePassword }
    $forceChange = if ($u.ForceChange) { [bool]::Parse($u.ForceChange) } else { $true }
    
    New-MgUser -BodyParameter @{
        AccountEnabled=$true; DisplayName=$u.DisplayName; MailNickname=$u.Email.Split("@")[0];
        UserPrincipalName=$u.Email; GivenName=$u.GivenName; Surname=$u.Surname;
        JobTitle=$u.JobTitle; Department=$u.Department;
        PasswordProfile=@{ Password=$password; ForceChangePasswordNextSignIn=$forceChange }
    } | Out-Null
    Write-Host "Created: $($u.Email)"
    Write-AuditLog -Message "User $($u.Email) created successfully" -Level "SUCCESS"
}

Write-Host "⚠️ Note: For production environments, avoid storing passwords in CSV files. Use Azure Key Vault or generate secure passwords as shown above." -ForegroundColor Yellow
Write-AuditLog -Message "Script execution completed. Reminder: Avoid storing passwords in CSV for production." -Level "WARNING"
