# api-management-discover-direct-management-api-status

The Direct management API Management REST API is deprecated and will be [retired in March 2025](https://learn.microsoft.com/rest/api/apimanagement/apimanagementrest/api-management-rest).

This repo helps discover which API Management in your instances have this API enabled.

Run the following script with your Azure tenant ID and any subscription ID that you have access to. It will subsequently loop over all subscriptions in your tenant.

```sh
./apim-direct-management-api-statistics.sh <tenant-id> <subscription-id>
```
