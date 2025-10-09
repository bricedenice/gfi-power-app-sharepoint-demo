# Demo Scripts and Templates

## Overview

Enterprise-ready PowerShell and shell scripts for Microsoft 365, SharePoint, and Power Platform automation. These templates demonstrate production-quality infrastructure-as-code practices for DoD/GCC High environments.

## Categories

### User and Group Management
- `Create_Users.ps1` - Bulk user provisioning in Azure AD
- `Add_To_M365_Group.ps1` - Microsoft 365 group membership automation
- `Add_To_Groups.ps1` - SharePoint site permission configuration
- `Find_GroupID.ps1` - Group ID lookup utility
- `Profile_Enrichment_CSV.ps1` - User profile data enrichment

### SharePoint Governance
- `Add_ContentTypes_SiteColumns.ps1` - Content type and site column provisioning with CSOM
- `Configure_RBAC.ps1` - Role-based access control configuration for libraries
- `Verify_ContentTypes_Columns.ps1` - Validation script for content type deployment
- `Sync_Script.ps1` - Data synchronization utility

### Power Platform ALM
- `Deploy_PowerAutomate_Solution.ps1` - Power Platform CLI-based solution deployment
- `Verify_ConceptApproval_Results.ps1` - Flow execution validation
- `flow-commands.sh` - Power Automate flow management CLI wrapper
- `solution-commands.sh` - Power Platform solution lifecycle management

#### GFIConceptFlow Solution Progress
- **Status**: In Progress
- **Enterprise Integrations**: Added connectors for Jira, ServiceNow, and Salesforce to meet non-negotiable enterprise integration requirements.
- **DoD Compliance**: Ensuring all modifications align with DoD standards for security and documentation.
- **Security Enhancements** (October 2025):
  - Added FIPS 140-2 encryption compliance checks to all deployment scripts
  - Enforced non-interactive authentication detection and warnings
  - Updated documentation to clarify DoD vs civilian environment requirements
  - All scripts now include automated compliance checks with warnings (non-blocking for flexibility)
- **Next Steps**: Pack and deploy the updated solution to the environment for testing.

### Documentation
- `How-To-Use-AI-In-GCC.md` - Azure OpenAI integration guide for GCC High
- `JSON-Dev-Checklist.md` - Comprehensive checklist for Power Automate JSON development

## Key Features

### Enterprise Patterns
- Certificate-based authentication (app-only, no interactive prompts)
- Idempotent scripts (safe to re-run)
- Comprehensive error handling with detailed logging
- CSOM and PnP.PowerShell for SharePoint automation
- Power Platform CLI for ALM workflows

### DoD/GCC Compliance
- Azure Government region support (IL4/IL5)
- FIPS 140-2 encryption compliance checks (mandatory for DoD, optional for civilian)
- Non-interactive authentication enforcement for production environments
- Audit logging and compliance tracking (FedRAMP AU-2, AU-12)
- Sites.Selected permission scoping
- CUI handling best practices

#### Authentication Requirements
- **DoD/Production Environments**: Non-interactive authentication (service principal or certificate-based) is **required**
- **Dev/Test/Civilian Environments**: Interactive authentication is **acceptable** but non-interactive is recommended
- All scripts include authentication method detection and warnings

#### FIPS 140-2 Encryption
- **DoD IL4/IL5**: FIPS 140-2 compliant encryption is **mandatory**
- **Commercial/Civilian**: FIPS 140-2 is **optional** but can be enabled for enhanced security
- Scripts include automated FIPS compliance checks with warnings (non-blocking for flexibility)
- Configuration guides provided for Windows, Linux, and macOS

### Code Quality
- Functional programming patterns (immutability, pure functions, higher-order functions)
- Extensive inline documentation following AIprompt standards
- Verification commands and output examples
- Template-driven configuration (no hardcoded credentials)

## Prerequisites

- PowerShell 7+
- PnP.PowerShell module
- Microsoft.Graph PowerShell module
- Power Platform CLI (pac)
- Azure AD app registration with certificate-based auth

## Usage

1. Copy template files to your workspace
2. Update placeholder values (YOUR_TENANT_ID, YOUR_CLIENT_ID, etc.)
3. Configure certificate-based authentication
4. Run scripts in sequence (see SETUP.md)

## Security Notes

All scripts in this folder use **placeholder values**. Before deploying:
- Replace all `YOUR_*` placeholders with actual tenant-specific values
- Store credentials in Azure Key Vault (not in scripts)
- Use service principals with least-privilege permissions
- Enable audit logging for all operations

## Technical Highlights

These scripts demonstrate:
- Advanced PowerShell patterns (splatting, pipeline optimization, functional approaches)
- CSOM object model manipulation for SharePoint
- Power Platform ALM with CLI automation
- Azure OpenAI integration in government clouds
- Complex RBAC scenarios with security groups and permission inheritance

Suitable for senior-level roles requiring:
- SharePoint/Power Platform architecture
- Federal contracting (DoD, civilian agencies)
- Enterprise ALM and DevOps practices
- Technical leadership and documentation skills

