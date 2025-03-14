# Discover Direct Management API Use in API Management Instances

The Direct management API Management REST API is deprecated and will be [retired in March 2025](https://learn.microsoft.com/rest/api/apimanagement/apimanagementrest/api-management-rest).

**Azure API Management instances will continue to function as-usual regardless!** The deprecation and this script only address the tooling to manage the instance.

This repo helps discover which API Management in your instances have this API enabled. The new V2 SKUs are not affected by this.

## Prerequisites

This script requires the [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) to be installed prior to execution.

## Execution

1. Clone the repo or just download the script.
1. If you pass an Azure tenant ID, just select any subscription, if asked for one. The script loops over all subscriptions in your tenant.

```sh
Usage:
  ./apim-direct-management-api-statistics.sh -t <tenant-id>   - Logs into specific Azure tenant and checks all subscriptions
  ./apim-direct-management-api-statistics.sh -sl              - Skips login and uses the current Azure CLI session's Azure tenant

Examples:
  ./apim-direct-management-api-statistics.sh -t 12345678-1234-1234-1234-123456789012
```

You can also hard-code a test subscription at the top of the shell script to check a specific subscription.

## Results

The results will be displayed at the end of the run. You need to take action on any instance that has the API enabled as your tooling may soon no longer work.

![Output](output.png)
