#!/bin/bash

# Power Platform Solution Management Commands
# GFI Strategic Concepts Demo Environment

# Environment Configuration
ENVIRONMENT_ID="YOUR_ENVIRONMENT_ID"
TENANT_ID="YOUR_TENANT_ID"
SOLUTION_NAME="GFIConceptFlow"

# Configurable Endpoints for Commercial and Government Cloud (GCC/GCC High)
# Use .crm.dynamics.com for commercial, .crm.dynamics.us for GCC, or .crm.microsoftdynamics.us for GCC High
DATAVERSE_URL="https://orgXXXXXX.crm.dynamics.com"  # Default: Commercial; Change to .us for GCC or .microsoftdynamics.us for GCC High
WEB_API_ENDPOINT="${DATAVERSE_URL}/api/data/v9.2"

# Utility function for logging
function log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    echo "[$timestamp] [$level] [solution-commands] $msg"
    # Append to a log file for audit purposes (FedRAMP AU-2, AU-12)
    local logfile="AuditLog_$(date '+%Y%m%d').log"
    echo "[$timestamp] [$level] [solution-commands] $msg" >> "$logfile"
}

# Check FIPS 140-2 compliance for DoD environments
function check_fips_compliance() {
    log "INFO" "Checking FIPS 140-2 encryption compliance..."
    
    # Check for Linux kernel parameter
    if [ -f /proc/sys/crypto/fips_enabled ]; then
        local fips_status=$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)
        if [ "$fips_status" = "1" ]; then
            log "SUCCESS" "✔ FIPS 140-2 mode enabled on Linux"
            echo "✔ FIPS 140-2 mode enabled" >&2
            return 0
        else
            log "WARNING" "⚠️ FIPS 140-2 mode NOT enabled on Linux"
            echo "⚠️ FIPS 140-2 mode NOT enabled" >&2
            echo "For DoD IL4/IL5 environments, enable FIPS mode with kernel parameter: fips=1" >&2
            echo "Note: FIPS 140-2 is required for DoD contracts but may not be necessary for commercial/civilian environments" >&2
            return 1
        fi
    # Check for macOS (limited support)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log "WARNING" "⚠️ FIPS 140-2 compliance check not automated for macOS"
        echo "⚠️ FIPS 140-2 compliance check not automated for macOS" >&2
        echo "For DoD IL4/IL5 environments, ensure cryptographic operations use FIPS 140-2 validated modules" >&2
        echo "Note: FIPS 140-2 is required for DoD contracts but may not be necessary for commercial/civilian environments" >&2
        return 1
    else
        log "WARNING" "⚠️ Could not determine FIPS 140-2 status"
        echo "⚠️ Could not determine FIPS 140-2 status" >&2
        return 1
    fi
}

# Check if Power Platform CLI is installed
function check_pac_cli() {
    if ! command -v pac &> /dev/null; then
        log "ERROR" "Power Platform CLI (pac) not found. Install it first."
        log "INFO" "Installation: https://docs.microsoft.com/en-us/power-platform/developer/cli/introduction#install-power-platform-cli"
        exit 1
    fi
    log "INFO" "Power Platform CLI found: $(pac --version)"
}

# Create new solution project
create_solution() {
    local solution_name=${1:-$SOLUTION_NAME}
    local publisher_name=${2:-$PUBLISHER_NAME}
    local publisher_prefix=${3:-$PUBLISHER_PREFIX}
    
    echo "🔧 Creating new solution: $solution_name"
    echo "   Publisher: $publisher_name"
    echo "   Prefix: $publisher_prefix"
    
    pac solution init \
        --publisher-name "$publisher_name" \
        --publisher-prefix "$publisher_prefix" \
        --outputDirectory "./$solution_name"
    
    if [ $? -eq 0 ]; then
        echo "✅ Solution created successfully in ./$solution_name"
        ls -la "./$solution_name/"
    else
        echo "❌ Failed to create solution"
    fi
}

# Clone existing solution from environment
clone_solution() {
    local solution_name=${1:-$SOLUTION_NAME}
    local target_dir=${2:-"./$solution_name-cloned"}
    
    echo "📥 Cloning solution '$solution_name' from environment..."
    
    # First, authenticate if needed
    if ! pac auth list 2>/dev/null | grep -q "Index"; then
        echo "🔐 Authentication required. Please run: pac auth create"
        return 1
    fi
    
    pac solution clone \
        --name "$solution_name" \
        --outputDirectory "$target_dir" \
        --processCanvasApps
    
    if [ $? -eq 0 ]; then
        echo "✅ Solution cloned successfully to $target_dir"
        ls -la "$target_dir/"
    else
        echo "❌ Failed to clone solution"
    fi
}

# Add flow to solution
add_flow_to_solution() {
    local solution_path=${1:-"./GFISolution"}
    local flow_id=${2:-"4a282ad2-9cbf-0de7-4791-2edbc35a3887"}
    
    echo "📎 Adding flow $flow_id to solution at $solution_path"
    
    if [ ! -d "$solution_path" ]; then
        echo "❌ Solution directory not found: $solution_path"
        return 1
    fi
    
    cd "$solution_path"
    pac solution add-reference --id "$flow_id"
    
    if [ $? -eq 0 ]; then
        echo "✅ Flow added to solution successfully"
    else
        echo "❌ Failed to add flow to solution"
    fi
    cd - > /dev/null
}

