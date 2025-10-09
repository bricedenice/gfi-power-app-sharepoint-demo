# Setup Guide for GCC Power App Developers Using AI with Azure OpenAI

## Prerequisites

Before diving in, gather these. No one likes a 404 error in a HTTP connector.

- **Azure Government Subscription**: Active in GCC or GCC High (portal.azure.us). If you don't have one, nudge your agency's Azure admin—bureaucracy moves slow.
- **PowerShell 7+**: Installed on your secure machine (run `pwsh --version` to check). Most GCC setups have it; if not, grab it from the Microsoft Store.
- **Power Apps PowerShell Module**: For admin tasks (`Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser`).
- **Azure CLI**: For resource provisioning (`az login --service-principal` for GCC). Keeps things scriptable.
- **Permissions**: Contributor role on your Azure subscription for creating OpenAI resources. Check with your admin; GCC High loves its RBAC hoops.
- **Coffee**: Because government IT is a grind, and caffeine is your co-pilot.

## Step 1: Provision Azure OpenAI in GCC

Log into the Azure Government portal (portal.azure.us). No public Azure here—GCC High is its own walled garden.

1. Navigate to "Create a resource" > Search for "Azure OpenAI".
2. Configure the resource:
   - **Name**: Something memorable, like `gcc-ai-prod`.
   - **Region**: US Gov Virginia or US Gov Texas (GCC High-compliant regions).
   - **Pricing Tier**: Standard S0 (scales well, ~$0.0005/1K tokens for gpt-4o-mini).

3. Deploy and wait (5-10 minutes). Grab that coffee.
4. Note the endpoint (e.g., `https://gcc-ai-prod.openai.azure.us/`) and API key (under "Keys and Endpoint"). Store the key in Azure Key Vault for compliance auditors love this.

## Step 2: Install and Configure PSOpenAI

PSOpenAI is your bridge to Azure OpenAI. It's like a good sergeant: reliable and gets the job done.

1. Open PowerShell 7 as admin in your GCC environment.
2. Install the module:
   ```powershell
   Install-Module -Name PSOpenAI -Scope CurrentUser
   ```

3. Set environment variables (replace with your values):
   ```powershell
   $env:AZURE_OPENAI_API_KEY = "your-api-key-from-key-vault"
   $env:AZURE_OPENAI_ENDPOINT = "https://gcc-ai-prod.openai.azure.us/"
   ```

**Pro tip**: Use Key Vault secrets (`az keyvault secret show`) to avoid hardcoding keys. GCC High sniffs out plaintext like a hound.

## Step 3: Test Your First AI Call

Let's query something useful, like optimizing a Power App formula. This mirrors the blog's "splat" example but for Power Apps.

```powershell
$params = @{
    Model = "gpt-4o-mini"
    SystemMessage = "You are a Power Apps expert with PL-400 certification."
    Message = "Optimize this Power Apps formula: If(IsBlank(TextInput1), 'Default', TextInput1)"
    ApiType = "Azure"
}
$response = Request-ChatCompletion @params
$response.Answer
```

**Expected output**: Something like, "Use Coalesce(TextInput1, 'Default') for cleaner logic and better performance." If it fails, check your endpoint or firewall (GCC loves blocking ports).
## Step 4: Structured Outputs for Automation

Unstructured AI responses are like unformatted SharePoint lists—useless for automation. Use JSON schemas for clean, pipeable objects.

**Example**: Parse user feedback into a Dataverse table.

```powershell
$schema = @{
    name = "feedback_schema"
    strict = $true
    schema = @{
        type = "object"
        properties = @{
            sentiment = @{
                type = "string"
                enum = @("Positive", "Negative", "Neutral")
                description = "Sentiment of the feedback"
            }
            summary = @{
                type = "string"
                description = "Brief summary of the feedback"
            }
        }
        required = @("sentiment", "summary")
        additionalProperties = $false
    }
}
$params = @{
    Model = "gpt-4o-mini"
    SystemMessage = "You are a Power Apps data analyst."
    Message = "Analyze this feedback: 'The app crashes when I submit forms.'"
    Format = "json_schema"
    JsonSchema = $schema
    ApiType = "Azure"
}
$response = Request-ChatCompletion @params | ConvertFrom-Json
$response.sentiment  # Outputs: "Negative"
$response.summary    # Outputs: "App crashes during form submission"
```

**Use Case**: Pipe `$response` to `Add-PowerAppsCustomRecord` to log issues in Dataverse, automating bug tracking.

## Step 5: Build Reusable Functions

Wrap your AI logic into a function for Power Platform tasks, like generating Dataverse schemas.

