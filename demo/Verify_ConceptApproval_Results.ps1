<#
.SYNOPSIS
Verification and monitoring script for GFI Concept Approval flow

.DESCRIPTION
This script provides comprehensive verification and monitoring capabilities for the concept approval workflow:
- Queries Dataverse tables for approval status and errors
- Validates SharePoint document metadata updates
- Checks Power Automate flow run history
- Generates operational reports for stakeholders

.PARAMETER TenantId
Azure AD tenant identifier

.PARAMETER OrgUrl
Dataverse organization URL

.PARAMETER ClientId
Azure AD app registration client ID

.PARAMETER CertificateThumbprint
Certificate thumbprint for authentication

.PARAMETER SharePointSiteUrl
SharePoint site URL

.PARAMETER FlowEnvironmentId
Power Platform environment ID containing the flow

.EXAMPLE
.\Verify_ConceptApproval_Results.ps1 -TenantId "YOUR_TENANT_ID" -OrgUrl "https://orgXXXXXX.crm.dynamics.com/" -ClientId "YOUR_CLIENT_ID" -CertificateThumbprint "YOUR_CERTIFICATE_THUMBPRINT"

#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId = "YOUR_TENANT_ID",
    
    [Parameter(Mandatory=$false)]
    [string]$OrgUrl = "https://orgXXXXXX.crm.dynamics.com/",  # Default: Commercial; Use .crm.dynamics.us for GCC or .crm.microsoftdynamics.us for GCC High
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentId = "YOUR_ENVIRONMENT_ID",
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId = "YOUR_CLIENT_ID",
    
    [Parameter(Mandatory=$false)]
    [string]$CertThumbprint = "YOUR_CERTIFICATE_THUMBPRINT",
    
    [Parameter(Mandatory=$false)]
    [string]$SharePointSiteUrl = "https://yourtenant.sharepoint.com/sites/YourSite",
    
    [Parameter(Mandatory=$false)]
    [string]$FlowApiUrl = "https://api.flow.microsoft.com",  # Default: Commercial; Use gov.api.flow.microsoft.us for GCC/GCC High
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDataverseCheck,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipFlowCheck,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipSharePointCheck
)

# Validate endpoint configuration for GCC/GCC High compliance
function Test-EndpointCompliance {
    if ($OrgUrl -match "\.com/$") {
        Write-Warning "⚠️ Using commercial cloud endpoint ($OrgUrl). For GCC/GCC High compliance, ensure endpoint uses .us domains."
    } else {
        Write-Host "✔ Endpoint configuration validated for government cloud ($OrgUrl)" -ForegroundColor Green
    }
    
    if ($FlowApiUrl -match "\.com$") {
        Write-Warning "⚠️ Using commercial flow API endpoint ($FlowApiUrl). For GCC/GCC High compliance, use gov.api.flow.microsoft.us."
    } else {
        Write-Host "✔ Flow API endpoint validated for government cloud ($FlowApiUrl)" -ForegroundColor Green
    }
}

Test-EndpointCompliance

# Check FIPS 140-2 compliance for DoD environments
function Test-FIPSCompliance {
    Write-Host "`nChecking FIPS 140-2 encryption compliance..." -ForegroundColor Cyan
    
    # Check if FIPS mode is enabled (Windows)
    if ($IsWindows -or $env:OS -match "Windows") {
        try {
            $fipsEnabled = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled" -ErrorAction SilentlyContinue
            if ($fipsEnabled.Enabled -eq 1) {
                Write-Host "✔ FIPS 140-2 mode enabled on Windows" -ForegroundColor Green
                Write-AuditLog -Message "FIPS 140-2 mode enabled on Windows" -Level "SUCCESS"
                return $true
            } else {
                Write-Warning "⚠️ FIPS 140-2 mode NOT enabled on Windows"
                Write-Host "For DoD IL4/IL5 environments, enable FIPS mode:" -ForegroundColor Yellow
                Write-Host "  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy' -Name 'Enabled' -Value 1" -ForegroundColor Yellow
                Write-Host "Note: FIPS 140-2 is required for DoD contracts but may not be necessary for commercial/civilian environments" -ForegroundColor Gray
                Write-AuditLog -Message "FIPS 140-2 mode NOT enabled - required for DoD IL4/IL5" -Level "WARNING"
                return $false
            }
        }
        catch {
            Write-Warning "⚠️ Could not check FIPS status: $($_.Exception.Message)"
            Write-AuditLog -Message "Could not check FIPS status: $($_.Exception.Message)" -Level "WARNING"
            return $false
        }
    }
    # Check for Linux/macOS (kernel parameter or OpenSSL FIPS module)
    elseif ($IsLinux -or $IsMacOS) {
        Write-Warning "⚠️ FIPS 140-2 compliance check not automated for Linux/macOS"
        Write-Host "For DoD IL4/IL5 environments on Linux, ensure 'fips=1' kernel parameter is set" -ForegroundColor Yellow
        Write-Host "Note: FIPS 140-2 is required for DoD contracts but may not be necessary for commercial/civilian environments" -ForegroundColor Gray
        Write-AuditLog -Message "FIPS 140-2 compliance check not automated for Linux/macOS" -Level "WARNING"
        return $false
    }
    
    return $false
}

