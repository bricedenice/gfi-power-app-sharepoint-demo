<#
Purpose
- Build governed, reusable metadata for a SharePoint document library using PnP.PowerShell.
- Create site columns and a content type at the site scope, then wire them to a specific library.
- Handle all first-run tasks: attach CT, set as default, add columns to views, set defaults and indexing.
- Output clear feedback per step so anyone reviewing can follow what happened and why.

Why this approach
- Site columns + content type = reuse and consistency. Define metadata once, apply anywhere.
- Library-scoped fields are faster to create, but they scatter definitions. A content type keeps governance clean.
- Idempotence matters in production. You need to re-run this safely without breaking things.

Prerequisites
- PnP.PowerShell module installed (Install-Module PnP.PowerShell).
- An Azure AD app configured for certificate-based app-only auth with appropriate SPO permissions.
- The target site and library already exist (we won't create them here).
#>

param(
  # Connection settings
  # Use variables so this script works across tenants/sites without changing code.
  [string]$SiteUrl    = "https://yourtenant.sharepoint.com/sites/YourSite",
  [string]$TenantId   = "YourTenant.onmicrosoft.com",     # Can be GUID or domain form
  [string]$ClientId   = "YOUR_CLIENT_ID",
  [string]$Thumbprint = "YOUR_CERTIFICATE_THUMBPRINT",

  # Library and governance objects
  # These names are part of your governance vocabulary. Keep them stable and meaningful.
  [string]$LibraryName   = "Strategic Concepts",
  [string]$CtName        = "GFI Concept Document",
  [string]$CtGroup       = "GFI Content Types",
  [string]$CtDescription = "Concept document with governance metadata",

  # Site column definitions
  # InternalName should be stable and code-friendly; DisplayName can be business-friendly.
  [string]$FieldGroup     = "GFI Columns",
  [string]$OpLevelTitle   = "Operational Level",
  [string]$OpLevelName    = "OperationalLevel",
  [string[]]$OpChoices    = @("Strategic","Tactical"),
  [string]$ClassTitle     = "Classification",
  [string]$ClassName      = "Classification",
  [string[]]$ClassChoices = @("Public","Sensitive"),

  # Defaults and behavior
  # Defaults reduce friction for users while still allowing overrides.
  [string]$DefaultOpLevel = "Strategic",
  [string]$DefaultClass   = "Public",

  # Optional behavior
  # Hide the built-in "Document" content type to prevent new uploads from falling back to it.
  [switch]$HideDefaultDocumentCT
)

# Utility helpers for readable, reviewable output
function Step { param([string]$m) Write-Host "==> $m" }
function TryDo {
  param([string]$Title, [scriptblock]$Action)
  Step $Title
  try {
    & $Action
    Write-Host "   ✔ $Title" -ForegroundColor Green
    return $true
  }
  catch {
    Write-Host "   ✖ $Title" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    return $false
  }
}

# Creates a site column if it doesn't exist, or confirms it if it does.
# Site columns live at the site scope and can be reused across libraries and content types.
function Ensure-SiteColumn {
  param([string]$DisplayName,[string]$Internal,[string]$Type,[string[]]$Choices,[string]$Group)
  $existing = Get-PnPField -Identity $Internal -ErrorAction SilentlyContinue
  if ($null -eq $existing) {
    Add-PnPField -DisplayName $DisplayName -InternalName $Internal -Type $Type -Choices $Choices -Group $Group -ErrorAction Stop | Out-Null
    Write-Host "   Created site column: $DisplayName ($Internal)"
  } else {
    Write-Host "   Site column present: $DisplayName ($Internal)"
  }
}

# Creates a content type if it doesn't exist.
# A content type bundles fields and behaviors—it's the right unit for governed document types.
function Ensure-ContentType {
  param([string]$Name,[string]$Group,[string]$Desc)
  $ct = Get-PnPContentType -Identity $Name -ErrorAction SilentlyContinue
  if ($null -eq $ct) {
    Add-PnPContentType -Name $Name -Group $Group -Description $Desc -ErrorAction Stop | Out-Null
    Write-Host "   Created content type: $Name"
  } else {
    Write-Host "   Content type present: $Name"
  }
}

# Links a field to the CT and optionally marks it required at the CT level.
# We force-load FieldLinks because CSOM lazy-loads collections.
function Ensure-FieldLink-OnCT {
  param([string]$CtName,[string]$FieldInternal,[bool]$Required)
  $ct = Get-PnPContentType -Identity $CtName -Includes FieldLinks -ErrorAction Stop
  Get-PnPProperty -ClientObject $ct -Property FieldLinks   # load the collection explicitly

  $link = $ct.FieldLinks | Where-Object { $_.Name -eq $FieldInternal }
  if ($null -eq $link) {
    Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternal -Required:$Required -ErrorAction Stop | Out-Null
    Write-Host "   Added field '$FieldInternal' to CT '$CtName' (Required=$Required)"
  } elseif ($Required -and -not $link.Required) {
    Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternal -Required -ErrorAction Stop | Out-Null
    Write-Host "   Set field '$FieldInternal' to Required on CT '$CtName'"
  } else {
    Write-Host "   Field '$FieldInternal' already linked to CT '$CtName' (Required=$($link.Required))"
  }
}

# Configures the library to accept content types.
function Enable-CTs-OnList {
  param([string]$ListTitle)
  $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
  if (-not $list.ContentTypesEnabled) {
    Set-PnPList -Identity $ListTitle -ContentTypesEnabled $true -ErrorAction Stop
    Write-Host "   Content types enabled on '$ListTitle'"
  } else {
    Write-Host "   Content types already enabled on '$ListTitle'"
  }
}

# Attaches the CT to the target library if it isn’t already there.
function Ensure-CT-OnList {
  param([string]$ListTitle,[string]$CtName)
  $cts = Get-PnPContentType -List $ListTitle -ErrorAction Stop
  if ($cts.Name -notcontains $CtName) {
    Add-PnPContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop | Out-Null
    Write-Host "   Attached CT '$CtName' to '$ListTitle'"
  } else {
    Write-Host "   CT '$CtName' already attached to '$ListTitle'"
  }
}

# Sets the default CT so new uploads automatically use the governed type.
function Set-DefaultCT {
  param([string]$ListTitle,[string]$CtName)
  Set-PnPDefaultContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop
  Write-Host "   Default CT set to '$CtName' on '$ListTitle'"
}

# Hides the built-in "Document" CT to prevent fallbacks during uploads.
function Maybe-Hide-DocumentCT {
  param([string]$ListTitle)
  $doc = Get-PnPContentType -List $ListTitle -ErrorAction Stop | Where-Object Name -eq "Document"
  if ($doc) {
    Set-PnPContentType -List $ListTitle -Identity $doc -Hidden $true -ErrorAction Stop
    Write-Host "   Hid 'Document' CT on '$ListTitle'"
  } else {
    Write-Host "   'Document' CT not present or already hidden"
  }
}

# Makes the governed columns visible in the "All Documents" view.
# Columns can exist on the CT but still not show in the current view—this closes that gap.
function Ensure-ViewFields {
  param([string]$ListTitle,[string]$View,[string[]]$Fields)
  $view = Get-PnPView -List $ListTitle -Identity $View -ErrorAction Stop
  $baseline = @("DocIcon","LinkFilename","Modified","Editor")   # keep familiar basics
  $desired = $baseline + ($Fields | Where-Object { $_ -notin $baseline })
  Set-PnPView -List $ListTitle -Identity $view.Title -Fields $desired -ErrorAction Stop | Out-Null
  Write-Host "   View '$View' fields set: $($desired -join ', ')"
}

# Applies defaults and indexing at the library scope.
# Indexing improves list view performance at scale; defaults reduce data entry friction.
function Set-ListFieldValues {
  param([string]$ListTitle,[string]$FieldInternal,[hashtable]$Values)
  Set-PnPField -List $ListTitle -Identity $FieldInternal -Values $Values -ErrorAction Stop | Out-Null
  $v = Get-PnPField -List $ListTitle -Identity $FieldInternal -ErrorAction Stop
  Write-Host "   Field '$($v.Title)': Indexed=$($v.Indexed) Default='$($v.DefaultValue)'"
}

# Connect to SharePoint Online
# Certificate-based app-only auth keeps secrets out of code and supports CI/CD.
$ok = TryDo "Connect to $SiteUrl" {
  Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantId -ErrorAction Stop
}
if (-not $ok) { exit 1 }

# Create or verify site columns
# We choose Choice type for both columns to enforce controlled vocabulary used by views, flows, and security.
TryDo "Ensure site column '$OpLevelTitle' ($OpLevelName)" {
  Ensure-SiteColumn -DisplayName $OpLevelTitle -Internal $OpLevelName -Type "Choice" -Choices $OpChoices -Group $FieldGroup
} | Out-Null

TryDo "Ensure site column '$ClassTitle' ($ClassName)" {
  Ensure-SiteColumn -DisplayName $ClassTitle -Internal $ClassName -Type "Choice" -Choices $ClassChoices -Group $FieldGroup
} | Out-Null

# Create or verify content type
# Content type is the contract: it carries the fields, and libraries opt into that contract.
TryDo "Ensure content type '$CtName'" {
  Ensure-ContentType -Name $CtName -Group $CtGroup -Desc $CtDescription
} | Out-Null

# Link fields to the content type
# Classification is required so every document carries a protection signal for routing/compliance.
TryDo "Link '$OpLevelName' to CT '$CtName'" {
  Ensure-FieldLink-OnCT -CtName $CtName -FieldInternal $OpLevelName -Required:$false
} | Out-Null

TryDo "Link '$ClassName' (Required) to CT '$CtName'" {
  Ensure-FieldLink-OnCT -CtName $CtName -FieldInternal $ClassName -Required:$true
} | Out-Null

# Propagate CT to child lists (future-proofing)
# If the CT was modified after being applied elsewhere, push updates to children so they stay in sync.
TryDo "Propagate CT '$CtName' to children" {
  $ct = Get-PnPContentType -Identity $CtName -ErrorAction Stop
  Set-PnPContentType -Identity $ct -UpdateChildren -ErrorAction Stop
} | Out-Null

# Wire the target library
# Turn on CT support, attach the governed type, and set it as default so uploads pick it automatically.
TryDo "Enable content types on '$LibraryName'" {
  Enable-CTs-OnList -ListTitle $LibraryName
} | Out-Null

TryDo "Attach CT '$CtName' to '$LibraryName'" {
  Ensure-CT-OnList -ListTitle $LibraryName -CtName $CtName
} | Out-Null

TryDo "Set '$CtName' as default CT on '$LibraryName'" {
  Set-DefaultCT -ListTitle $LibraryName -CtName $CtName
} | Out-Null

if ($HideDefaultDocumentCT.IsPresent) {
  TryDo "Hide 'Document' CT on '$LibraryName'" {
    Maybe-Hide-DocumentCT -ListTitle $LibraryName
  } | Out-Null
}

# Make the columns visible and useful in the UI
# Add the columns to the default view. Without this, the columns exist but aren't immediately visible.
TryDo "Add governed columns to 'All Documents' view" {
  Ensure-ViewFields -ListTitle $LibraryName -View "All Documents" -Fields @($OpLevelName,$ClassName)
} | Out-Null

# Apply defaults and indexing at the library so user experience and performance are good from day one.
TryDo "Set default + index on '$OpLevelName'" {
  Set-ListFieldValues -ListTitle $LibraryName -FieldInternal $OpLevelName -Values @{ DefaultValue = $DefaultOpLevel; Indexed = $true }
} | Out-Null

TryDo "Set default on '$ClassName'" {
  Set-ListFieldValues -ListTitle $LibraryName -FieldInternal $ClassName -Values @{ DefaultValue = $DefaultClass }
} | Out-Null

# Verification summary for reviewers
# Helpful in code reviews, handoffs, and portfolio demos.
Step "Verification summary"

TryDo "List content types on '$LibraryName'" {
  Get-PnPContentType -List $LibraryName | Select-Object Name,StringId | Format-Table | Out-String | Write-Host
} | Out-Null

TryDo "Show library CT field links (Name, Required)" {
  $ctList = Get-PnPContentType -List $LibraryName -Identity $CtName -Includes FieldLinks
  Get-PnPProperty -ClientObject $ctList -Property FieldLinks
  $ctList.FieldLinks | Select-Object Name,Required | Format-Table | Out-String | Write-Host
} | Out-Null

TryDo "Show list fields (Indexed, Default)" {
  $f1 = Get-PnPField -List $LibraryName -Identity $OpLevelName
  $f2 = Get-PnPField -List $LibraryName -Identity $ClassName
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f1.Title, $f1.Indexed, $f1.DefaultValue)
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f2.Title, $f2.Indexed, $f2.DefaultValue)
} | Out-Null

Write-Host "`nCompleted. Review ✔/✖ above for outcomes and any follow-ups."