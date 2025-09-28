# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome

$users = Import-Csv $config.UsersCSVPath
foreach ($u in $users) {
  Update-MgUser -UserId $u.Email -Department $u.Department -JobTitle $u.JobTitle -OfficeLocation "Phoenix, AZ" -City "Phoenix" -State "AZ" -Country "USA"
}