```powershell
function Get-DataverseSchema {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$EntityDescription
    )
    $schema = @{
        name = "dataverse_schema"
        strict = $true
        schema = @{
            type = "object"
            properties = @{
                entityName = @{ type = "string"; description = "Dataverse entity name" }
                fields = @{
                    type = "array"
                    items = @{
                        type = "object"
                        properties = @{
                            name = @{ type = "string" }
                            type = @{ type = "string"; enum = @("string", "number", "date") }
                        }
                        required = @("name", "type")
                    }
                }
            }
            required = @("entityName", "fields")
        }
    }
    $params = @{
        Model = "gpt-4o-mini"
        SystemMessage = "You are a Dataverse expert."
        Message = "Generate a Dataverse entity schema for: $EntityDescription"
        Format = "json_schema"
        JsonSchema = $schema
        ApiType = "Azure"
    }
    Request-ChatCompletion @params | ConvertFrom-Json
}
```

**Usage**:
```powershell
"Customer feedback with name, rating, and date" | Get-DataverseSchema
```

**Output**: A JSON object with `entityName: "Feedback"` and fields like `{name: "CustomerName", type: "string"}`, ready for `New-PowerAppsEntity`.
## Step 6: Integrate with Power Apps and Power Automate

- **Power Apps**: Use the PowerShell script in a Power Automate flow to process data (e.g., call `Get-DataverseSchema` via a custom connector). Trigger it from a canvas app button to dynamically generate forms.
- **Power Automate**: Create a flow that runs the script, parses the JSON, and updates Dataverse or SharePoint. Example: Auto-classify support tickets by sentiment.
- **ALM Integration**: Embed scripts in Azure DevOps pipelines for app deployment. AI-generated schemas can validate test data before pushing to production.

## Use Cases for GCC Power App Developers

- **Development**: Generate optimized Power Fx formulas or PCF components. Example: AI suggests `Filter(Gallery, StartsWith(Title, SearchBox.Text))` for faster searches.
- **Planning**: Create data models for Dataverse. The `Get-DataverseSchema` function can propose entities for new apps, saving hours of manual design.
- **Automation**: Streamline admin tasks like auditing app permissions (`Get-AdminPowerApp | Where-Object {$_.Owner -eq "user"}`) by feeding AI outputs into reports.
- **Debugging**: Analyze error logs with AI to suggest fixes, like tweaking a flow's retry policy based on HTTP 429 errors.

## Security and Compliance Notes

- **Data Residency**: Azure OpenAI in GCC keeps data in US Gov regions, compliant with IL4/IL5.
- **Access Control**: Use least-privilege RBAC (e.g., Reader for users, Contributor for admins). Audit Key Vault access monthly.
- **Rate Limits**: Start with gpt-4o-mini (cheaper, ~50K tokens/min). Monitor via Azure Metrics to avoid throttling.
- **Audits**: Log all API calls (Azure Monitor) for GCC High compliance reviews. No one wants a DoD auditor's side-eye.
- **Non-Interactive Authentication**: For production and DoD environments, use service principal or certificate-based authentication. Interactive authentication is acceptable for dev/test and corporate civilian environments only.
- **FIPS 140-2 Compliance**: 
  - **DoD/IL4/IL5 Requirement**: FIPS 140-2 compliant encryption is **mandatory** for DoD contracts and GCC High environments (IL4/IL5)
  - **Commercial/Civilian Environments**: FIPS 140-2 is **not required** for commercial or civilian corporate environments, but can be enabled if needed for additional security
  - **Windows Configuration**: Enable via registry: `Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled" -Value 1`
  - **Linux Configuration**: Add kernel parameter `fips=1` to bootloader configuration (e.g., GRUB)
  - **macOS Configuration**: Ensure cryptographic operations use FIPS 140-2 validated modules (consult security team for specific configuration)
  - **Verification**: Scripts in this repository include automated FIPS compliance checks that warn but do not block execution to maintain compatibility across environments

## Troubleshooting

- **Connection Errors**: Verify `$env:AZURE_OPENAI_ENDPOINT` matches your resource. Check firewall rules (port 443 open).
- **Auth Issues**: Regenerate API keys if expired. Use `az account show` to confirm you're in the right tenant.
- **Quota Exceeded**: Scale up to Standard S1 or request a limit increase via Azure support.

## Why This Matters

This setup lets you wield AI like a well-aimed M16: precise, powerful, and compliant. You'll cut development time (think 30% faster on data tasks), automate the boring stuff, and impress your Fed overlords with GCC-approved smarts. Plus, you can tell your team you tamed AI without leaving the secure bubble. Now, go build that app before the next compliance review hits.