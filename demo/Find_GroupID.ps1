# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome
$group = Get-MgGroup -Filter "displayName eq 'GFI Strategic Concepts'"
$group.Id