Test-FIPSCompliance

# TECHNIQUE: Import required modules with error handling
function Import-RequiredModules {
    $modules = @(
        'Microsoft.Graph.Authentication',
        'PnP.PowerShell',
        'Microsoft.PowerApps.Administration.PowerShell'
    )
    
    foreach ($module in $modules) {
        try {
            Import-Module $module -ErrorAction Stop
            Write-Host "✔ Loaded module: $module" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to load module: $module. Install with: Install-Module $module"
            return $false
        }
    }
    return $true
}

# Function to get authentication tokens for Dataverse and Power Platform
function Get-AuthenticationTokens {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertThumbprint,
        [string]$OrgUrl
    )
    
    # Check certificate expiration
    Test-CertificateExpiration -Thumbprint $CertThumbprint
    
    # Get tokens using MSAL.PS
    $dataverseTokenResult = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Scopes "$OrgUrl/.default" -CertificateThumbprint $CertThumbprint
    $powerPlatformTokenResult = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Scopes "https://service.powerapps.com/.default" -CertificateThumbprint $CertThumbprint
    
    $dataverseToken = $dataverseTokenResult.AccessToken
    $powerPlatformToken = $powerPlatformTokenResult.AccessToken
    
    # Clear plaintext tokens from memory as soon as possible
    $dataverseTokenResult = $null
    $powerPlatformTokenResult = $null
    [System.GC]::Collect()
    
    return @{
        DataverseHeaders = @{ 
            Authorization = "Bearer $dataverseToken"
            'Content-Type' = 'application/json'
            Accept = 'application/json'
        }
        PowerPlatformHeaders = @{
            Authorization = "Bearer $powerPlatformToken"
            'Content-Type' = 'application/json'
        }
    }
}

# TECHNIQUE: Retry wrapper for API calls to handle transient errors
function Invoke-RestMethodWithRetry {
    param($Method, $Uri, $Headers, $MaxRetries = 3, $RetryDelay = 1000)
    
    $attempt = 0
    do {
        try {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
        }
        catch {
            # TECHNIQUE: Handle HTTP 429 (Too Many Requests) and other transient errors
            if ($_.Exception.Response.StatusCode -eq 429 -and $attempt -lt $MaxRetries) {
                Write-Host "  ⚠ Rate limited (429), retrying in $($RetryDelay)ms..." -ForegroundColor Yellow
                Start-Sleep -Milliseconds $RetryDelay
                $attempt++
                $RetryDelay = $RetryDelay * 2  # Exponential backoff
                continue
            }
            throw $_
        }
    } while ($attempt -lt $MaxRetries)
}

