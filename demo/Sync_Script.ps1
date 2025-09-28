# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

# Ensure PnP PowerShell module is loaded
Import-Module -Name PnP.PowerShell -ErrorAction Stop

# Connect with app-only auth
Connect-PnPOnline -Url $config.SharePointSiteUrl `
    -ClientId $config.ClientId `
    -Thumbprint $config.CertificateThumbprint `
    -Tenant $config.TenantId -ErrorAction Stop

# Grant site access to the app (if needed)
Set-PnPAppSiteAccess -ClientId $config.ClientId -Scope FullControl -ErrorAction Stop

# Sync mock files using Add-PnPFile
$sourcePath = $config.SourcePath  # Define in config.ps1
$destFolder = $config.DestinationFolder  # Define in config.ps1
$files = Get-ChildItem -Path "$sourcePath/*.docx"

foreach ($file in $files) {
    Add-PnPFile -Path $file.FullName -Folder $destFolder -ErrorAction Stop
    Write-Output "Uploaded $($file.Name)"
}

Write-Output "Synced $($files.Count) files"
