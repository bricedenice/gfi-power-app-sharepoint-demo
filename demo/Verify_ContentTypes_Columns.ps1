<#
Purpose:
- Verify or create reusable site columns (Operational Level, Classification)
- Verify or create content type (GFI Concept Document) and attach fields (Classification required)
- Enable content types on the target library and attach the CT
- Make the CT default and optionally hide "Document"
- Add columns to the All Documents view
- Set defaults and indexing at the library level
- Print verification at the end

Usage:
- Requires PnP.PowerShell and cert-based app-only access
- Update $siteUrl, $tenantId, $clientId, $thumbprint, $libraryName as needed
#>

param(
  [string]$SiteUrl      = "https://yourtenant.sharepoint.com/sites/YourSite",
  [string]$TenantId     = "YourTenant.onmicrosoft.com",
  [string]$ClientId     = "YOUR_CLIENT_ID",
  [string]$Thumbprint   = "YOUR_CERTIFICATE_THUMBPRINT",
  [string]$LibraryName  = "Strategic Concepts",
  [string]$CtName       = "GFI Concept Document",
  [string]$CtGroup      = "GFI Content Types",
  [string]$CtDescription= "Concept document with governance metadata",
  [string]$FieldGroup   = "GFI Columns",
  [string]$OpLevelTitle = "Operational Level",
  [string]$OpLevelName  = "OperationalLevel",
  [string]$ClassTitle   = "Classification",
  [string]$ClassName    = "Classification",
  [string[]]$OpChoices  = @("Strategic","Tactical"),
  [string[]]$ClassChoices = @("Public","Sensitive"),
  [string]$DefaultOpLevel = "Strategic",
  [string]$DefaultClass   = "Public",
  [switch]$HideDefaultDocumentCT
)

# Helpers
function Write-Step {
  param([string]$Message)
  Write-Host "==> $Message"
}

function Try-Step {
  param(
    [string]$Title,
    [scriptblock]$Action
  )
  Write-Step $Title
  try {
    & $Action
    Write-Host "   ✔ $Title" -ForegroundColor Green
    $true
  }
  catch {
    Write-Host "   ✖ $Title" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    $false
  }
}

function Ensure-SiteColumn {
  param(
    [string]$DisplayName, [string]$InternalName, [string]$Type,
    [string[]]$Choices, [string]$Group
  )
  $existing = Get-PnPField -Identity $InternalName -ErrorAction SilentlyContinue
  if ($null -eq $existing) {
    Add-PnPField -DisplayName $DisplayName -InternalName $InternalName -Type $Type -Group $Group -Choices $Choices -ErrorAction Stop | Out-Null
    Write-Host "   Created site column: $DisplayName ($InternalName)"
  } else {
    Write-Host "   Site column already exists: $DisplayName ($InternalName)"
  }
}

function Ensure-ContentType {
  param([string]$Name, [string]$Group, [string]$Description)
  $ct = Get-PnPContentType -Identity $Name -ErrorAction SilentlyContinue
  if ($null -eq $ct) {
    Add-PnPContentType -Name $Name -Group $Group -Description $Description -ErrorAction Stop | Out-Null
    Write-Host "   Created content type: $Name"
  } else {
    Write-Host "   Content type already exists: $Name"
  }
}

function Ensure-FieldOnContentType {
  param([string]$CtName, [string]$FieldInternalName, [bool]$Required = $false)
  $ct = Get-PnPContentType -Identity $CtName -ErrorAction Stop
  $hasLink = $ct.FieldLinks | Where-Object { $_.Name -eq $FieldInternalName }
  if ($null -eq $hasLink) {
    Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternalName -Required:$Required -ErrorAction Stop | Out-Null
    Write-Host "   Added field '$FieldInternalName' to CT '$CtName' (Required=$Required)"
  } else {
    if ($Required -and -not $hasLink.Required) {
      # Re-add to enforce required flag or set via schema update
      Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternalName -Required -ErrorAction Stop | Out-Null
      Write-Host "   Updated field '$FieldInternalName' on CT '$CtName' to Required"
    } else {
      Write-Host "   Field '$FieldInternalName' already linked to CT '$CtName' (Required=$($hasLink.Required))"
    }
  }
}

function Ensure-ContentTypesEnabled-OnList {
  param([string]$ListTitle)
  $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
  if (-not $list.ContentTypesEnabled) {
    Set-PnPList -Identity $ListTitle -ContentTypesEnabled $true -ErrorAction Stop
    Write-Host "   Enabled content types on list '$ListTitle'"
  } else {
    Write-Host "   Content types already enabled on list '$ListTitle'"
  }
}

function Ensure-CTOnList {
  param([string]$ListTitle, [string]$CtName)
  $cts = Get-PnPContentType -List $ListTitle -ErrorAction Stop
  if ($cts.Name -notcontains $CtName) {
    Add-PnPContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop | Out-Null
    Write-Host "   Attached CT '$CtName' to list '$ListTitle'"
  } else {
    Write-Host "   CT '$CtName' already attached to list '$ListTitle'"
  }
}

function Ensure-DefaultCT {
  param([string]$ListTitle, [string]$CtName)
  Set-PnPDefaultContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop
  Write-Host "   Set CT '$CtName' as default on '$ListTitle'"
}