# TECHNIQUE: Comprehensive Dataverse query with analytics and dynamic option set mapping
function Get-ConceptStatusAnalytics {
    param($Headers, $OrgUrl, $DaysBack)
    
    Write-Host "`nQuerying ConceptStatus records..." -ForegroundColor Cyan
    
    # TECHNIQUE: Query option set metadata to map values dynamically
    try {
        $optionSetUri = "$OrgUrl/api/data/v9.2/GlobalOptionSetDefinitions(Name='gfi_gfi_approvalstatus')"
        $optionSetResponse = Invoke-RestMethodWithRetry -Method GET -Uri $optionSetUri -Headers $Headers
        $statusMap = @{}
        $optionSetResponse.Options | ForEach-Object { 
            $statusMap[$_.Value] = $_.Label.LocalizedLabels[0].Label 
        }
        Write-Host "✔ Option set metadata loaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Could not load option set metadata, using fallback values" -ForegroundColor Yellow
        # Fallback to setup script values
        $statusMap = @{
            100000000 = "Pending"
            100000001 = "Approved" 
            100000002 = "Rejected"
        }
    }
    
    # Calculate date filter for recent records
    $filterDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # TECHNIQUE: OData query with filtering and ordering
    $query = @(
        '$select=gfi_documentid,gfi_approvalstatus,gfi_remindercount,gfi_approvalrequestedat,gfi_escalatedto,createdon,modifiedon',
        '$filter=createdon ge ' + $filterDate,
        '$orderby=createdon desc'
    ) -join '&'
    
    $uri = "$OrgUrl/api/data/v9.2/gfi_conceptstatuses?$query"
    
    try {
        $response = Invoke-RestMethodWithRetry -Method GET -Uri $uri -Headers $Headers
        
        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) ConceptStatus records from last $DaysBack days" -ForegroundColor Green
            
            # TECHNIQUE: Data analysis and aggregation using dynamic status mapping
            $pendingValue = ($statusMap.GetEnumerator() | Where-Object { $_.Value -eq "Pending" }).Key
            $approvedValue = ($statusMap.GetEnumerator() | Where-Object { $_.Value -eq "Approved" }).Key
            $rejectedValue = ($statusMap.GetEnumerator() | Where-Object { $_.Value -eq "Rejected" }).Key
            
            $pendingCount = ($response.value | Where-Object { $_.gfi_approvalstatus -eq $pendingValue }).Count
            $approvedCount = ($response.value | Where-Object { $_.gfi_approvalstatus -eq $approvedValue }).Count
            $rejectedCount = ($response.value | Where-Object { $_.gfi_approvalstatus -eq $rejectedValue }).Count
            
            Write-Host "`nApproval Status Summary:" -ForegroundColor Yellow
            Write-Host "  Pending: $pendingCount" -ForegroundColor $(if ($pendingCount -gt 0) { "Yellow" } else { "Gray" })
            Write-Host "  Approved: $approvedCount" -ForegroundColor $(if ($approvedCount -gt 0) { "Green" } else { "Gray" })
            Write-Host "  Rejected: $rejectedCount" -ForegroundColor $(if ($rejectedCount -gt 0) { "Red" } else { "Gray" })
            
            # Display detailed records
            Write-Host "`nDetailed Records:" -ForegroundColor Yellow
            $response.value | Select-Object @{
                Name='DocumentID'; Expression={$_.gfi_documentid}
            }, @{
                Name='Status'; Expression={
                    if ($statusMap.ContainsKey($_.gfi_approvalstatus)) {
                        $statusMap[$_.gfi_approvalstatus]
                    } else {
                        "Unknown ($($_.gfi_approvalstatus))"
                    }
                }
            }, @{
                Name='Reminders'; Expression={$_.gfi_remindercount}
            }, @{
                Name='RequestedAt'; Expression={
                    if ($_.gfi_approvalrequestedat) { 
                        [DateTime]::Parse($_.gfi_approvalrequestedat).ToString("yyyy-MM-dd HH:mm") 
                    } else { "Not set" }
                }
            }, @{
                Name='Created'; Expression={[DateTime]::Parse($_.createdon).ToString("yyyy-MM-dd HH:mm")}
            } | Format-Table -AutoSize
            
            return $response.value
        } else {
            Write-Host "No ConceptStatus records found in last $DaysBack days" -ForegroundColor Yellow
            return @()
        }
    }
    catch {
        Write-Error "Failed to query ConceptStatus: $($_.Exception.Message)"
        return @()
    }
}

