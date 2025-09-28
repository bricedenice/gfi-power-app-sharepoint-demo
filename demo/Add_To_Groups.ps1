# Load configuration
$config = Import-PowerShellDataFile "./config.ps1"

Connect-PnPOnline -Url $config.SharePointSiteUrl `
  -ClientId $config.ClientId `
  -Thumbprint $config.CertificateThumbprint `
  -Tenant $config.TenantId

# Create custom groups if not exists
$groups = @("SCD Editors", "JCD Reviewers")
foreach ($g in $groups) {
  $fullGroupName = "GFI Strategic Concepts $g"
  if (-not (Get-PnPGroup -Identity $fullGroupName -ErrorAction SilentlyContinue)) {
    New-PnPGroup -Title $fullGroupName -Owner "GFI Strategic Concepts Owners"
    if ($g -eq "SCD Editors") { Set-PnPGroupPermissions -Identity $fullGroupName -AddRole "Contribute" }
    if ($g -eq "JCD Reviewers") { Set-PnPGroupPermissions -Identity $fullGroupName -AddRole "Read" }
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
  try { Add-PnPGroupMember -LoginName $u.Email -Identity $g -ErrorAction Stop; Write-Host "Added $($u.Email) to $g" }
  catch { Write-Warning "Could not add $($u.Email) to $($_.Exception.Message)" }
}
