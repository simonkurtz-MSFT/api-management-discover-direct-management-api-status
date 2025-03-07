#!/bin/bash

# Azure CLI script to log into an Azure tenant, loop over all of its subscriptions to search for API Management instances,
# then check which one have the Direct Management API enabled as it is end-of-life March 2025.

# Set variables (you can modify these or pass as parameters)
TENANT_ID=${1:-"<your-tenant-id>"}                # Default value or first argument
SUBSCRIPTION_ID=${2:-"<your-subscription-id>"}    # Default value or second argument

# Print script information
echo ""
echo "Tenant ID       : $TENANT_ID"
echo "Subscription ID : $SUBSCRIPTION_ID"
echo "------------------------------------------------------"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Log in
echo "Logging into Azure..."
az login --tenant "$TENANT_ID"

if [ $? -ne 0 ]; then
    echo "Error: Failed to log in to Azure. Please check your credentials and try again."
    exit 1
fi

# Set the subscription context
echo "Setting subscription context to: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

if [ $? -ne 0 ]; then
    echo "Error: Failed to set subscription context. Please check your subscription ID."
    exit 1
fi

echo "Successfully logged in to Azure and set subscription context."

# -------------------------------------------------------------------------------------------------

# List all subscriptions in the tenant
echo "------------------------------------------------------"
echo "Retrieving all subscriptions in tenant: $TENANT_ID"

SUBSCRIPTIONS=$(az account list --query '[].id' -o tsv)
# You can hardcode the subscription ID(s) here for testing.
SUBSCRIPTIONS="<your-subscription-id>"

if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve subscriptions."
    exit 1
fi

# ...existing code...

echo "Found $(echo "$SUBSCRIPTIONS" | wc -l) subscription(s) in tenant."

# Initialize arrays to store results
RESULTS=()

# Search for API Management instances across all subscriptions
echo "------------------------------------------------------"
echo -e "Searching for API Management instances across all subscriptions:\n"
API_VERSION="2022-08-01"

# Count total subscriptions
TOTAL_SUBS=$(echo "$SUBSCRIPTIONS" | wc -l)
CURRENT_SUB=0

for SUB in $SUBSCRIPTIONS; do
    # Increment counter
    CURRENT_SUB=$((CURRENT_SUB + 1))

    echo "($CURRENT_SUB of $TOTAL_SUBS): Checking subscription: $SUB"

    # Set context to current subscription and check if successful
    if ! az account set --subscription "$SUB" > /dev/null 2>&1; then
        echo "You may not have access to this subscription. Skipping."
        continue
    fi

    # First check if there are any APIM instances in this subscription
    INSTANCE_COUNT=$(az apim list --subscription "$SUB" --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo -e "Found $INSTANCE_COUNT API Management instance(s) in subscription $SUB\n"

        # Get all APIM instances with details
        APIM_INSTANCES=$(az apim list --subscription "$SUB" --query "[].{name:name, resourceGroup:resourceGroup, location:location, sku:sku.name}" -o tsv 2>/dev/null)

        # Process and display in table format
        while IFS=$'\t' read -r name resourceGroup location sku; do
            if [ -n "$name" ]; then
                echo "Getting tenant access information for $name in $resourceGroup..."

                # Call REST API using az rest and capture JSON output
                # echo "Calling API Management tenant access endpoint..."
                TENANT_ACCESS=$(az rest --method GET \
                  --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$name/tenant/access?api-version=$API_VERSION" \
                  --output json 2>/dev/null)

                # Check if the REST call was successful
                REST_STATUS=$?

                if [ $REST_STATUS -eq 0 ] && [ -n "$TENANT_ACCESS" ]; then
                    # Extract the enabled status - grab text after "enabled": and before comma or }
                    ENABLED=$(echo "$TENANT_ACCESS" | grep -o '"enabled": *[^,}]*' | awk -F': ' '{print $2}' | tr -d ' "')

                    # Add result to array for summary table
                    RESULTS+=("| $SUB | $resourceGroup | $name | $location | $sku | $ENABLED |")

                    echo "Tenant access enabled: $ENABLED"
                else
                    # Handle bad request or other errors: Add result with unknown enabled state
                    RESULTS+=("| $SUB | $resourceGroup | $name | $location | $sku | UNKNOWN |")
                fi
            fi
        done <<< "$APIM_INSTANCES"
    else
        echo "No API Management instances found in subscription $SUB"
    fi
done

# Reset to original subscription context
az account set --subscription "$SUBSCRIPTION_ID" > /dev/null

# Show summary table of all instances with their enabled state
echo -e "\n"
echo "=========================================================="
echo "SUMMARY: API Management Instances with Tenant Access State"
echo "=========================================================="

# Count enabled/disabled instances first
ENABLED_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c "| true |")
DISABLED_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c "| false |")
UNKNOWN_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c "| UNKNOWN |")

echo ""
echo "Total instances : ${#RESULTS[@]}"
echo "Enabled         : $ENABLED_COUNT"
echo "Disabled        : $DISABLED_COUNT"
echo "Unknown         : $UNKNOWN_COUNT"
echo ""

# Then print the table headers and results
# Define a format string with specific column widths
printf "%-36s | %-25s | %-25s | %-20s | %-20s | %-8s\n" "Subscription ID" "Resource Group" "API Management Name" "Location" "SKU" "Enabled"
printf "%s\n" "-------------------------------------|---------------------------|---------------------------|----------------------|----------------------|----------"

# Parse each result and format with printf
for RESULT in "${RESULTS[@]}"; do
    # Extract fields from the pipe-delimited result
    SUB=$(echo "$RESULT" | cut -d'|' -f2 | tr -d ' ')
    RG=$(echo "$RESULT" | cut -d'|' -f3 | tr -d ' ')
    NAME=$(echo "$RESULT" | cut -d'|' -f4 | tr -d ' ')
    LOC=$(echo "$RESULT" | cut -d'|' -f5 | tr -d ' ')
    SKU=$(echo "$RESULT" | cut -d'|' -f6 | tr -d ' ')
    ENABLED=$(echo "$RESULT" | cut -d'|' -f7 | tr -d ' ')

    # Format with consistent spacing
    printf "%-36s | %-25s | %-25s | %-20s | %-20s | %-8s\n" "$SUB" "$RG" "$NAME" "$LOC" "$SKU" "$ENABLED"
done

echo -e "\nDone."