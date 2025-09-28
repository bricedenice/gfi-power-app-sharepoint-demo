# Setup guide

## Initial configuration

### Create configuration file
```powershell
Copy-Item config-template.ps1 config.ps1
```

Edit config.ps1 with actual values:
* Replace "YourTenant.onmicrosoft.com" with tenant domain
* Add Azure AD app registration client ID
* Include certificate thumbprint
* Update SharePoint site URLs

### Create user data file
```powershell
Copy-Item users-template.csv users.csv
```

Edit users.csv with demo users:
* Use tenant-specific email domains
* Set secure passwords
* Define job titles and departments

### Verify file exclusions
The .gitignore file prevents sensitive files from version control:
* config.ps1 (actual configuration)
* users.csv (actual user data)
* development/ folder (production scripts)
* Certificate files

### Test configuration
```powershell
# Test Graph connection
$config = Import-PowerShellDataFile "./config.ps1"
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId

# Test PnP connection
Connect-PnPOnline -Url $config.SharePointSiteUrl -ClientId $config.ClientId
```

## Repository readiness
After completing setup:
1. Configuration file created (excluded from Git)
2. User data file created (excluded from Git)
3. No credentials in tracked files
4. Configuration tested successfully

The repository is ready for public hosting.
