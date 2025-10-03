#!/bin/bash

# Power Automate Flow Management Scripts
# GFI Strategic Concepts Demo Environment
# Supports both REST API and PnP CLI Microsoft 365 approaches

# Environment Configuration
ENVIRONMENT_ID="YOUR_ENVIRONMENT_ID"
ENVIRONMENT_NAME="Default-$ENVIRONMENT_ID"  # Used for PnP CLI
TENANT_ID="YOUR_TENANT_ID"
CONCEPT_FLOW_ID="4a282ad2-9cbf-0de7-4791-2edbc35a3887"

# Configurable Base URL for Power Automate API (Commercial and Government Cloud)
# Use api.flow.microsoft.com for commercial, gov.api.flow.microsoft.us for GCC/GCC High
BASE_URL="https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple"  # Default: Commercial; Change to gov.api.flow.microsoft.us for GCC/GCC High

# Utility function for logging
function log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    echo "[$timestamp] [$level] [flow-commands] $msg"
    # Append to a log file for audit purposes (FedRAMP AU-2, AU-12)
    local logfile="AuditLog_$(date '+%Y%m%d').log"
    echo "[$timestamp] [$level] [flow-commands] $msg" >> "$logfile"
}

# Get access token (for REST API)
get_token() {
    az account get-access-token --resource https://service.flow.microsoft.com --query accessToken -o tsv 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "Azure CLI not authenticated. Run 'az login' first."
        echo "❌ Azure CLI not authenticated. Run 'az login' first."
        exit 1
    fi
    log "INFO" "Access token retrieved successfully"
}

# Check CLI availability
check_cli_availability() {
    if ! command -v m365 &> /dev/null; then
        log "WARNING" "PnP CLI Microsoft 365 not found. Install with: npm install -g @pnp/cli-microsoft365"
        echo "⚠️  PnP CLI Microsoft 365 not found. Install with: npm install -g @pnp/cli-microsoft365"
        return 1
    fi
    log "INFO" "PnP CLI Microsoft 365 found"
    return 0
}

# Ensure PnP CLI authentication
ensure_pnp_auth() {
    if [ "$CLI_METHOD" = "pnp" ]; then
        if ! check_cli_availability; then
            log "WARNING" "PnP CLI not available, falling back to REST API"
            echo "❌ PnP CLI not available, falling back to REST API"
            CLI_METHOD="rest"
            return 1
        fi
        
        # Check if already logged in
        if ! m365 status --output json 2>/dev/null | jq -e '.connectedAs' > /dev/null; then
            log "INFO" "Authenticating with PnP CLI Microsoft 365..."
            echo "🔐 Authenticating with PnP CLI Microsoft 365..."
            m365 login
        fi
    fi
}

# List all flows in environment
list_flows() {
    local sharing_status=${1:-"all"}
    local with_solutions=${2:-false}
    local as_admin=${3:-false}
    
    log "INFO" "Listing flows with sharing status: $sharing_status"
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        log "INFO" "Using PnP CLI to list flows"
        echo "🔍 Listing flows using PnP CLI (sharing: $sharing_status)..."
        local cmd="m365 flow list --environmentName $ENVIRONMENT_NAME --sharingStatus $sharing_status --output json"
        
        if [ "$with_solutions" = "true" ]; then
            cmd="$cmd --withSolutions"
        fi
        
        if [ "$as_admin" = "true" ]; then
            cmd="$cmd --asAdmin"
        fi
        
        eval $cmd | jq '.[] | {name: .name, displayName: .displayName, state: .state, sharingType: .sharingType}'
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Flows listed successfully using PnP CLI"
        else
            log "ERROR" "Failed to list flows using PnP CLI"
        fi
    else
        log "INFO" "Using REST API to list flows in environment $ENVIRONMENT_ID"
        echo "🔍 Listing flows using REST API in environment $ENVIRONMENT_ID..."
        curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json" | jq '.value[] | {name: .name, displayName: .properties.displayName, state: .properties.state}'
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Flows listed successfully using REST API"
        else
            log "ERROR" "Failed to list flows using REST API"
        fi
    fi
}

# List flows with different sharing options
list_flows_shared() {
    echo "📊 Listing flows by sharing status..."
    echo ""
    echo "🔹 Personal flows:"
    list_flows "personal"
    echo ""
    echo "🔹 Shared with me:"
    list_flows "sharedWithMe"
    echo ""
    echo "🔹 Owned by me:"
    list_flows "ownedByMe"
}

