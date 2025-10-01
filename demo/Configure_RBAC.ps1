<#
Purpose
- Build governed, reusable metadata for a SharePoint document library using PnP.PowerShell.
- Create site columns and a content type at the site scope, then wire them to a specific library.
- Handle all first-run tasks: attach CT, set as default, add columns to views, set defaults and indexing.
- Configure RBAC for the target library (SCD Editors = Contribute, JCD Reviewers = Read) and seed demo users.
- Output clear feedback per step so anyone reviewing can follow what happened and why.

Why this approach
- Site columns + content type = reuse and consistency. Define metadata once, apply anywhere.
- Library-scoped fields are faster to create, but they scatter definitions. A content type keeps governance clean.
- Idempotence matters in production. You need to re-run this safely without breaking things.
- Complex CSOM solution: C# was my first language, Kotlin is my strongsuit, and PowerShell is the weird cousin at the family reunion who insists on doing everything differently. They all run on similar principles (objects, types, lambdas), but PowerShell's verb-noun cmdlets and pipeline operators still trip me up. When the CSOM patterns get dense, I use Grok to translate the .NET object manipulation into something my Kotlin-wired brain can parse.

Prerequisites
- PnP.PowerShell module installed (Install-Module PnP.PowerShell).
- An Azure AD app configured for certificate-based app-only auth with appropriate SPO permissions.
- The target site and library already exist (we won't create them here).
#>

param(
  # Connection settings
  [string]$SiteUrl    = "https://yourtenant.sharepoint.com/sites/YourSite",
  [string]$TenantId   = "YourTenant.onmicrosoft.com",
  [string]$ClientId   = "YOUR_CLIENT_ID",
  [string]$Thumbprint = "YOUR_CERTIFICATE_THUMBPRINT",

  # Library and governance objects
  [string]$LibraryName   = "Strategic Concepts",
  [string]$CtName        = "GFI Concept Document",
  [string]$CtGroup       = "GFI Content Types",
  [string]$CtDescription = "Concept document with governance metadata",

  # Site column definitions
  [string]$FieldGroup     = "GFI Columns",
  [string]$OpLevelTitle   = "Operational Level",
  [string]$OpLevelName    = "OperationalLevel",
  [string[]]$OpChoices    = @("Strategic","Tactical"),
  [string]$ClassTitle     = "Classification",
  [string]$ClassName      = "Classification",
  [string[]]$ClassChoices = @("Public","Sensitive"),

  # Defaults and behavior
  [string]$DefaultOpLevel = "Strategic",
  [string]$DefaultClass   = "Public",

  # RBAC objects
  # Site groups (adjust names to match your site if needed)
  [string]$OwnersGroupName = "GFI Strategic Concepts Owners",
  [string]$SCDGroupName    = "GFI Strategic Concepts SCD Editors",
  [string]$JCDGroupName    = "GFI Strategic Concepts JCD Reviewers",

  # Demo member seeds
  [string[]]$SeedOwners = @(
    "laura.bennett@YourTenant.onmicrosoft.com",
    "sam.nguyen@YourTenant.onmicrosoft.com",
    "elena.ortiz@YourTenant.onmicrosoft.com"
  ),
  [string[]]$SeedSCDMembers = @(
    "michael.patel@YourTenant.onmicrosoft.com",
    "karen.foster@YourTenant.onmicrosoft.com"
  ),
  [string[]]$SeedJCDMembers = @(
    "david.kim@YourTenant.onmicrosoft.com",
    "john.rivera@YourTenant.onmicrosoft.com",
    "emily.walsh@YourTenant.onmicrosoft.com",
    "rachel.torres@YourTenant.onmicrosoft.com"
  ),

  # Optional behavior
  [switch]$HideDefaultDocumentCT
)

# Utility helpers

# One-liner function with inline parameter declaration
# Similar to Kotlin: fun step(m: String) = println("==> $m")
# The param() block can be inline for simple functions
function Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }

# Simple helper for consistent output formatting
# PowerShell functions don't need explicit return—last expression is returned
function Info { param([string]$m) Write-Host "   $m" }

# Higher-order function accepting a scriptblock (like lambda in Kotlin)
# [scriptblock] is PowerShell's equivalent to Kotlin's () -> Unit
function TryDo {
  param([string]$Title, [scriptblock]$Action)
  Step $Title
  try { 
    # & operator executes the scriptblock (like invoke() in Kotlin)
    & $Action
    Write-Host "   ✔ $Title" -ForegroundColor Green
    return $true
  }
  catch { 
    # $_ is PowerShell's implicit exception variable (like 'it' in Kotlin)
    # $($_.Exception.Message) - subexpression syntax for string interpolation
    Write-Host "   ✖ $Title" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    return $false 
  }
}

# Idempotent function pattern (safe to re-run)
# Similar to Kotlin's "check if exists, create if not" pattern
function Ensure-SiteColumn {
  param([string]$DisplayName,[string]$Internal,[string]$Type,[string[]]$Choices,[string]$Group)
  
  # -ErrorAction SilentlyContinue suppresses errors (like try-catch)
  # Returns $null if field doesn't exist instead of throwing exception
  $existing = Get-PnPField -Identity $Internal -ErrorAction SilentlyContinue
  
  # PowerShell null comparison—always put $null on left side
  # Prevents issues with collections. In Kotlin: if (existing == null)
  if ($null -eq $existing) {
    # Splatting parameters with named arguments (like Kotlin named params)
    # | Out-Null suppresses return output (like Unit in Kotlin)
    Add-PnPField -DisplayName $DisplayName -InternalName $Internal -Type $Type -Choices $Choices -Group $Group -ErrorAction Stop | Out-Null
    Info "Created site column: $DisplayName ($Internal)"
  } else { 
    # else clause for idempotent operations
    Info "Site column present: $DisplayName ($Internal)" 
  }
}

function Ensure-ContentType {
  param([string]$Name,[string]$Group,[string]$Desc)
  $ct = Get-PnPContentType -Identity $Name -ErrorAction SilentlyContinue
  if ($null -eq $ct) {
    Add-PnPContentType -Name $Name -Group $Group -Description $Desc -ErrorAction Stop | Out-Null
    Info "Created content type: $Name"
  } else { Info "Content type present: $Name" }
}

# Complex business logic with multiple conditions
# Advanced PowerShell patterns for SharePoint object manipulation
function Ensure-FieldLink-OnCT {
  param([string]$CtName,[string]$FieldInternal,[bool]$Required)
  
  # -Includes parameter for eager loading (like JPA fetch joins)
  # Loads related FieldLinks collection to avoid lazy loading issues
  $ct = Get-PnPContentType -Identity $CtName -Includes FieldLinks -ErrorAction Stop
  
  # Explicit property loading for CSOM objects
  # SharePoint Client Object Model requires explicit property requests
  Get-PnPProperty -ClientObject $ct -Property FieldLinks
  
  # Pipeline filtering with Where-Object (like Kotlin's filter)
  # $_ represents current object in pipeline (like 'it' in Kotlin)
  $link = $ct.FieldLinks | Where-Object { $_.Name -eq $FieldInternal }
  
  if ($null -eq $link) {
    # Switch parameter syntax with colon (:$Variable)
    # Passes boolean value to switch parameter
    Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternal -Required:$Required -ErrorAction Stop | Out-Null
    Info "Added field '$FieldInternal' to CT '$CtName' (Required=$Required)"
  } elseif ($Required -and -not $link.Required) {
    # Complex conditional logic with boolean operations
    # -and, -or, -not are PowerShell's logical operators
    Add-PnPFieldToContentType -ContentType $CtName -Field $FieldInternal -Required -ErrorAction Stop | Out-Null
    Info "Set field '$FieldInternal' to Required on CT '$CtName'"
  } else { 
    # String interpolation with subexpression $()
    # Similar to Kotlin's "${expression}" syntax
    Info "Field '$FieldInternal' already linked to CT '$CtName' (Required=$($link.Required))" 
  }
}

