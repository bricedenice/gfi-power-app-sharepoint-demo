# Configuration template for GFI Strategic Concepts demo environment
# Copy this file to 'config.ps1' and populate with tenant-specific values

@{
    # Microsoft 365 tenant information
    TenantId = "YourTenant.onmicrosoft.com"
    TenantShort = "yourtenant"
    
    # Azure AD app registration details
    ClientId = "your-app-registration-client-id-here"
    CertificateThumbprint = "your-certificate-thumbprint-here"
    
    # SharePoint site configuration
    SharePointSiteUrl = "https://yourtenant.sharepoint.com/sites/gfi-strategic-concepts"
    SharePointAdminUrl = "https://yourtenant-admin.sharepoint.com"
    
    # Demo user configuration
    DefaultPassword = "YourSecurePassword123!"
    UsersCSVPath = "./users.csv"
    
    # Microsoft 365 group identifiers
    SCDEditorsGroupId = "your-scd-editors-group-id"
    JCDReviewersGroupId = "your-jcd-reviewers-group-id"
    
    # File sync configuration
    SourcePath = "/path/to/source/files"
    DestinationFolder = "/sites/yoursite/Shared Documents/YourFolder"
}