# Export specific flow
export_flow() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    local output_file=${2:-"flows/exported-flow-$(date +%Y%m%d-%H%M%S).json"}
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "📥 Exporting flow using PnP CLI: $flow_id..."
        m365 flow export --id "$flow_id" --environmentName "$ENVIRONMENT_NAME" --format json --output json > "$output_file"
    else
        echo "📥 Exporting flow using REST API: $flow_id to $output_file..."
        curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json" | jq '.' > "$output_file"
    fi
    
    if [ $? -eq 0 ] && [ -s "$output_file" ]; then
        echo "✅ Flow exported successfully to $output_file"
        echo "📊 Flow size: $(wc -c < "$output_file") bytes"
    else
        echo "❌ Failed to export flow"
    fi
}

# Get flow details
get_flow_details() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "🔍 Getting flow details using PnP CLI: $flow_id..."
        m365 flow get --id "$flow_id" --environmentName "$ENVIRONMENT_NAME" --output json | jq '{
            name: .displayName,
            state: .state,
            created: .createdTime,
            modified: .lastModifiedTime,
            owner: .creator.userPrincipalName,
            sharingType: .sharingType
        }'
    else
        echo "🔍 Getting flow details using REST API: $flow_id..."
        curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json" | jq '{
                name: .properties.displayName,
                state: .properties.state,
                created: .properties.createdTime,
                modified: .properties.lastModifiedTime,
                suspensionReason: .properties.flowSuspensionReason
            }'
    fi
}

# Get flow run history
get_flow_runs() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    local limit=${2:-5}
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "🏃 Getting flow runs using PnP CLI (last $limit runs)..."
        m365 flow run list --flowId "$flow_id" --environmentName "$ENVIRONMENT_NAME" --output json | jq ".[0:$limit] | .[] | {
            name: .name,
            status: .status,
            startTime: .startTime,
            endTime: .endTime,
            trigger: .trigger.name
        }"
    else
        echo "🏃 Getting last $limit runs using REST API for flow $flow_id..."
        curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id/runs" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json" | jq ".value[0:$limit] | .[] | {name: .name, status: .status, startTime: .properties.startTime, endTime: .properties.endTime}"
    fi
}

# Get specific run details
get_run_details() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    local run_id=$2
    
    if [ -z "$run_id" ]; then
        echo "❌ Run ID required"
        echo "Usage: get_run_details [flow_id] <run_id>"
        return 1
    fi
    
    echo "🔍 Getting details for run $run_id..."
    curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id/runs/$run_id" \
        -H "Authorization: Bearer $(get_token)" \
        -H "Content-Type: application/json" | jq '.'
}

# Enable flow
enable_flow() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "▶️ Enabling flow using PnP CLI: $flow_id..."
        m365 flow enable --id "$flow_id" --environmentName "$ENVIRONMENT_NAME"
    else
        echo "▶️ Enabling flow using REST API: $flow_id..."
        curl -s -X POST "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id/start" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Flow enabled successfully"
    else
        echo "❌ Failed to enable flow"
    fi
}

# Disable flow
disable_flow() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "⏸️ Disabling flow using PnP CLI: $flow_id..."
        m365 flow disable --id "$flow_id" --environmentName "$ENVIRONMENT_NAME"
    else
        echo "⏸️ Disabling flow using REST API: $flow_id..."
        curl -s -X POST "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id/stop" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Flow disabled successfully"
    else
        echo "❌ Failed to disable flow"
    fi
}

# Import/create flow from JSON file
import_flow() {
    local flow_file=${1:-"flows/gfi-concept-approval-flow.json"}
    local new_flow_name=${2:-""}
    
    if [ ! -f "$flow_file" ]; then
        echo "❌ Flow file not found: $flow_file"
        return 1
    fi
    
    ensure_pnp_auth
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        echo "📥 Importing flow using PnP CLI from: $flow_file..."
        # Note: PnP CLI import may require solution format
        echo "⚠️  PnP CLI flow import requires solution package format"
        echo "💡 Use 'pac solution import' or REST API method for JSON imports"
        return 1
    else
        echo "📥 Importing flow using REST API from: $flow_file..."
        
        # Generate new flow ID if not updating existing
        local import_flow_id
        if [ -n "$new_flow_name" ]; then
            import_flow_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
            echo "🆔 Generated new flow ID: $import_flow_id"
        else
            import_flow_id=$CONCEPT_FLOW_ID
            echo "🔄 Updating existing flow ID: $import_flow_id"
        fi
        
        # Construct URI using proper concatenation
        local import_uri="https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/${ENVIRONMENT_ID}/flows/${import_flow_id}?api-version=2016-11-01"
        
        echo "🌐 Import URI: $import_uri"
        
        # Read flow definition
        local flow_body
        flow_body=$(cat "$flow_file")
        echo "📊 Flow definition: $(echo "$flow_body" | wc -c) characters"
        
        # Attempt import using PUT
        local response
        response=$(curl -s -X PUT "$import_uri" \
            -H "Authorization: Bearer $(get_token)" \
            -H "Content-Type: application/json" \
            -d "$flow_body" \
            -w "HTTP_STATUS:%{http_code}")
        
        local http_status=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
        local response_body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')
        
        if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
            echo "✅ Flow imported successfully (HTTP $http_status)"
            echo "$response_body" | jq -r '.properties.displayName // .name // "Flow imported"' 2>/dev/null || echo "Import completed"
            return 0
        else
            echo "❌ Flow import failed (HTTP $http_status)"
            echo "📝 Response: $response_body"
            
            # Try POST method for new flow creation
            if [ "$http_status" = "404" ] && [ -n "$new_flow_name" ]; then
                echo "🔄 Trying POST method for new flow creation..."
                local create_uri="https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/${ENVIRONMENT_ID}/flows?api-version=2016-11-01"
                
                response=$(curl -s -X POST "$create_uri" \
                    -H "Authorization: Bearer $(get_token)" \
                    -H "Content-Type: application/json" \
                    -d "$flow_body" \
                    -w "HTTP_STATUS:%{http_code}")
                
                http_status=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
                response_body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')
                
                if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
                    echo "✅ Flow created successfully (HTTP $http_status)"
                    echo "$response_body" | jq -r '.properties.displayName // .name // "Flow created"' 2>/dev/null || echo "Creation completed"
                    return 0
                else
                    echo "❌ Flow creation also failed (HTTP $http_status)"
                    echo "📝 Response: $response_body"
                fi
            fi
            return 1
        fi
    fi
}