function Enable-CTs-OnList {
  param([string]$ListTitle)
  $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
  if (-not $list.ContentTypesEnabled) {
    Set-PnPList -Identity $ListTitle -ContentTypesEnabled $true -ErrorAction Stop
    Info "Content types enabled on '$ListTitle'"
  } else { Info "Content types already enabled on '$ListTitle'" }
}

function Ensure-CT-OnList {
  param([string]$ListTitle,[string]$CtName)
  $cts = Get-PnPContentType -List $ListTitle -ErrorAction Stop
  if ($cts.Name -notcontains $CtName) {
    Add-PnPContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop | Out-Null
    Info "Attached CT '$CtName' to '$ListTitle'"
  } else { Info "CT '$CtName' already attached to '$ListTitle'" }
}

function Set-DefaultCT { param([string]$ListTitle,[string]$CtName)
  Set-PnPDefaultContentTypeToList -List $ListTitle -ContentType $CtName -ErrorAction Stop
  Info "Default CT set to '$CtName' on '$ListTitle'"
}

function Maybe-Hide-DocumentCT { param([string]$ListTitle)
  $doc = Get-PnPContentType -List $ListTitle -ErrorAction Stop | Where-Object Name -eq "Document"
  if ($doc) { Set-PnPContentType -List $ListTitle -Identity $doc -Hidden $true -ErrorAction Stop; Info "Hid 'Document' CT on '$ListTitle'" }
  else { Info "'Document' CT not present or already hidden" }
}

# Resolve the view title robustly before calling this helper
function Ensure-ViewFields {
  param([string]$ListTitle,[string]$View,[string[]]$Fields)
  $view = Get-PnPView -List $ListTitle -Identity $View -ErrorAction Stop
  $baseline = @("DocIcon","LinkFilename","Modified","Editor")
  $desired = $baseline + ($Fields | Where-Object { $_ -notin $baseline })
  Set-PnPView -List $ListTitle -Identity $view.Title -Fields $desired -ErrorAction Stop | Out-Null
  Info "View '$View' fields set: $($desired -join ', ')"
}

function Set-ListFieldValues {
  param([string]$ListTitle,[string]$FieldInternal,[hashtable]$Values)
  Set-PnPField -List $ListTitle -Identity $FieldInternal -Values $Values -ErrorAction Stop | Out-Null
  $v = Get-PnPField -List $ListTitle -Identity $FieldInternal -ErrorAction Stop
  Info ("Field '{0}': Indexed={1} Default='{2}'" -f $v.Title, $v.Indexed, $v.DefaultValue)
}

# RBAC helpers
function Ensure-SPGroup { param([string]$GroupName)
  $g = Get-PnPGroup -Identity $GroupName -ErrorAction SilentlyContinue
  if ($null -eq $g) {
    New-PnPGroup -Title $GroupName -AllowMembersEditMembership:$false -OnlyAllowMembersViewMembership:$true -ErrorAction Stop | Out-Null
    Info "Created SharePoint group: $GroupName"
  } else { Info "Group present: $GroupName" }
}

function Ensure-BrokenInheritance { param([string]$ListTitle)
  $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
  if ($list.HasUniqueRoleAssignments -ne $true) {
    Set-PnPList -Identity $ListTitle -BreakRoleInheritance -CopyRoleAssignments:$false -ClearSubscopes:$true -ErrorAction Stop
    Info "Broke permission inheritance on '$ListTitle'"
  } else { Info "Permissions already unique on '$ListTitle'" }
}

