#!/bin/bash

# Azure CLI script to log into an Azure tenant, loop over all of its subscriptions to search for API Management instances,
# then check which one have the Direct Management API enabled as it is end-of-life March 2025.

# Hard-code a test subscription, if you wish.
#HARDCODED_SUBSCRIPTION="<your-subscription-id>"

echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if tenant ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <tenant-id>"
    echo "Example: $0 your-tenant-id"
    exit 1
fi

# Log in
TENANT_ID=${1}
echo "Logging into Azure tenant $TENANT_ID..."
az login --tenant "$TENANT_ID"

if [ $? -ne 0 ]; then
    echo "Error: Failed to log into Azure. Please check your credentials and try again."
    exit 1
fi

echo "Successfully logged into Azure."

# -------------------------------------------------------------------------------------------------

echo "------------------------------------------------------"

# Check if HARDCODED_SUBSCRIPTION has a real value (not empty and not the placeholder)
if [[ -n "$HARDCODED_SUBSCRIPTION" && "$HARDCODED_SUBSCRIPTION" != "<your-subscription-id>" ]]; then
    echo "Using hardcoded subscription: $HARDCODED_SUBSCRIPTION"
    SUBSCRIPTIONS="$HARDCODED_SUBSCRIPTION"
else
    echo "Retrieving all subscriptions in tenant: $TENANT_ID"

    # Get all subscriptions
    SUBSCRIPTIONS=$(az account list --query '[].id' -o tsv)

    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve subscriptions."
        exit 1
    fi

    echo "Found $(echo "$SUBSCRIPTIONS" | wc -l) subscription(s) in tenant."
fi

# Initialize JSON array for results
JSON_RESULTS="["

# Search for API Management instances across all subscriptions
echo "------------------------------------------------------"
echo -e "Searching for API Management instances across all subscriptions:\n"

# Count total subscriptions
TOTAL_SUBS=$(echo "$SUBSCRIPTIONS" | wc -l)
CURRENT_SUB=0
FIRST_ENTRY=true

for SUB in $SUBSCRIPTIONS; do
    # Increment counter
    CURRENT_SUB=$((CURRENT_SUB + 1))

    # Trim any whitespace or control characters from the subscription ID
    SUB=$(echo "$SUB" | tr -d '\r\n')

    echo -e "\n$CURRENT_SUB/$TOTAL_SUBS: Checking subscription: $SUB"

    # Set context to current subscription and check if successful
    if ! az account set --subscription "$SUB" > /dev/null 2>&1; then
        echo -e "\tYou may not have access to this subscription. Skipping."
        continue
    fi

    # First check if there are any APIM instances in this subscription
    INSTANCE_COUNT=$(az apim list --subscription "$SUB" --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo -e "\tFound $INSTANCE_COUNT API Management instance(s).\n"

        # Get all APIM instances with details
        APIM_INSTANCES=$(az apim list --subscription "$SUB" --query "[].{name:name, resourceGroup:resourceGroup, location:location, sku:sku.name}" -o tsv 2>/dev/null)

        # Process and display in table format
        while IFS=$'\t' read -r name resourceGroup location sku; do
            if [ -n "$name" ]; then
                echo -e "\tGetting tenant access information for API Management instance $name in resource group $resourceGroup..."

                # Check if we have a V2 SKU as the Direct Management API does not apply there.
                if [[ "$sku" == *"V2"* ]]; then
                    # For V2 SKUs, tenant access is not applicable
                    ENABLED="Not Applicable"
                    echo -e "\t\tSKU is V2. Tenant access is not applicable."
                else
                    # For V1 SKUs, check tenant access status

                    # Call REST API using az rest and capture JSON output
                    TENANT_ACCESS=$(az rest --method GET \
                        --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$name/tenant/access?api-version=2022-08-01" \
                        --output json 2>/dev/null)

                    # Check if the REST call was successful
                    REST_STATUS=$?

                    if [ $REST_STATUS -eq 0 ] && [ -n "$TENANT_ACCESS" ]; then
                        # Extract the enabled status - grab text after "enabled": and before comma or }
                        ENABLED=$(echo "$TENANT_ACCESS" | grep -o '"enabled": *[^,}]*' | awk -F': ' '{print $2}' | tr -d ' "')

                        echo -e "\t\tTenant access enabled: $ENABLED"
                    else
                        ENABLED="UNKNOWN"
                    fi
                fi

                # Add comma for JSON array elements except for first element
                if [ "$FIRST_ENTRY" = true ]; then
                    FIRST_ENTRY=false
                else
                    JSON_RESULTS+=","
                fi

                # Add this instance to the JSON array
                JSON_RESULTS+=$(printf '\n  {"subscription":"%s","resourceGroup":"%s","name":"%s","location":"%s","sku":"%s","enabled":"%s"}' \
                    "$SUB" "$resourceGroup" "$name" "$location" "$sku" "$ENABLED")
            fi
        done <<< "$APIM_INSTANCES"
    else
        echo -e "\tNo API Management instances found."
    fi
done

# Close JSON array
JSON_RESULTS+="\n]"

# -------------------------------------------------------------------------------------------------

echo -e "\n------------------------------------------------------\n"

# Print headers
printf "%-36s | %-45s | %-45s | %-20s | %-12s | %-15s\n" \
    "Subscription ID" "Resource Group" "API Management Name" "Location" "SKU" "Enabled"

# Print separator line
printf "%s\n" "$(printf '=%.0s' {1..187})"

# Process each JSON object
echo "$JSON_RESULTS" | grep -o '{[^}]*}' | while read -r line; do
    SUB=$(echo "$line" | grep -o '"subscription":"[^"]*"' | cut -d'"' -f4)
    RG=$(echo "$line" | grep -o '"resourceGroup":"[^"]*"' | cut -d'"' -f4)
    NAME=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    LOC=$(echo "$line" | grep -o '"location":"[^"]*"' | cut -d'"' -f4)
    SKU=$(echo "$line" | grep -o '"sku":"[^"]*"' | cut -d'"' -f4)
    ENABLED=$(echo "$line" | grep -o '"enabled":"[^"]*"' | cut -d'"' -f4)

    printf "%-36s | %-45s | %-45s | %-20s | %-12s | %-15s\n" \
        "$SUB" "$RG" "$NAME" "$LOC" "$SKU" "$ENABLED"

done

# Count results by enabled status
TOTAL_COUNT=$(echo -e "$JSON_RESULTS" | grep -c "name")
ENABLED_COUNT=$(echo -e "$JSON_RESULTS" | grep -c '"enabled":"true"')
DISABLED_COUNT=$(echo -e "$JSON_RESULTS" | grep -c '"enabled":"false"')
UNKNOWN_COUNT=$(echo -e "$JSON_RESULTS" | grep -c '"enabled":"UNKNOWN"')

echo ""
echo "Total instances : $TOTAL_COUNT"
echo "Enabled         : $ENABLED_COUNT  <-- Update any tooling using the enabled Direct Management API!"
echo "Disabled        : $DISABLED_COUNT"
echo "Unknown         : $UNKNOWN_COUNT"

echo -e "\nDone."
