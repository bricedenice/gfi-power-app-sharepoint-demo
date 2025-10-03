# Hybrid SharePoint Migration with One-Way Sync and Dataverse Integration

## Problem

You're stuck with a SharePoint 2013/2016/2019 on prem farm, hoarding list data like a Concept Vault for document metadata, think terabytes of files untouched since 2014. SharePoint 2019 support dies July 14, 2026, and your federal bosses, armed with FedRAMP checklists, want Power Apps and Power BI in the cloud without a six-month data migration slog. What recourse does one have but to federate the data?

The Hybrid Strangler Fig pattern lets cloud apps tap on prem data via SharePoint Online (SPO) one way sync and Dataverse, phasing out the legacy farm without torching it. SharePoint 2013/2016/2019 lacks direct Dataverse connectors, so we'll use Microsoft's official hybrid sync to pipe data to SPO, then hook it to Dataverse. No SQL Server hacks here, my Top Secret clearance days taught me to keep auditors happy, not hand them a reason to grill me.

---

## How to Build It (Without Cratering Production)

### 1. Configure SharePoint Hybrid

Use the SharePoint Hybrid Configuration Wizard to link on prem SharePoint to SPO, setting up one way outbound sync for your Concept Vault list. This keeps data flowing to the cloud while the farm stays online.

**Steps:**

1. In the SharePoint admin center (on prem), launch the Hybrid Configuration Wizard.
2. Configure Azure AD Connect for SSO using GCC/GCC High/DoD-compliant credentials.
3. Enable one way sync for Concept Vault to an SPO site.
4. Ensure port 443 is open for Azure Service Bus relay, firewall fights are worse than debugging PowerShell 10 mins before EOD.
5. Test sync: Verify SPO shows list items (DocumentId, DocumentTitle, Created, Modified, DocumentType, Classification).

This works because Microsoft's hybrid sync is FedRAMP authorized, keeping your auditors at bay. 

### 2. Verify the On Premises Data Gateway

The on premises data gateway is your secure bridge from Power Platform to on prem SharePoint. Install it on a SharePoint app server.

**Gateway checklist:**

- Installed and registered to your Power Platform environment (GCC/GCC High/DoD).
- Runs under a service account with SharePoint read permissions, not your personal AD login.
- Port 443 open for Azure relay, or you're stuck parsing firewall logs.
- Clustered for high availability, single gateways will fail you.

Check Power Platform admin center → Data → On prem data gateways. If it's offline, dig into Event Viewer (Applications and Services Logs → On premises data gateway). Never install on a domain controller—that's like running a server in a broom closet.

### 3. Integrate SharePoint Online with Dataverse

Connect the synced SPO list to Dataverse using the SharePoint connector, letting Power Apps and Power BI query data with minimal lag.

**Steps:**

1. In Power Platform admin center → Environments → [Your Environment] → Settings → Data → Tables, create a new table.
2. Use the SharePoint connector.
3. Configure:
   - **Site URL**: SPO site with the synced Concept Vault.
   - **List**: The replicated list.
   - **Credentials**: Service account with SPO read access (Azure AD, GCC-compliant).
   - **Gateway**: Your verified gateway for hybrid connectivity.
4. Map columns:
   - DocumentId → Primary Key (Whole Number)
   - DocumentTitle → Text
   - DocumentType → Choice (Policy, Report)
   - Classification → Choice (Public, Confidential)
   - Created, Modified → DateTime
5. Save and publish.

Dataverse spins up a table linked to SPO, reflecting on-prem changes via sync. 

### 4. Validate the Integration

Build a Power App (canvas or model driven) to query the Dataverse table. Filter by Classification, sort by Modified, show DocumentTitle. If data loads, you're in business. If you hit a "data source error," check the gateway or SPO permissions, someone's probably skimped on access perms.

For bonus points, create a Power BI report: connect to Dataverse, query the table, chart DocumentType counts. When a GS-15 asks, "How many Confidential docs do we have?" you'll have answers before the morning standup.

**Write operations**: Dataverse supports CRUD on SPO lists if permissions allow. Test updates in Power Apps to confirm changes sync back to on prem via SPO. If writes fail, your service account's got no pull (verify settings).

---

## Why This Approach Doesn't Crash and Burn

**Near real time access**: Power Apps hit SPO, which syncs with on prem, keeping data fresh, no helpdesk calls. The farm keeps running while you build cloud apps, we avoid downtime like the plague. 

**Federal compliance**: GCC/GCC High/DoD environments are FedRAMP and NIST 800-53 compliant, my days in the theatre taught me auditors don't mess around. 

**Future-ready**: By 2026, when SharePoint 2019's support flatlines, you're already cloud-native.

---

## Example PowerShell Script for List Export (Plan B)

If hybrid sync acts up, export the list to CSV for manual SPO/Dataverse import.

**PowerShell to export SharePoint list to CSV for SPO/Dataverse:**

```powershell
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue

$siteUrl = "http://your-sharepoint-site"
$listName = "Concept Vault"
$csvPath = "C:\Export\ConceptVault.csv"

$web = Get-SPWeb $siteUrl
$list = $web.Lists[$listName]
$items = $list.Items

$export = $items | Select-Object @{Name="DocumentId";Expression={$_.ID}}, 
    @{Name="DocumentTitle";Expression={$_.Title}}, 
    @{Name="Created";Expression={$_.Created}}, 
    @{Name="Modified";Expression={$_.Modified}}, 
    @{Name="DocumentType";Expression={$_["DocumentType"]}}, 
    @{Name="Classification";Expression={$_["Classification"]}}

$export | Export-Csv -Path $csvPath -NoTypeInformation
$web.Dispose()
```