# Advanced CSOM (Client Side Object Model) manipulation
# Working with a remote API that requires explicit loading/execution
function Grant-ListRoleCSOM {
  param([string]$ListTitle,[string]$GroupName,[string]$RoleName)

  # Getting SharePoint context (like getting a database connection)
  # $ctx is the connection to SharePoint's API
  $ctx  = Get-PnPContext
  $web  = $ctx.Web
  $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
  $group = Get-PnPGroup -Identity $GroupName -ErrorAction Stop

  # Explicit loading pattern for CSOM
  # Like lazy loading—you must request data before using it
  $ctx.Load($list.RoleAssignments)
  $ctx.ExecuteQuery()  # Actually executes the request (like commit() in databases)

  # Flag variable for existence checking
  # Similar to Kotlin's any() function but using imperative style
  $existing = $false
  
  # foreach loop over CSOM collection
  # Like Kotlin's forEach but with imperative break control
  foreach ($ra in $list.RoleAssignments) {
    # Loading nested properties on demand
    $ctx.Load($ra.Member)
    $ctx.Load($ra.RoleDefinitionBindings)
    $ctx.ExecuteQuery()
    
    # Complex condition with pipeline filtering
    # Combines ID comparison with collection filtering
    if ($ra.Member.Id -eq $group.Id -and ($ra.RoleDefinitionBindings | Where-Object { $_.Name -eq $RoleName })) {
      $existing = $true; break  # Early exit from loop
    }
  }

  if (-not $existing) {
    # .NET object creation in PowerShell
    # New-Object is like 'new' in Kotlin but more explicit
    $roleDef = $web.RoleDefinitions.GetByName($RoleName)
    $bindings = New-Object Microsoft.SharePoint.Client.RoleDefinitionBindingCollection($ctx)
    $bindings.Add($roleDef)
    $list.RoleAssignments.Add($group, $bindings)
    $ctx.ExecuteQuery()  # Commit the changes
  }
  Info "Ensured '$RoleName' for '$GroupName' on '$ListTitle'"
}

function Ensure-GroupMembers { param([string]$GroupName,[string[]]$Members)
  if ($Members -and $Members.Count -gt 0) {
    foreach ($m in $Members) {
      try { Add-PnPGroupMember -Identity $GroupName -LoginName $m -ErrorAction Stop | Out-Null; Info "Added '$m' to '$GroupName'" }
      catch { Info "Skipped '$m' (already a member or not resolvable): $($_.Exception.Message)" }
    }
  }
}

# Connect
# Using custom TryDo function with scriptblock
# The { } creates a scriptblock (lambda) passed to TryDo function
$ok = TryDo "Connect to $SiteUrl" {
  Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantId -ErrorAction Stop
}
# Early exit pattern with semicolon statement separator
# if (-not $ok) is like Kotlin's if (!ok), exit 1 terminates script
if (-not $ok) { exit 1 }

# Metadata: fields + CT
# Function calls within scriptblocks with parameter splatting
# Each TryDo wraps a function call in error handling with consistent output
TryDo "Ensure site column '$OpLevelTitle' ($OpLevelName)" { 
  Ensure-SiteColumn -DisplayName $OpLevelTitle -Internal $OpLevelName -Type "Choice" -Choices $OpChoices -Group $FieldGroup 
} | Out-Null

TryDo "Ensure site column '$ClassTitle' ($ClassName)" { 
  Ensure-SiteColumn -DisplayName $ClassTitle -Internal $ClassName -Type "Choice" -Choices $ClassChoices -Group $FieldGroup 
} | Out-Null

# String interpolation in function descriptions
# Variables inside strings are expanded (like Kotlin's string templates)
TryDo "Ensure content type '$CtName'" { 
  Ensure-ContentType -Name $CtName -Group $CtGroup -Desc $CtDescription 
} | Out-Null

# Boolean parameter passing with colon syntax
# :$false and :$true pass boolean values to switch parameters
TryDo "Link '$OpLevelName' to CT '$CtName'" { 
  Ensure-FieldLink-OnCT -CtName $CtName -FieldInternal $OpLevelName -Required:$false 
} | Out-Null

