# Power Automate Cloud Flow JSON Development Checklist

## Why This Checklist Exists

You've been there: three meetings deep, still waiting on a connector ID. Another email thread asking "which environment again?" The customer swears they sent the SharePoint site URL, but it's buried in Outlook somewhere between spam and that Teams notification you'll never read.

This checklist stops that. Fill it out in the first meeting—or better, send it beforehand. When you sit down to code a Power Automate flow from JSON, you have every environment ID, certificate thumbprint, Dataverse table name, and API endpoint already confirmed. No back-and-forth. No assumptions that break in production. No "quick call" at 4:45 PM because someone forgot to mention the flow needs to hit a custom connector.

This is how you build enterprise solutions without the endless loop of discovery calls and validation emails.

---

## 1. Environment and Authentication

Every flow runs in a specific Power Platform environment. Get this wrong and your flow deploys to Dev when it should be in Prod, or worse—deploys to the wrong tenant entirely. DoD/GovCloud environments sit in different Azure regions (US Gov Virginia for IL4/IL5), and that matters for compliance. Confirm the environment ID and type upfront.

### Power Platform Environment
Environment ID: ________________________ (e.g., f5bc0817-ccb7-eb2c-8137-23b0788c8404)
Type: [ ] Production [ ] Sandbox [ ] Default
Region: ________________________ (e.g., Azure Government - US Gov Virginia for IL4/IL5)
Verification Command: `pac env list`


### Authentication

Certificate-based authentication is the standard for production flows. Interactive auth works for dev/test, but fails in unattended scenarios. Confirm the client ID, certificate thumbprint, and where the cert lives (macOS Keychain vs Windows Cert Store). Entra ID permissions need to be scoped correctly—Sites.Selected for SharePoint is tighter than AllSites.Write, and DoD environments scrutinize this.

Client ID: ________________________ (e.g., bc2480b4-e677-4277-a4f3-9e67e9cbc476)
Certificate Thumbprint: ________________________ (e.g., BC0A1422EE9CAF1003F53EF7E195DA4B7D5AC3F6)
Certificate Location: [ ] macOS Keychain [ ] Windows Cert Store [ ] Other: ________________________
Fallback Authentication: [ ] Interactive [ ] Other: ________________________

Entra ID Permissions:
- Dynamics CRM: user_impersonation
- SharePoint: Sites.Selected or AllSites.Write
- Microsoft Graph: Teams.ReadWrite.All
- Approvals: Approvals.ReadWrite
- Other: ________________________

Verification Commands:
```powershell
Get-PnPAzureADApp -Identity [ClientId]
security find-certificate -c [Thumbprint] # macOS
Get-Item -Path Cert:\CurrentUser\My\[Thumbprint] # Windows
```

Tenant ID: ________________________ (e.g., 871d0c31-22b0-49ab-b4bd-7f145eaa7803)
Verification Command: `pac auth list`



## 2. Flow Requirements and Logic

Before writing a single action in JSON, you need to know what kicks off the flow and what it does. SharePoint triggers need list IDs (not just names—IDs change between environments). Recurrence schedules matter for SLA-driven workflows. Document the trigger parameters and expected outputs now, or debug them later when the flow silently fails because someone gave you a library name instead of a GUID.