# TECHNIQUE: Error monitoring and alerting
function Get-FlowErrorAnalysis {
    param($Headers, $OrgUrl, $DaysBack)
    
    Write-Host "`nQuerying FlowErrors records..." -ForegroundColor Cyan
    
    $filterDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $query = @(
        '$select=gfi_errormessage,gfi_timestamp,createdon',
        '$filter=createdon ge ' + $filterDate,
        '$orderby=createdon desc',
        '$top=50'
    ) -join '&'
    
    # TECHNIQUE: Fixed OData entity name (removed double plural)
    $uri = "$OrgUrl/api/data/v9.2/gfi_flowerrors?$query"
    
    try {
        $response = Invoke-RestMethodWithRetry -Method GET -Uri $uri -Headers $Headers
        
        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) FlowError records from last $DaysBack days" -ForegroundColor Red
            
            # TECHNIQUE: Enhanced error categorization with Power Platform specific patterns
            $errorPatterns = $response.value | Group-Object { 
                # Extract error type from message with comprehensive patterns
                if ($_.gfi_errormessage -match "HTTP|timeout|connection") { "Network" }
                elseif ($_.gfi_errormessage -match "authentication|unauthorized|forbidden") { "Authentication" }
                elseif ($_.gfi_errormessage -match "validation|required|format") { "Validation" }
                elseif ($_.gfi_errormessage -match "quota|throttle|limit") { "Throttling" }
                elseif ($_.gfi_errormessage -match "dataverse|entity|attribute") { "Dataverse" }
                elseif ($_.gfi_errormessage -match "sharepoint|list|library") { "SharePoint" }
                else { "Other" }
            }
            
            Write-Host "`nError Categories:" -ForegroundColor Yellow
            foreach ($pattern in $errorPatterns) {
                Write-Host "  $($pattern.Name): $($pattern.Count) errors" -ForegroundColor Red
            }
            
            Write-Host "`nRecent Errors:" -ForegroundColor Yellow
            $response.value | Select-Object @{
                Name='Timestamp'; Expression={[DateTime]::Parse($_.createdon).ToString("yyyy-MM-dd HH:mm")}
            }, @{
                Name='Error'; Expression={
                    if ($_.gfi_errormessage.Length -gt 80) {
                        $_.gfi_errormessage.Substring(0, 77) + "..."
                    } else {
                        $_.gfi_errormessage
                    }
                }
            } | Format-Table -AutoSize
            
            return $response.value
        } else {
            Write-Host "No FlowError records found in last $DaysBack days" -ForegroundColor Green
            return @()
        }
    }
    catch {
        Write-Error "Failed to query FlowErrors: $($_.Exception.Message)"
        return @()
    }
}

