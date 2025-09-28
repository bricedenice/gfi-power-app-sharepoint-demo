# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

Import-Module Microsoft.Graph
Connect-MgGraph -TenantId $config.TenantId -ClientId $config.ClientId -CertificateThumbprint $config.CertificateThumbprint -NoWelcome

$groupId = $config.SCDEditorsGroupId  # or $config.JCDReviewersGroupId depending on target group
$users = Import-Csv $config.UsersCSVPath
$successfullyAdded = @()

foreach ($u in $users) {
  try {
    $m = Get-MgUser -Filter "userPrincipalName eq '$($u.Email)'" -ErrorAction Stop
    New-MgGroupMemberByRef -GroupId $groupId -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($m.Id)" -ErrorAction Stop
    $successfullyAdded += $u.Email
    Write-Host "Successfully added $($u.Email) to group $groupId" -ForegroundColor Green
  }
  catch {
    Write-Warning "Failed to add $($u.Email) to group $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host "Total users successfully added: $($successfullyAdded.Count)" -ForegroundColor Cyan
Write-Host "Added users: $successfullyAdded" -ForegroundColor Cyan