# Export solution from environment
export_solution() {
    local solution_name=${1:-$SOLUTION_NAME}
    local output_path=${2:-"./exports/${solution_name}_$(date +%Y%m%d_%H%M%S).zip"}
    local managed=${3:-"false"}
    
    echo "📤 Exporting solution '$solution_name' from environment..."
    echo "   Output: $output_path"
    echo "   Managed: $managed"
    
    # Create exports directory
    mkdir -p "$(dirname "$output_path")"
    
    local export_cmd="pac solution export --name \"$solution_name\" --path \"$output_path\""
    
    if [ "$managed" = "true" ]; then
        export_cmd="$export_cmd --managed"
    fi
    
    eval $export_cmd
    
    if [ $? -eq 0 ] && [ -f "$output_path" ]; then
        echo "✅ Solution exported successfully"
        echo "📊 File size: $(du -h "$output_path" | cut -f1)"
        return 0
    else
        echo "❌ Failed to export solution"
        return 1
    fi
}

# Import solution to environment
import_solution() {
    local solution_path=${1}
    local target_env=${2:-$ENVIRONMENT_ID}
    
    if [ -z "$solution_path" ]; then
        echo "❌ Solution path required"
        echo "Usage: import_solution <path> [environment_id]"
        return 1
    fi
    
    if [ ! -f "$solution_path" ]; then
        echo "❌ Solution file not found: $solution_path"
        return 1
    fi
    
    echo "📥 Importing solution from: $solution_path"
    echo "   Target environment: $target_env"
    
    pac solution import --path "$solution_path"
    
    if [ $? -eq 0 ]; then
        echo "✅ Solution imported successfully"
    else
        echo "❌ Failed to import solution"
    fi
}

# Pack solution (source to zip)
pack_solution() {
    local solution_path=${1:-"./GFISolution"}
    local output_path=${2:-"./packed/${SOLUTION_NAME}_$(date +%Y%m%d_%H%M%S).zip"}
    local solution_type=${3:-"Unmanaged"}
    
    echo "📦 Packing solution from: $solution_path"
    echo "   Output: $output_path"
    echo "   Type: $solution_type"
    
    if [ ! -d "$solution_path" ]; then
        echo "❌ Solution directory not found: $solution_path"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$(dirname "$output_path")"
    
    pac solution pack \
        --folder "$solution_path/src" \
        --zipfile "$output_path" \
        --packagetype "$solution_type"
    
    if [ $? -eq 0 ] && [ -f "$output_path" ]; then
        echo "✅ Solution packed successfully"
        echo "📊 File size: $(du -h "$output_path" | cut -f1)"
    else
        echo "❌ Failed to pack solution"
    fi
}

# Unpack solution (zip to source)
unpack_solution() {
    local solution_zip=${1}
    local output_dir=${2:-"./unpacked/$(basename "$solution_zip" .zip)"}
    
    if [ -z "$solution_zip" ]; then
        echo "❌ Solution zip path required"
        echo "Usage: unpack_solution <zip_path> [output_dir]"
        return 1
    fi
    
    if [ ! -f "$solution_zip" ]; then
        echo "❌ Solution zip not found: $solution_zip"
        return 1
    fi
    
    echo "📂 Unpacking solution: $solution_zip"
    echo "   Output directory: $output_dir"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    pac solution unpack \
        --zipfile "$solution_zip" \
        --folder "$output_dir"
    
    if [ $? -eq 0 ]; then
        echo "✅ Solution unpacked successfully"
        ls -la "$output_dir/"
    else
        echo "❌ Failed to unpack solution"
    fi
}

# Sync solution with environment
sync_solution() {
    local solution_path=${1:-"./GFISolution"}
    
    echo "🔄 Syncing solution with environment: $solution_path"
    
    if [ ! -d "$solution_path" ]; then
        echo "❌ Solution directory not found: $solution_path"
        return 1
    fi
    
    cd "$solution_path"
    pac solution sync
    
    if [ $? -eq 0 ]; then
        echo "✅ Solution synced successfully"
    else
        echo "❌ Failed to sync solution"
    fi
    cd - > /dev/null
}

# List solutions in environment
list_solutions() {
    echo "📋 Listing solutions in environment..."
    
    pac solution list
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to list solutions. Ensure you're authenticated with 'pac auth create'"
    fi
}