### Trigger
Type: ________________________ (e.g., OpenApiConnection - GetOnNewFileItems)
Parameters:
- ________________________ (e.g., SharePoint site: https://culturalbridgelabs.sharepoint.com/sites/GFIStrategicConcepts)
- ________________________ (e.g., List ID: 5fe777ff-9fa1-4479-b4c8-7515071e8f0e)

Recurrence: [ ] None [ ] Frequency: ________________________ Interval: ________________________
Verification Command: `Get-PnPList -Identity "[ListName]"`


### Actions

List every action the flow performs. If Action 2 depends on Action 1's output, note it. If there's a condition ("If Classification is blank"), document the logic. Power Automate flows fail silently when expressions reference non-existent outputs. Writing this down forces you to think through dependencies before JSON typos waste hours.

Action 1: ________________________ (e.g., InitializeVariable - MissingClassification)
Type: ________________________
Parameters: ________________________

Action 2: ________________________ (e.g., CreateRecord - gfi_conceptstatuses)
Type: ________________________
Parameters: ________________________

Action 3: ________________________ (e.g., StartAndWaitForAnApproval)
Type: ________________________
Parameters: ________________________

Additional Actions: ________________________
Dependencies/Conditions: ________________________ (e.g., If Classification is blank)

### Outputs

What does success look like? Dataverse records created? Teams notification sent? Approval logged? Define the expected results and how to verify them. If you can't query the output table or check the destination, you can't prove the flow worked.

Expected Results: ________________________ (e.g., Dataverse records, Teams notifications)
Verification Method: ________________________ (e.g., Query gfi_ConceptStatus)



## 3. Connectors and Connections

Connectors are how Power Automate talks to SharePoint, Dataverse, Teams, or external APIs. Premium connectors (Dataverse, custom connectors) cost money and require licensing. Connection references store authentication details—get the logical names right or the flow can't authenticate. Custom connectors need OpenAPI definitions and auth configs (API keys, OAuth, etc.). Confirm connector availability in the target environment before coding.

### Connectors
- [ ] shared_sharepointonline (SharePoint)
- [ ] shared_commondataserviceforapps (Dataverse, Premium)
- [ ] shared_teams (Microsoft Teams)
- [ ] shared_approvals (Approvals)
- [ ] Custom: ________________________ (e.g., PSOpenAI)

Verification Command: `pac connector list --environment [EnvironmentId]`

### Connection References

Connection references link flows to authenticated connections. If you deploy a solution and the connection reference isn't bound, the flow won't run. Get the connection ID and logical name from the source environment, or plan to create new connections post-import.

Connection 1: ________________________ (e.g., shared-sharepointonl-815b782b-98e7-436f-a367-b18edaa0a599)
Logical Name: ________________________
Authentication: [ ] ClientCredentials [ ] Interactive

Connection 2: ________________________
Logical Name: ________________________
Authentication: [ ] ClientCredentials [ ] Interactive

Verification Command: `pac connection list --environment [EnvironmentId]`

### Custom Connectors (if applicable)

Custom connectors extend Power Automate to APIs it doesn't natively support. You need the API endpoint, OpenAPI definition (swagger file), and auth method (API key, OAuth, PAT). Test the connector in the environment before adding it to the flow because broken custom connectors fail silently.

API Endpoint: ________________________ (e.g., https://models.inference.ai.azure.com)
OpenAPI Definition: ________________________ (e.g., file path or URL)
Authentication: ________________________ (e.g., GitHub PAT)



## 4. Dataverse Schema

Dataverse is Power Platform's database. Flows that create/update records need exact table names (logical names, not display names), field names, and option set values. "Pending" might be 100000000 in one environment and 833060000 in another—hard-coding the wrong value breaks the flow. Get the schema details and primary key field upfront. Permissions matter too: flows fail silently if the service principal lacks write access.

### Tables
Table 1: ________________________ (e.g., gfi_conceptstatuses)
Logical Name: ________________________
Fields: ________________________ (e.g., gfi_name, gfi_approvalstatus)
Option Sets: ________________________ (e.g., gfi_approvalstatus: 100000000=Pending)
Primary Key: ________________________ (e.g., gfi_conceptstatusid)

Table 2: ________________________ (e.g., gfi_flowerrors)
Logical Name: ________________________
Fields: ________________________ (e.g., gfi_errormessage, gfi_timestamp)

Verification Command: `pac data schema export --table [TableName]`

### Permissions

Flows run under a service principal or user context. If the identity lacks read/write on the Dataverse table, the CreateRecord action fails with a cryptic "unauthorized" error. Verify security roles before deployment.

Read/Write Access for: [ ] ClientId [ ] User
Verification: Check make.powerapps.com > Settings > Security > Security Roles



## 5. SharePoint Configuration

SharePoint triggers and actions need exact site URLs and list IDs. List names change, GUIDs don't. Column names matter for expressions—if the flow references `Author/Email` but the column is `CreatedBy/Email`, it fails. Permissions are critical: flows need Contribute or higher to create/update items, and Sites.Selected scopes require explicit grants per site.

### Site and List
Site URL: ________________________ (e.g., https://culturalbridgelabs.sharepoint.com/sites/GFIStrategicConcepts)
List Name/ID: ________________________ (e.g., Strategic Concepts, 5fe777ff-9fa1-4479-b4c8-7515071e8f0e)
Columns: ________________________ (e.g., Title, Classification, Author/Email)
Verification Command: `Get-PnPList -Identity "[ListName]"`

### Permissions

Service principals with Sites.Selected need explicit site permissions. If the flow tries to read a library it can't access, you get "Access Denied." Verify permissions before deploying.

Access Level: [ ] Contribute [ ] Other: ________________________
Verification: Check SharePoint site permissions



## 6. Teams and Approval Configuration

Teams notifications and approvals need Group IDs and Channel IDs (not names). If you post to the wrong channel or send approvals to the wrong user, the flow works—but no one sees the output. Dynamic expressions (`@triggerOutputs()?['body/Author/Email']`) are powerful but break if the referenced field doesn't exist. Test approval routing before going live.

### Teams
Group ID: ________________________ (e.g., 165333bb-7d00-441e-b98e-651601a00523)
Channel ID: ________________________ (e.g., 19:e448s4uHpqxxof_MnL1yywMbAQzKW58_9D2W_0cKQBM1@thread.tacv2)
Recipients: ________________________ (e.g., user emails, dynamic expressions)
Verification Command: `Get-PnPTeamsChannel -GroupId [GroupId]`

### Approvals

Approval types matter: "First to Respond" ends when one person approves, "Everyone Must Approve" waits for all. Get assignee routing right—if the flow sends approvals to a service account, they'll pile up unread.

Type: [ ] Basic [ ] First to Respond [ ] Everyone Must Approve
Assignees: ________________________ (e.g., @triggerOutputs()?['body/Author/Email'])
Verification: Test in make.powerapps.com > Flows > Approvals



## 7. AI Integration (Optional)

AI-powered flows (document classification, sentiment analysis, etc.) require API endpoints, models, and authentication. GitHub Models, Azure OpenAI, and custom AI services each have different auth patterns. Output schemas matter—if the AI returns unstructured text and you expect JSON, parsing fails. Test the API outside the flow before integrating it.

### AI Requirements
Enabled: [ ] Yes [ ] No
API Endpoint: ________________________ (e.g., https://models.inference.ai.azure.com)
API Key: ________________________ (e.g., GitHub PAT)
Model: ________________________ (e.g., gpt-4o-mini)
Output Schema: ________________________ (e.g., { "classification": "Public/Confidential/Strategic", "explanation": "..." })
Content Access Method: ________________________ (e.g., SharePoint Get file content)
Verification Command: `Request-ChatCompletion` (PSOpenAI)

### Permissions

AI APIs need valid keys and quota. If the key expires or the quota runs out, the flow fails. Verify API access and test a sample request before deployment.

API Access: [ ] Granted [ ] Pending
Verification: Test API call with key



## 8. Error Handling and Logging

Flows fail. HTTP actions timeout, Dataverse throttles, SharePoint returns 404. Without error handling, failures disappear into Power Platform's run history. Define a logging table (gfi_flowerrors), wrap critical actions in try/catch scopes, and capture error messages. Document expected failure scenarios so you can build conditional logic around them.

### Logging Table
Table: ________________________ (e.g., gfi_flowerrors)
Fields: ________________________ (e.g., gfi_errormessage, gfi_timestamp)
Verification Command: `pac data schema export --table [TableName]`

### Error Scenarios

List known failure points: blank required fields, API timeouts, permission issues. If you know Classification can be blank, add a condition. If Dataverse updates fail under load, add retry logic.

Scenario 1: ________________________ (e.g., Blank Classification)
Scenario 2: ________________________ (e.g., Dataverse update failure)

### Try/Catch Scope

Wrap actions that can fail (HTTP calls, Dataverse writes, approvals) in scopes with error branches. Log failures to Dataverse or send alerts. Without this, you debug blind.

Actions to Wrap: ________________________ (e.g., CreateRecord, StartAndWaitForAnApproval)



## 9. Licensing and Compliance

Premium connectors (Dataverse, custom connectors, AI Builder) require Power Automate Per-User licenses ($15-$40/month) or usage-based billing. If the customer doesn't have licenses, the flow fails at import. DoD/GovCloud environments have compliance requirements: Azure Government regions, FIPS 140-2 encryption, CUI handling. Verify licensing and compliance before deployment, not after.

### Licensing
Power Automate License: [ ] Microsoft 365 E3/E5 [ ] Per-User ($15-$40/month) [ ] Other: ________________________
Premium Connectors: [ ] Dataverse [ ] Other: ________________________
AI Builder Credits: ________________________ (e.g., 1,000,000 credits/month)
Verification: Check admin.powerplatform.microsoft.com > Billing > Licenses

### Compliance

DoD contracts require Azure Government regions and CUI-compliant handling. FIPS 140-2 encryption must be enabled for IL4/IL5 workloads. Audit logging (flow run history, Dataverse logs) must capture sensitive operations. Confirm compliance requirements with the security team before building.

Azure Government Region: ________________________ (e.g., US Gov Virginia)
CUI Requirements: [ ] Met [ ] Pending
FIPS 140-2 Encryption: [ ] Enabled
Audit Logging: [ ] Enabled (e.g., gfi_FlowErrors)
Verification: Consult DoD security team



## 10. ALM and Deployment

Application Lifecycle Management (ALM) is how you move flows from Dev to Test to Prod without breaking them. Flows belong in solutions (managed for Prod, unmanaged for Dev). Without solutions, you manually export/import flows and lose connection references. Confirm the solution name, type, and deployment tools before starting. `pac` CLI version matters—older versions have bugs with custom connectors.

### Solution Management
Solution Name: ________________________ (e.g., GFI_Demo)
Type: [ ] Managed [ ] Unmanaged
Verification Command: `pac solution list --environment [EnvironmentId]`

### Deployment Tools

Power Platform CLI (`pac`), PowerShell Core, and required modules (Microsoft.Graph, PnP.PowerShell) must be installed and updated. Version mismatches cause silent failures. Verify tool versions before deployment.

pac CLI Version: ________________________ (e.g., 2.x+)
PowerShell Version: ________________________ (e.g., Core 7.2+)
Modules: [ ] Microsoft.Graph.Authentication [ ] PnP.PowerShell [ ] PSOpenAI

Verification Commands:
```powershell
pac --version
pwsh --version
Get-Module -ListAvailable
```

---

## How to Use This Checklist

1. **Send it to the customer before the kickoff meeting.** Let them fill out what they know.
2. **Review it in the first meeting.** Confirm environment IDs, table names, permissions. Get the stuff they skipped.
3. **Validate entries before coding.** Run the verification commands. Don't assume the SharePoint list ID is correct—test it.
4. **Keep it updated.** When requirements change (new column, different approval routing), update the checklist. It's your source of truth.

When you sit down to write the flow JSON, everything you need is documented. No email threads. No assumptions. No "I'll figure it out later." Just build.