function Hide-DocumentCT {
  param([string]$ListTitle)
  $docCt = Get-PnPContentType -List $ListTitle -ErrorAction Stop | Where-Object Name -eq "Document"
  if ($docCt) {
    Set-PnPContentType -List $ListTitle -Identity $docCt -Hidden $true -ErrorAction Stop
    Write-Host "   Hid 'Document' content type on '$ListTitle'"
  } else {
    Write-Host "   'Document' CT not present or already hidden"
  }
}

function Ensure-Fields-In-View {
  param([string]$ListTitle,[string]$ViewTitle,[string[]]$FieldInternalNames)
  $view = Get-PnPView -List $ListTitle -Identity $ViewTitle -ErrorAction Stop
  $current = @($view.ViewFields)
  $desired = @()
  # Keep common basics, append desired fields uniquely
  $baseline = @("DocIcon","LinkFilename","Modified","Editor")
  $desired = $baseline + ($FieldInternalNames | Where-Object { $_ -notin $baseline })
  Set-PnPView -List $ListTitle -Identity $view.Title -Fields $desired -ErrorAction Stop | Out-Null
  Write-Host "   Updated view '$ViewTitle' fields: $($desired -join ', ')"
}

function Ensure-ListField-Values {
  param([string]$ListTitle, [string]$FieldInternalName, [hashtable]$Values)
  Set-PnPField -List $ListTitle -Identity $FieldInternalName -Values $Values -ErrorAction Stop | Out-Null
  $verify = Get-PnPField -List $ListTitle -Identity $FieldInternalName -ErrorAction Stop
  Write-Host "   Updated list field '$FieldInternalName' values: Indexed=$($verify.Indexed) Default='$($verify.DefaultValue)'"
}

# Connect
$ok = Try-Step "Connect to $SiteUrl" {
  Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantId -ErrorAction Stop
}
if (-not $ok) { exit 1 }

# Ensure Site Columns
Try-Step "Ensure site column '$OpLevelTitle' ($OpLevelName)" {
  Ensure-SiteColumn -DisplayName $OpLevelTitle -InternalName $OpLevelName -Type "Choice" -Choices $OpChoices -Group $FieldGroup
} | Out-Null

Try-Step "Ensure site column '$ClassTitle' ($ClassName)" {
  Ensure-SiteColumn -DisplayName $ClassTitle -InternalName $ClassName -Type "Choice" -Choices $ClassChoices -Group $FieldGroup
} | Out-Null

# Ensure Content Type and Field Links
Try-Step "Ensure content type '$CtName'" {
  Ensure-ContentType -Name $CtName -Group $CtGroup -Description $CtDescription
} | Out-Null

Try-Step "Ensure field link '$OpLevelName' on CT '$CtName'" {
  Ensure-FieldOnContentType -CtName $CtName -FieldInternalName $OpLevelName -Required:$false
} | Out-Null

Try-Step "Ensure field link '$ClassName' (Required) on CT '$CtName'" {
  Ensure-FieldOnContentType -CtName $CtName -FieldInternalName $ClassName -Required:$true
} | Out-Null

# Enable CTs on Library, Attach, Set Default
Try-Step "Enable content types on library '$LibraryName'" {
  Ensure-ContentTypesEnabled-OnList -ListTitle $LibraryName
} | Out-Null

Try-Step "Attach content type '$CtName' to library '$LibraryName'" {
  Ensure-CTOnList -ListTitle $LibraryName -CtName $CtName
} | Out-Null

Try-Step "Set '$CtName' as default CT on '$LibraryName'" {
  Ensure-DefaultCT -ListTitle $LibraryName -CtName $CtName
} | Out-Null

if ($HideDefaultDocumentCT.IsPresent) {
  Try-Step "Hide default 'Document' content type on '$LibraryName'" {
    Hide-DocumentCT -ListTitle $LibraryName
  } | Out-Null
}

# View Columns
Try-Step "Add columns to 'All Documents' view" {
  Ensure-Fields-In-View -ListTitle $LibraryName -ViewTitle "All Documents" -FieldInternalNames @($OpLevelName,$ClassName)
} | Out-Null

# Defaults and Indexing
Try-Step "Set defaults and indexing on '$OpLevelName'" {
  Ensure-ListField-Values -ListTitle $LibraryName -FieldInternalName $OpLevelName -Values @{ DefaultValue = $DefaultOpLevel; Indexed = $true }
} | Out-Null

Try-Step "Set default on '$ClassName'" {
  Ensure-ListField-Values -ListTitle $LibraryName -FieldInternalName $ClassName -Values @{ DefaultValue = $DefaultClass }
} | Out-Null

# Verification Summary
Write-Step "Verification summary"

Try-Step "Verify CT present on library" {
  $cts = Get-PnPContentType -List $LibraryName -ErrorAction Stop
  $cts | Select-Object Name, StringId | Format-Table | Out-String | Write-Host
} | Out-Null

Try-Step "Verify CT field links on library instance" {
  $ctList = Get-PnPContentType -List $LibraryName -Identity $CtName -ErrorAction Stop
  $ctList.FieldLinks | Select-Object Name, Required | Format-Table | Out-String | Write-Host
} | Out-Null

Try-Step "Verify fields exist on list and settings" {
  $f1 = Get-PnPField -List $LibraryName -Identity $OpLevelName -ErrorAction Stop
  $f2 = Get-PnPField -List $LibraryName -Identity $ClassName   -ErrorAction Stop
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f1.Title, $f1.Indexed, $f1.DefaultValue)
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f2.Title, $f2.Indexed, $f2.DefaultValue)
} | Out-Null

Write-Host "`nAll steps attempted. Review ✔/✖ above for outcomes."