# Remove/delete flow
remove_flow() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    
    ensure_pnp_auth
    
    echo "⚠️  WARNING: This will permanently delete flow $flow_id"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ "$CLI_METHOD" = "pnp" ]; then
            echo "🗑️ Removing flow using PnP CLI: $flow_id..."
            m365 flow remove --id "$flow_id" --environmentName "$ENVIRONMENT_NAME" --force
        else
            echo "🗑️ Removing flow using REST API: $flow_id..."
            curl -s -X DELETE "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id" \
                -H "Authorization: Bearer $(get_token)" \
                -H "Content-Type: application/json"
        fi
        
        if [ $? -eq 0 ]; then
            echo "✅ Flow removed successfully"
        else
            echo "❌ Failed to remove flow"
        fi
    else
        echo "🚫 Flow removal cancelled"
    fi
}

# Get flow status
get_flow_status() {
    local flow_id=${1:-$CONCEPT_FLOW_ID}
    
    echo "📊 Getting status for flow $flow_id..."
    curl -s -X GET "$BASE_URL/environments/$ENVIRONMENT_ID/flows/$flow_id" \
        -H "Authorization: Bearer $(get_token)" \
        -H "Content-Type: application/json" | jq '{
            name: .properties.displayName,
            state: .properties.state,
            created: .properties.createdTime,
            modified: .properties.lastModifiedTime,
            suspensionReason: .properties.flowSuspensionReason
        }'
}

# Analyze flow structure
analyze_flow() {
    local flow_file=${1:-"flows/gfi-concept-approval-flow.json"}
    
    if [ ! -f "$flow_file" ]; then
        echo "❌ Flow file not found: $flow_file"
        return 1
    fi
    
    echo "🔍 Analyzing flow structure from $flow_file..."
    echo ""
    echo "📋 Flow Summary:"
    jq '{
        name: .properties.displayName,
        state: .properties.state,
        created: .properties.createdTime,
        modified: .properties.lastModifiedTime,
        triggers: (.properties.definition.triggers | keys),
        actions: (.properties.definition.actions | keys),
        connections: (.properties.connectionReferences | keys)
    }' "$flow_file"
    
    echo ""
    echo "🔗 Connection References:"
    jq '.properties.connectionReferences | to_entries | .[] | {name: .key, displayName: .value.displayName, tier: .value.tier}' "$flow_file"
}

# Set CLI method
set_cli_method() {
    local method=$1
    if [ "$method" = "pnp" ] || [ "$method" = "rest" ]; then
        CLI_METHOD=$method
        echo "🔧 CLI method set to: $CLI_METHOD"
    else
        echo "❌ Invalid method. Use 'pnp' or 'rest'"
    fi
}

# Show CLI status
show_cli_status() {
    echo "🔧 CLI Configuration:"
    echo "  Method: $CLI_METHOD"
    echo "  Environment ID: $ENVIRONMENT_ID"
    echo "  Environment Name: $ENVIRONMENT_NAME"
    echo ""
    
    if [ "$CLI_METHOD" = "pnp" ]; then
        if check_cli_availability; then
            echo "✅ PnP CLI Microsoft 365 available"
            if m365 status --output json 2>/dev/null | jq -e '.connectedAs' > /dev/null; then
                echo "✅ PnP CLI authenticated"
                m365 status
            else
                echo "⚠️  PnP CLI not authenticated - use 'm365 login'"
            fi
        else
            echo "❌ PnP CLI Microsoft 365 not available"
        fi
    else
        if command -v az &> /dev/null; then
            echo "✅ Azure CLI available"
            if az account show &> /dev/null; then
                echo "✅ Azure CLI authenticated"
            else
                echo "⚠️  Azure CLI not authenticated - use 'az login'"
            fi
        else
            echo "❌ Azure CLI not available"
        fi
    fi
}

