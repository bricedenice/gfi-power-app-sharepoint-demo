# GFI Strategic Concepts Demo Environment

## Overview
PowerShell automation scripts for Microsoft 365 and SharePoint demo environment setup. Simulates **Global Force Integration (GFI) Strategic Concepts Division** user management, group provisioning, and SharePoint integration.

## Sway Presentation
https://sway.cloud.microsoft/xs9JB7bGQeJPUoSq?ref=Link

## Repository Structure
```
/GFI-SCD-Demo/
├── demo/                        # Template scripts for public use
├── development/                 # Development scripts (excluded from repository)
├── config-template.ps1          # Configuration template
├── users-template.csv           # User data template
└── README.md                    # Documentation
```

## Prerequisites
* PowerShell 7.x
* Microsoft.Graph PowerShell module
* PnP.PowerShell module
* Azure AD app registration with appropriate permissions

## Setup Instructions

### Configuration
1. Copy configuration template
   ```powershell
   Copy-Item config-template.ps1 config.ps1
   ```

2. Edit config.ps1 with tenant-specific values
   * Replace placeholder tenant information
   * Add Azure AD app registration client ID
   * Include certificate thumbprint for authentication
   * Update SharePoint site URLs

### User Data Preparation
1. Copy user template
   ```powershell
   Copy-Item users-template.csv users.csv
   ```

2. Populate users.csv with demo user accounts
   * Use tenant-specific email domains
   * Define appropriate job titles and departments
   * Set secure passwords for demo accounts

### Script Execution
Execute scripts in sequence:
```powershell
# Create demo users in Azure AD
.\demo\Create_Users.ps1

# Add users to Microsoft 365 groups
.\demo\Add_To_M365_Group.ps1

# Configure SharePoint site permissions
.\demo\Add_To_Groups.ps1
```

## Script Descriptions

| Script | Function | Dependencies |
|--------|----------|--------------|
| Create_Users.ps1 | Bulk user creation in Azure AD | Microsoft.Graph |
| Add_To_M365_Group.ps1 | Microsoft 365 group membership | Microsoft.Graph |
| Add_To_Groups.ps1 | SharePoint site permission configuration | PnP.PowerShell |

## Security Configuration

### Azure AD App Registration Requirements
* API permissions
  * Microsoft Graph: User.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All
  * SharePoint: Sites.FullControl.All
* Certificate-based authentication (recommended)
* Administrative consent required

### Certificate Setup
1. Generate certificate (self-signed or enterprise CA)
2. Upload public key to Azure AD app registration
3. Reference certificate thumbprint in configuration file

## Demo Environment Structure

### Organizational Structure
* **Command**: Leadership positions (Director, Deputy Director, Chief of Staff)
* **Strategic Concepts Division**: Strategy and analysis personnel
* **Joint Concepts Division**: Development and implementation team
* **Data Science Team**: Analytics support

### SharePoint Groups
* **SCD Editors**: Contribute permissions for Strategic Concepts library
* **JCD Reviewers**: Read permissions for Strategic Concepts library
* **Standard hierarchy**: Owners, Members, Visitors

## Security Considerations
* Template files contain no production credentials
* Development folder excluded from version control
* Certificate authentication recommended for production use
* All operations logged through Microsoft 365 audit infrastructure
