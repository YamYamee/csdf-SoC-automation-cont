// automation.bicep
// Deploys an Automation Account with Managed Identity and pre-populates variables

// ===== Parameters (Inputs from main.bicep) =====

@description('Location for all resources.')
param location string

@description('Name of the Automation Account.')
param automationAccountName string

@description('Resource ID of the Log Analytics Workspace (for diagnostic settings).')
param logAnalyticsWorkspaceId string

@description('Name of the Key Vault to be stored as a variable.')
param keyVaultName string

@description('Name of the Storage Account to be stored as a variable.')
param storageAccountName string

@description('Name of the resource group (for logging purposes).')
param resourceGroupName string

// ===== Resources =====

// 1. Automation Account
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  properties: {
    sku: {
      // Basic tier (Free tier is deprecated)
      name: 'Basic'
    }
  }
  // [Key 1] Enable System-Assigned Managed Identity
  // This creates a 'robot ID' for this account, which we will grant RBAC access to.
  identity: {
    type: 'SystemAssigned'
  }
}

// 2. Automation Variables (as child resources)
// These variables are injected into the account for runbooks to use.

resource varKeyVault 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount // Child resource
  name: 'destKV'
  properties: {
    description: 'The name of the keyvault to store secrets'
    // PowerShell runbooks often expect the value to be a string literal, including the quotes
    value: '"${keyVaultName}"'
  }
}

resource varStorage 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'destSAblob'
  properties: {
    description: 'The name of the storage account for BLOB'
    value: '"${storageAccountName}"'
  }
}

resource varStorageFile 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'destSAfile'
  properties: {
    description: 'The name of the storage account for FILE (same as blob for this deployment)'
    value: '"${storageAccountName}"'
  }
}

resource varResourceGroup 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'destRGName'
  properties: {
    description: 'The name of the resource group'
    value: '"${resourceGroupName}"'
  }
}

resource varSubscription 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'destSubId'
  properties: {
    description: 'The subscription ID'
    value: '"${subscription().subscriptionId}"'
  }
}

// 3. Diagnostic Settings (send Automation logs to Log Analytics)
resource automationDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: automationAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        category: 'JobStreams'
        enabled: true
      }
      {
        category: 'DscNodeStatus'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// 4. Hybrid Worker Group
resource hybridWorkerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2023-11-01' = {
  parent: automationAccount
  name: 'soc-hrw-group'
  properties: {}
}

// 5. PowerShell Modules for Runbooks
// Az.Accounts is the base module required for Azure authentication
resource moduleAzAccounts 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.Accounts'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Accounts/3.0.4'
    }
  }
}

// Az.Compute for VM and snapshot operations
resource moduleAzCompute 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.Compute'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Compute/8.3.0'
    }
  }
  dependsOn: [
    moduleAzAccounts
  ]
}

// Az.Storage for storage account operations
resource moduleAzStorage 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.Storage'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Storage/7.3.0'
    }
  }
  dependsOn: [
    moduleAzAccounts
  ]
}

// Az.KeyVault for Key Vault secret operations
resource moduleAzKeyVault 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.KeyVault'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.KeyVault/6.2.0'
    }
  }
  dependsOn: [
    moduleAzAccounts
  ]
}

// Az.Resources for resource management
resource moduleAzResources 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.Resources'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Resources/7.4.0'
    }
  }
  dependsOn: [
    moduleAzAccounts
  ]
}

// ===== Outputs (Return to main.bicep) =====

@description('The Resource ID of the created Automation Account.')
output automationAccountId string = automationAccount.id

@description('The Principal ID (Object ID) of the Automation Account (for RBAC).')
// [Key 2] Output the Managed Identity's ID. This is CRITICAL for step 3.5 (RBAC).
output automationAccountPrincipalId string = automationAccount.identity.principalId

@description('The name of the Hybrid Worker Group.')
output hybridWorkerGroupName string = hybridWorkerGroup.name