# Authenticate to Power Platform
authenticate() {
    log "INFO" "Authenticating to Power Platform..."
    
    # Run FIPS compliance check
    check_fips_compliance || true  # Don't fail on FIPS check, just warn
    
    if [ -n "$SERVICE_PRINCIPAL_ID" ] && [ -n "$SERVICE_PRINCIPAL_SECRET" ]; then
        log "INFO" "Using service principal authentication"
        log "SUCCESS" "✔ Non-interactive authentication enforced for production compliance"
        pac auth create --applicationId "$SERVICE_PRINCIPAL_ID" --clientSecret "$SERVICE_PRINCIPAL_SECRET" --tenant "$TENANT_ID" --url "$DATAVERSE_URL"
    else
        log "WARNING" "Falling back to interactive authentication (not suitable for production)"
        log "WARNING" "DoD environments require non-interactive authentication (service principal or certificate-based)"
        log "WARNING" "Interactive auth is acceptable for dev/test and corporate civilian environments only"
        echo "⚠️ Using interactive authentication - not suitable for production/DoD environments" >&2
        echo "For production/DoD: Set SERVICE_PRINCIPAL_ID and SERVICE_PRINCIPAL_SECRET environment variables" >&2
        echo "For dev/test/civilian: Interactive auth is acceptable" >&2
        pac auth create --url "$DATAVERSE_URL"
    fi
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Authentication successful"
    else
        log "ERROR" "Authentication failed"
        exit 1
    fi
}

# Show solution info
show_solution_info() {
    local solution_path=${1:-"./GFISolution"}
    
    if [ ! -d "$solution_path" ]; then
        echo "❌ Solution directory not found: $solution_path"
        return 1
    fi
    
    echo "📊 Solution Information: $solution_path"
    echo ""
    
    # Show solution.xml if exists
    local solution_xml="$solution_path/src/Other/Solution.xml"
    if [ -f "$solution_xml" ]; then
        echo "📄 Solution.xml details:"
        grep -E "(UniqueName|LocalizedName|Version|Publisher)" "$solution_xml" | head -10
        echo ""
    fi
    
    # Show directory structure
    echo "📁 Directory structure:"
    find "$solution_path" -type f -name "*.xml" | head -10
    echo ""
    
    # Show project file
    if [ -f "$solution_path"/*.cdsproj ]; then
        echo "🔧 Project file: $(basename "$solution_path"/*.cdsproj)"
    fi
}

# Show help
show_help() {
    echo "🔧 Power Platform Solution Management Commands"
    echo ""
    echo "Solution Creation:"
    echo "  create_solution [name] [publisher] [prefix] - Create new solution project"
    echo "  clone_solution [name] [target_dir]         - Clone existing solution from environment"
    echo ""
    echo "Solution Development:"
    echo "  add_flow_to_solution [path] [flow_id]      - Add flow to solution"
    echo "  sync_solution [path]                       - Sync solution with environment"
    echo "  show_solution_info [path]                  - Show solution details"
    echo ""
    echo "Solution Packaging:"
    echo "  pack_solution [path] [output] [type]       - Pack solution (source to zip)"
    echo "  unpack_solution [zip] [output_dir]         - Unpack solution (zip to source)"
    echo ""
    echo "Environment Operations:"
    echo "  export_solution [name] [output] [managed]  - Export solution from environment"
    echo "  import_solution <path> [env_id]            - Import solution to environment"
    echo "  list_solutions                             - List solutions in environment"
    echo ""
    echo "Authentication:"
    echo "  authenticate [tenant_id]                   - Authenticate to Power Platform"
    echo ""
    echo "Default Configuration:"
    echo "  Solution Name: $SOLUTION_NAME"
    echo "  Publisher: $PUBLISHER_NAME"
    echo "  Prefix: $PUBLISHER_PREFIX"
    echo "  Environment ID: $ENVIRONMENT_ID"
    echo "  Environment Unique Name: $ENVIRONMENT_UNIQUE_NAME"
    echo "  Organization ID: $ORGANIZATION_ID"
    echo "  Web API Endpoint: $WEB_API_ENDPOINT"
    echo "  Dataverse URL: $DATAVERSE_URL"
    echo ""
    echo "Examples:"
    echo "  ./solution-commands.sh create_solution MyFlow GFIStrategicConcepts gfi"
    echo "  ./solution-commands.sh add_flow_to_solution ./GFISolution 4a282ad2-9cbf-0de7-4791-2edbc35a3887"
    echo "  ./solution-commands.sh export_solution GFISolution ./exports/gfi-flows.zip true"
    echo "  ./solution-commands.sh import_solution ./exports/gfi-flows.zip"
}

# Main execution
if [ $# -eq 0 ]; then
    show_help
else
    case $1 in
        create_solution)
            create_solution "$2" "$3" "$4"
            ;;
        clone_solution)
            clone_solution "$2" "$3"
            ;;
        add_flow_to_solution)
            add_flow_to_solution "$2" "$3"
            ;;
        export_solution)
            export_solution "$2" "$3" "$4"
            ;;
        import_solution)
            import_solution "$2" "$3"
            ;;
        pack_solution)
            pack_solution "$2" "$3" "$4"
            ;;
        unpack_solution)
            unpack_solution "$2" "$3"
            ;;
        sync_solution)
            sync_solution "$2"
            ;;
        list_solutions)
            list_solutions
            ;;
        authenticate)
            authenticate "$2"
            ;;
        show_solution_info)
            show_solution_info "$2"
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