# TECHNIQUE: SharePoint integration verification
function Test-SharePointIntegration {
    param($SharePointSiteUrl, $ClientId, $CertThumbprint, $TenantId)
    
    Write-Host "`nVerifying SharePoint integration..." -ForegroundColor Cyan
    
    try {
        Connect-PnPOnline -Url $SharePointSiteUrl -ClientId $ClientId -Thumbprint $CertThumbprint -Tenant $TenantId
        
        # Check library exists and is configured
        $library = Get-PnPList -Identity "Strategic Concepts" -ErrorAction SilentlyContinue
        if ($library) {
            Write-Host "✔ Strategic Concepts library found" -ForegroundColor Green
            
            # Get recent items to check for flow processing
            $recentItems = Get-PnPListItem -List "Strategic Concepts" -PageSize 10 | 
                Sort-Object Id -Descending | 
                Select-Object -First 5
            
            if ($recentItems) {
                Write-Host "✔ Found $($recentItems.Count) recent documents" -ForegroundColor Green
                
                Write-Host "`nRecent Documents:" -ForegroundColor Yellow
                foreach ($item in $recentItems) {
                    # TECHNIQUE: Fixed column name from RiskLevel to OperationalLevel
                    $operationalLevel = if ($item["OperationalLevel"]) { $item["OperationalLevel"] } else { "Not set" }
                    $classification = if ($item["Classification"]) { $item["Classification"] } else { "Not set" }
                    
                    Write-Host "  ID: $($item.Id) | Name: $($item["FileLeafRef"]) | Operational Level: $operationalLevel | Class: $classification"
                }
            } else {
                Write-Host "⚠ No documents found in library" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✖ Strategic Concepts library not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Error "SharePoint integration test failed: $($_.Exception.Message)"
    }
}

# TECHNIQUE: Power Automate flow monitoring
function Get-FlowRunHistory {
    param($Headers, $EnvironmentId, $DaysBack)
    
    if (-not $EnvironmentId) {
        Write-Host "⚠ Flow environment ID not provided, skipping flow run history" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nQuerying Power Automate flow runs..." -ForegroundColor Cyan
    
    try {
        # Get flows in environment
        $flowsUri = "$FlowApiUrl/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows"
        $flows = Invoke-RestMethodWithRetry -Method GET -Uri $flowsUri -Headers $Headers
        
        # TECHNIQUE: More specific flow name filter or use exact flow GUID for reliability
        # For now, keeping loose filter but can be replaced with exact flow GUID
        $conceptFlow = $flows.value | Where-Object { $_.properties.displayName -like "*Concept*Approval*" }
        # Alternative: Use exact flow GUID if known from setup
        # $conceptFlow = $flows.value | Where-Object { $_.name -eq 'YOUR-FLOW-GUID-HERE' }
        
        if ($conceptFlow) {
            Write-Host "✔ Found Concept Approval flow: $($conceptFlow.properties.displayName)" -ForegroundColor Green
            
            # Get recent runs
            $runsUri = "$FlowApiUrl/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows/$($conceptFlow.name)/runs"
            $runs = Invoke-RestMethodWithRetry -Method GET -Uri $runsUri -Headers $Headers
            
            $recentRuns = $runs.value | Where-Object { 
                [DateTime]::Parse($_.properties.startTime) -gt (Get-Date).AddDays(-$DaysBack) 
            } | Sort-Object { $_.properties.startTime } -Descending
            
            if ($recentRuns) {
                Write-Host "Found $($recentRuns.Count) flow runs in last $DaysBack days" -ForegroundColor Green
                
                Write-Host "`nFlow Run Summary:" -ForegroundColor Yellow
                $recentRuns | Select-Object @{
                    Name='StartTime'; Expression={[DateTime]::Parse($_.properties.startTime).ToString("yyyy-MM-dd HH:mm")}
                }, @{
                    Name='Status'; Expression={$_.properties.status}
                }, @{
                    Name='Duration'; Expression={
                        if ($_.properties.endTime) {
                            $start = [DateTime]::Parse($_.properties.startTime)
                            $end = [DateTime]::Parse($_.properties.endTime)
                            "{0:F1}s" -f ($end - $start).TotalSeconds
                        } else { "Running" }
                    }
                } | Format-Table -AutoSize
            } else {
                Write-Host "No flow runs found in last $DaysBack days" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠ Concept Approval flow not found in environment" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to query flow runs: $($_.Exception.Message)"
    }
}

# TECHNIQUE: Comprehensive health report generation with dynamic output path
function New-HealthReport {
    param(
        $ConceptData, 
        $ErrorData, 
        $OutputPath = (Join-Path $env:TEMP "health-report-$(Get-Date -Format 'yyyyMMddHHmmss').md")
    )
    
    Write-Host "`nGenerating health report..." -ForegroundColor Cyan
    
    $report = @"
# GFI Concept Approval Flow - Health Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Summary
- **ConceptStatus Records**: $($ConceptData.Count)
- **FlowError Records**: $($ErrorData.Count)
- **Overall Health**: $(if ($ErrorData.Count -eq 0) { "✔ Healthy" } else { "⚠ Issues Detected" })

## Approval Status Overview
$( if ($ConceptData.Count -gt 0) {
    # Note: This should use dynamic status mapping from the calling function
    $pending = ($ConceptData | Where-Object { $_.gfi_approvalstatus -eq 100000000 }).Count
    $approved = ($ConceptData | Where-Object { $_.gfi_approvalstatus -eq 100000001 }).Count
    $rejected = ($ConceptData | Where-Object { $_.gfi_approvalstatus -eq 100000002 }).Count
    
    "- Pending: $pending`n- Approved: $approved`n- Rejected: $rejected"
} else {
    "No approval data available"
})

## Error Analysis
$( if ($ErrorData.Count -gt 0) {
    "⚠ **$($ErrorData.Count) errors detected** - Review required"
} else {
    "✔ No errors detected in monitoring period"
})

## Recommendations
$( if ($ErrorData.Count -gt 5) {
    "- **High error rate detected** - Investigate flow configuration`n- Check SharePoint connectivity and permissions`n- Verify Dataverse table permissions"
} elseif ($ConceptData.Count -eq 0) {
    "- **No approval data** - Verify flow is triggering on document uploads`n- Check SharePoint library configuration"
} else {
    "- System operating within normal parameters`n- Continue monitoring for trends"
})

---
*Report generated by GFI Concept Approval monitoring system*
"@

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "✔ Health report saved to: $OutputPath" -ForegroundColor Green
}

# ==================== MAIN EXECUTION ====================

# Enterprise logging and error handling infrastructure
$ErrorActionPreference = "Stop"

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "Verify_ConceptApproval_Results"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    $colorMap = @{
        "INFO" = "White"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
        "STEP" = "Cyan"
        "CRITICAL" = "Magenta"
    }
    
    Write-Host $logEntry -ForegroundColor $colorMap[$Level]
    # Append to a log file for audit purposes (FedRAMP AU-2, AU-12)
    $logFile = "AuditLog_$(Get-Date -Format 'yyyyMMdd').log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function TryDo {
    param([string]$Title, [scriptblock]$Action)
    Write-Host "==> $Title" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "   ✔ $Title" -ForegroundColor Green
        Write-AuditLog -Message "Operation '$Title' completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Host "   ✖ $Title" -ForegroundColor Red
        Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        Write-AuditLog -Message "Operation '$Title' failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

Write-Host "GFI Concept Approval Flow - Verification & Monitoring" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Yellow

# TECHNIQUE: Session tracking for monitoring and audit trail (cleaned up unused parameters)
$sessionInfo = @{
    SessionId = [System.Guid]::NewGuid().ToString()
    Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    TenantId = $TenantId
    InstanceUrl = $OrgUrl
    ClusterGeo = "US"
    BuildVersion = "0.0.20250923.1-2509.2-prod"
}

Write-Host "Monitoring Session:" -ForegroundColor Cyan
Write-Host "  Session ID: $($sessionInfo.SessionId)" -ForegroundColor Gray
Write-Host "  Timestamp: $($sessionInfo.Timestamp)" -ForegroundColor Gray
Write-Host "  Instance URL: $($sessionInfo.InstanceUrl)" -ForegroundColor Gray
Write-Host "  Cluster Geo: $($sessionInfo.ClusterGeo)" -ForegroundColor Gray

# Step 1: Load required modules
if (-not (Import-RequiredModules)) {
    Write-Error "Failed to load required modules. Exiting."
    exit 1
}

# Step 2: Authenticate to services
try {
    $authTokens = Get-AuthenticationTokens -TenantId $TenantId -ClientId $ClientId -CertThumbprint $CertThumbprint -OrgUrl $OrgUrl
    Write-Host "✔ Authentication successful" -ForegroundColor Green
    Write-AuditLog -Message "Authentication to services successful" -Level "SUCCESS"
}
catch {
    Write-Host "✖ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog -Message "Authentication failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Step 3: Query and analyze ConceptStatus data
$conceptData = Get-ConceptStatusAnalytics -Headers $authTokens.DataverseHeaders -OrgUrl $OrgUrl -DaysBack $DaysBack

# Step 4: Query and analyze FlowErrors data
$errorData = Get-FlowErrorAnalysis -Headers $authTokens.DataverseHeaders -OrgUrl $OrgUrl -DaysBack $DaysBack

# Step 5: Verify SharePoint integration
Test-SharePointIntegration -SharePointSiteUrl $SharePointSiteUrl -ClientId $ClientId -CertThumbprint $CertThumbprint -TenantId $TenantId

# Step 6: Check Power Automate flow runs (if environment provided)
if ($EnvironmentId) {
    Get-FlowRunHistory -Headers $authTokens.PowerPlatformHeaders -EnvironmentId $EnvironmentId -DaysBack $DaysBack
}

# Step 7: Generate health report
New-HealthReport -ConceptData $conceptData -ErrorData $errorData

# Final summary
Write-Host "`n" -NoNewline
Write-Host "====================================================" -ForegroundColor Yellow
Write-Host "VERIFICATION COMPLETE" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Yellow

$healthStatus = if ($errorData.Count -eq 0 -and $conceptData.Count -gt 0) { 
    "✔ HEALTHY" 
} elseif ($errorData.Count -gt 0) { 
    "⚠ ISSUES DETECTED" 
} else { 
    "📊 MONITORING" 
}

Write-Host "System Status: $healthStatus" -ForegroundColor $(
    if ($healthStatus.Contains("HEALTHY")) { "Green" }
    elseif ($healthStatus.Contains("ISSUES")) { "Red" }
    else { "Yellow" }
)

Write-Host "`nFor detailed analysis, review:" -ForegroundColor Cyan
Write-Host "- ConceptStatus records: $($conceptData.Count) found" -ForegroundColor Gray
Write-Host "- FlowError records: $($errorData.Count) found" -ForegroundColor Gray
Write-Host "- Health report: ./health-report.md" -ForegroundColor Gray