# Show help
show_help() {
    echo "🔧 Power Automate Flow Management Commands"
    echo "Supports both REST API and PnP CLI Microsoft 365 methods"
    echo ""
    echo "Configuration:"
    echo "  set_cli_method <pnp|rest>     - Set preferred CLI method (default: rest)"
    echo "  show_cli_status               - Show current CLI configuration and authentication status"
    echo ""
    echo "Flow Management:"
    echo "  list_flows [sharing] [solutions] [admin] - List flows (sharing: personal/sharedWithMe/ownedByMe/all, default: all; solutions: true/false, default: false; admin: true/false, default: false)"
    echo "  list_flows_shared             - List flows categorized by sharing status (personal, shared with me, owned by me)"
    echo "  export_flow [flow_id] [file]  - Export flow definition (default flow_id: GFI Concept Approval Flow; default file: flows/exported-flow-<timestamp>.json)"
    echo "  import_flow [file] [new_name] - Import flow from JSON file (default file: flows/gfi-concept-approval-flow.json; new_name optional for creating new flow)"
    echo "  get_flow_details [flow_id]    - Get detailed flow information (default flow_id: GFI Concept Approval Flow)"
    echo "  get_flow_runs [flow_id] [n]   - Get last n flow runs (default flow_id: GFI Concept Approval Flow; default n: 5)"
    echo "  get_run_details flow_id run_id - Get specific run details (default flow_id: GFI Concept Approval Flow; run_id required)"
    echo "  enable_flow [flow_id]         - Enable/start flow (default flow_id: GFI Concept Approval Flow)"
    echo "  disable_flow [flow_id]        - Disable/stop flow (default flow_id: GFI Concept Approval Flow)"
    echo "  remove_flow [flow_id]         - Remove/delete flow with confirmation (default flow_id: GFI Concept Approval Flow)"
    echo "  get_flow_status [flow_id]     - Get flow status (default flow_id: GFI Concept Approval Flow)"
    echo "  analyze_flow [file]           - Analyze flow structure from file (default file: flows/gfi-concept-approval-flow.json)"
    echo ""
    echo "Environment Variables:"
    echo "  CLI_METHOD                    - Set to 'pnp' or 'rest' (default: rest)"
    echo ""
    echo "Default Configuration:"
    echo "  Flow ID: $CONCEPT_FLOW_ID (GFI Concept Approval Flow)"
    echo "  Environment ID: $ENVIRONMENT_ID"
    echo "  Environment Name: $ENVIRONMENT_NAME"
    echo "  CLI Method: $CLI_METHOD"
    echo ""
    echo "Examples:"
    echo "  CLI_METHOD=pnp ./flow-commands.sh list_flows"
    echo "  ./flow-commands.sh set_cli_method pnp"
    echo "  ./flow-commands.sh list_flows personal true false"
    echo "  ./flow-commands.sh export_flow"
    echo "  ./flow-commands.sh get_flow_runs 4a282ad2-9cbf-0de7-4791-2edbc35a3887 10"
    echo "  ./flow-commands.sh analyze_flow flows/gfi-concept-approval-flow.json"
    echo ""
    echo "PnP CLI Setup:"
    echo "  npm install -g @pnp/cli-microsoft365"
    echo "  m365 login"
}

# Main execution
if [ $# -eq 0 ]; then
    show_help
else
    case $1 in
        set_cli_method)
            set_cli_method "$2"
            ;;
        show_cli_status)
            show_cli_status
            ;;
        list_flows)
            list_flows "$2" "$3" "$4"
            ;;
        list_flows_shared)
            list_flows_shared
            ;;
        export_flow)
            export_flow "$2" "$3"
            ;;
        import_flow)
            import_flow "$2" "$3"
            ;;
        get_flow_details)
            get_flow_details "$2"
            ;;
        get_flow_runs)
            get_flow_runs "$2" "$3"
            ;;
        get_run_details)
            get_run_details "$2" "$3"
            ;;
        enable_flow)
            enable_flow "$2"
            ;;
        disable_flow)
            disable_flow "$2"
            ;;
        remove_flow)
            remove_flow "$2"
            ;;
        get_flow_status)
            get_flow_status "$2"
            ;;
        analyze_flow)
            analyze_flow "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo ""
            show_help
            ;;
    esac
fi
