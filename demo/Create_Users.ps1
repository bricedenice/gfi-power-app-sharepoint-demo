# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome

$users = Import-Csv $config.UsersCSVPath
foreach ($u in $users) {
  $exists = Get-MgUser -Filter "userPrincipalName eq '$($u.Email)'" -ErrorAction SilentlyContinue
  if ($exists) { Write-Host "Exists: $($u.Email)"; continue }
  New-MgUser -BodyParameter @{
    AccountEnabled=$true; DisplayName=$u.DisplayName; MailNickname=$u.Email.Split("@")[0];
    UserPrincipalName=$u.Email; GivenName=$u.GivenName; Surname=$u.Surname;
    JobTitle=$u.JobTitle; Department=$u.Department;
    PasswordProfile=@{ Password=$u.Password; ForceChangePasswordNextSignIn=[bool]::Parse($u.ForceChange) }
  } | Out-Null
  Write-Host "Created: $($u.Email)"
}