TryDo "Link '$ClassName' (Required) to CT '$CtName'" { 
  Ensure-FieldLink-OnCT -CtName $CtName -FieldInternal $ClassName -Required:$true 
} | Out-Null
TryDo "Propagate CT '$CtName' to children" {
  $ct = Get-PnPContentType -Identity $CtName -ErrorAction Stop
  Set-PnPContentType -Identity $ct -UpdateChildren -ErrorAction Stop
} | Out-Null

# Wire library
# Sequential configuration steps using TryDo wrapper
# Each step builds on the previous—content types must be enabled before attaching
TryDo "Enable content types on '$LibraryName'" { 
  Enable-CTs-OnList -ListTitle $LibraryName 
} | Out-Null

TryDo "Attach CT '$CtName' to '$LibraryName'" { 
  Ensure-CT-OnList -ListTitle $LibraryName -CtName $CtName 
} | Out-Null

TryDo "Set '$CtName' as default CT on '$LibraryName'" { 
  Set-DefaultCT -ListTitle $LibraryName -CtName $CtName 
} | Out-Null

# Conditional execution with switch parameter testing
# .IsPresent checks if switch parameter was provided (like Kotlin's nullable boolean)
if ($HideDefaultDocumentCT.IsPresent) { 
  TryDo "Hide 'Document' CT on '$LibraryName'" { 
    Maybe-Hide-DocumentCT -ListTitle $LibraryName 
  } | Out-Null 
}

# Robust view selection with fallback logic
# Defensive programming patterns for SharePoint views
TryDo "Add governed columns to view" {
  # Getting all views from a list
  $views = Get-PnPView -List $LibraryName
  
  # Pipeline with Select-Object -First 1 for single result
  # Similar to Kotlin's firstOrNull() function
  $view = $views | Where-Object { $_.Title -eq "All Documents" } | Select-Object -First 1
  
  # Fallback pattern with multiple conditionals
  # If preferred view not found, try default view
  if (-not $view) { 
    $view = $views | Where-Object { $_.DefaultView -eq $true } | Select-Object -First 1 
  }
  
  # Error handling with throw statement
  # Similar to Kotlin's throw IllegalStateException()
  if (-not $view) { 
    throw "No suitable view found on '$LibraryName'." 
  }
  
  # Complex array operations for view field management
  $baseline = @("DocIcon","LinkFilename","Modified","Editor")
  $desired = $baseline + @($OpLevelName,$ClassName | Where-Object { $_ -notin $baseline })
  
  Set-PnPView -List $LibraryName -Identity $view.Title -Fields $desired | Out-Null
  
  # Object property access in string interpolation
  Info "Updated view '$($view.Title)'"
} | Out-Null

# Hashtable inline creation for multiple property updates
# @{} creates hashtables on-the-fly (like Kotlin's mapOf())
TryDo "Set default + index on '$OpLevelName'" { 
  Set-ListFieldValues -ListTitle $LibraryName -FieldInternal $OpLevelName -Values @{ 
    DefaultValue = $DefaultOpLevel; 
    Indexed = $true 
  } 
} | Out-Null

TryDo "Set default on '$ClassName'" { 
  Set-ListFieldValues -ListTitle $LibraryName -FieldInternal $ClassName -Values @{ 
    DefaultValue = $DefaultClass 
  } 
} | Out-Null

# RBAC: groups + roles
# Batch operations within single TryDo block
# Groups multiple related operations for atomic success/failure
TryDo "Ensure groups exist" {
  Ensure-SPGroup -GroupName $OwnersGroupName
  Ensure-SPGroup -GroupName $SCDGroupName
  Ensure-SPGroup -GroupName $JCDGroupName
} | Out-Null

# Permission inheritance breaking for security isolation
TryDo "Break library permission inheritance (no copy)" { 
  Ensure-BrokenInheritance -ListTitle $LibraryName 
} | Out-Null

# Enterprise RBAC implementation with SharePoint roles
# Maps business roles to SharePoint permission levels
TryDo "Grant Owners = Full Control" { 
  Grant-ListRoleCSOM -ListTitle $LibraryName -GroupName $OwnersGroupName -RoleName "Full Control" 
} | Out-Null

TryDo "Grant SCD Editors = Contribute" { 
  Grant-ListRoleCSOM -ListTitle $LibraryName -GroupName $SCDGroupName -RoleName "Contribute" 
} | Out-Null

TryDo "Grant JCD Reviewers = Read" { 
  Grant-ListRoleCSOM -ListTitle $LibraryName -GroupName $JCDGroupName -RoleName "Read" 
} | Out-Null

# Seed demo members
# Array parameter passing for bulk operations
# Each $Seed* variable contains array of user email addresses
TryDo "Seed Owners group members" { 
  Ensure-GroupMembers -GroupName $OwnersGroupName -Members $SeedOwners 
} | Out-Null

TryDo "Seed SCD Editors members" { 
  Ensure-GroupMembers -GroupName $SCDGroupName -Members $SeedSCDMembers 
} | Out-Null

TryDo "Seed JCD Reviewers members" { 
  Ensure-GroupMembers -GroupName $JCDGroupName -Members $SeedJCDMembers 
} | Out-Null

# Verification
# Direct Step call without TryDo wrapper for section headers
Step "Verification summary"

# Complex pipeline for formatted output
# Chains Get -> Select -> Format -> Out-String -> Write-Host
TryDo "List content types on '$LibraryName'" {
  Get-PnPContentType -List $LibraryName | 
    Select-Object Name,StringId | 
    Format-Table | 
    Out-String | 
    Write-Host
} | Out-Null

# CSOM property loading with verification display
TryDo "Show CT field links (Name, Required)" {
  # Load the content type with its field links
  $ctList = Get-PnPContentType -List $LibraryName -Identity $CtName -Includes FieldLinks
  Get-PnPProperty -ClientObject $ctList -Property FieldLinks
  
  # Pipeline formatting for table display
  $ctList.FieldLinks | 
    Select-Object Name,Required | 
    Format-Table | 
    Out-String | 
    Write-Host
} | Out-Null

# Manual formatting with string interpolation
# Different approaches to data presentation
TryDo "Show list fields (Indexed, Default)" {
  $f1 = Get-PnPField -List $LibraryName -Identity $OpLevelName
  $f2 = Get-PnPField -List $LibraryName -Identity $ClassName
  
  # String formatting with alignment and padding
  # {0,-20} = left-align in 20 characters, {1,-5} = left-align in 5 characters
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f1.Title, $f1.Indexed, $f1.DefaultValue)
  Write-Host ("   {0,-20} Indexed={1,-5} Default={2}" -f $f2.Title, $f2.Indexed, $f2.DefaultValue)
} | Out-Null

# Advanced CSOM verification with role enumeration
# Complex SharePoint object model navigation
TryDo "Show role assignments on '$LibraryName' (CSOM)" {
  # Get SharePoint context and list object
  $ctx = Get-PnPContext
  $list = Get-PnPList -Identity $LibraryName -ErrorAction Stop
  
  # Explicit loading and execution pattern
  $ctx.Load($list.RoleAssignments)
  $ctx.ExecuteQuery()

  # Nested property loading in foreach loop
  # Must load each role assignment's properties individually
  foreach ($ra in $list.RoleAssignments) {
    $ctx.Load($ra.Member)
    $ctx.Load($ra.RoleDefinitionBindings)
    $ctx.ExecuteQuery()
    
    # Property extraction and collection transformation
    $principal = $ra.Member.Title
    
    # ForEach-Object with property extraction and joining
    # Similar to Kotlin's map{}.joinToString()
    $roles = ($ra.RoleDefinitionBindings | ForEach-Object { $_.Name }) -join ", "
    
    # Formatted output for role assignments
    Write-Host ("   {0} : {1}" -f $principal, $roles)
  }
} | Out-Null

# Escape sequence for newline and final status message
# `n creates newline character (like \n in other languages)
Write-Host "`nCompleted. Review ✔/✖ above for outcomes and any follow-ups."