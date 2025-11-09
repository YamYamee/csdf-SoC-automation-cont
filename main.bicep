// main.bicep
// Main deployment file for SOC team

// [Key 1] Deploy at subscription level (enables resource group creation)
targetScope = 'subscription'

// ===== Parameters =====

@description('Whether to create a new resource group (true: create, false: use existing)')
param createNewResourceGroup bool = true

@description('Resource group name (for new creation or existing group)')
param resourceGroupName string

@description('Azure region to deploy resources')
param location string = 'koreacentral'

@description('Virtual Network name')
param vnetName string = 'vnet-soc'

@description('VNet address prefix (CIDR notation)')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Storage account name (must be globally unique, lowercase+numbers only, 3-24 chars)')
param storageAccountName string

@description('Azure AD Object ID to grant storage access (get via: az ad signed-in-user show --query id -o tsv)')
param principalId string

@description('Principal type for RBAC assignment')
@allowed(['User', 'ServicePrincipal', 'Group'])
param principalType string = 'User'

@description('Allowed public IP addresses for storage access (CIDR notation). Leave empty for full network isolation.')
param allowedIpAddresses array = []

@description('Enable network isolation (Deny all public access except allowed IPs)')
param enableNetworkIsolation bool = true

@description('Key Vault name (must be globally unique, 3-24 chars)')
param keyVaultName string

@description('Automation Account name')
param automationAccountName string

@description('Log Analytics Workspace name (must be globally unique)')
param logAnalyticsWorkspaceName string = 'log-soc-${uniqueString(resourceGroupName)}'

@description('VM name for Hybrid Runbook Worker')
param vmName string = 'vm-soc-hrw'

@description('VM admin username')
param vmAdminUsername string

@description('VM admin password')
@secure()
param vmAdminPassword string

// ===== Resource Group (Conditional Creation) =====

// Create resource group only when createNewResourceGroup is true
resource newResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (createNewResourceGroup) {
  name: resourceGroupName
  location: location
  tags: {
    purpose: 'SOC-forensic-evidence'
    createdBy: 'bicep-deployment'
  }
}

// ===== Module 1: Virtual Network =====

// Deploy VNet to new resource group
module vnetModuleNew './vnet.bicep' = if (createNewResourceGroup) {
  name: 'vnetDeployment'
  scope: newResourceGroup
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
  }
}

// Deploy VNet to existing resource group
module vnetModuleExisting './vnet.bicep' = if (!createNewResourceGroup) {
  name: 'vnetDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
  }
}

// ===== Module 2: Log Analytics Workspace =====

module loggingModuleNew 'logging.bicep' = if (createNewResourceGroup) {
  name: 'loggingDeployment'
  scope: newResourceGroup
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    retentionInDays: 90
  }
}

module loggingModuleExisting 'logging.bicep' = if (!createNewResourceGroup) {
  name: 'loggingDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    retentionInDays: 90
  }
}

// ===== Module 3: Automation Account =====

module automationModuleNew 'automation.bicep' = if (createNewResourceGroup) {
  name: 'automationDeployment'
  scope: newResourceGroup
  params: {
    location: location
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceId: loggingModuleNew!.outputs.workspaceId
    keyVaultName: keyVaultName
    storageAccountName: storageAccountName
    resourceGroupName: resourceGroupName
  }
}

module automationModuleExisting 'automation.bicep' = if (!createNewResourceGroup) {
  name: 'automationDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceId: loggingModuleExisting!.outputs.workspaceId
    keyVaultName: keyVaultName
    storageAccountName: storageAccountName
    resourceGroupName: resourceGroupName
  }
}

// ===== Module 4: Virtual Machine (Hybrid Runbook Worker) =====

module vmModuleNew 'vm.bicep' = if (createNewResourceGroup) {
  name: 'vmDeployment'
  scope: newResourceGroup
  params: {
    location: location
    vmName: vmName
    subnetId: vnetModuleNew!.outputs.vmSubnetId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
  }
  dependsOn: [
    automationModuleNew
  ]
}

module vmModuleExisting 'vm.bicep' = if (!createNewResourceGroup) {
  name: 'vmDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    vmName: vmName
    subnetId: vnetModuleExisting!.outputs.vmSubnetId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
  }
  dependsOn: [
    automationModuleExisting
  ]
}

// ===== VM RBAC: Subscription-level Contributor =====

// Role Definition ID
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// VM: Subscription-level Contributor (for creating snapshots across all resource groups)
resource vmSubscriptionContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, vmName, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: createNewResourceGroup ? vmModuleNew!.outputs.vmPrincipalId : vmModuleExisting!.outputs.vmPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Hybrid Worker VM to create snapshots and access VMs in any resource group'
  }
}

// ===== Module 4.5: Hybrid Worker Registration =====
// Registers the VM as a Hybrid Runbook Worker

module hybridWorkerModuleNew 'hybridworker.bicep' = if (createNewResourceGroup) {
  name: 'hybridWorkerDeployment'
  scope: newResourceGroup
  params: {
    location: location
    automationAccountName: automationAccountName
    hybridWorkerGroupName: automationModuleNew!.outputs.hybridWorkerGroupName
    vmName: vmName
    vmResourceId: vmModuleNew!.outputs.vmId
  }
}

module hybridWorkerModuleExisting 'hybridworker.bicep' = if (!createNewResourceGroup) {
  name: 'hybridWorkerDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    automationAccountName: automationAccountName
    hybridWorkerGroupName: automationModuleExisting!.outputs.hybridWorkerGroupName
    vmName: vmName
    vmResourceId: vmModuleExisting!.outputs.vmId
  }
}

// ===== Module 5: Storage Account =====
// Deployed after Automation and VM so we can grant them access

module storageModuleNew './storage.bicep' = if (createNewResourceGroup) {
  name: 'storageDeployment'
  scope: newResourceGroup
  params: {
    location: location
    storageAccountName: storageAccountName
    allowedIpAddresses: allowedIpAddresses
    enableNetworkIsolation: enableNetworkIsolation
    vmPrincipalId: vmModuleNew!.outputs.vmPrincipalId
    automationAccountPrincipalId: automationModuleNew!.outputs.automationAccountPrincipalId
    userPrincipalId: principalId
    userPrincipalType: principalType
    privateEndpointSubnetId: vnetModuleNew!.outputs.privateEndpointSubnetId
  }
}

module storageModuleExisting './storage.bicep' = if (!createNewResourceGroup) {
  name: 'storageDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    storageAccountName: storageAccountName
    allowedIpAddresses: allowedIpAddresses
    enableNetworkIsolation: enableNetworkIsolation
    vmPrincipalId: vmModuleExisting!.outputs.vmPrincipalId
    automationAccountPrincipalId: automationModuleExisting!.outputs.automationAccountPrincipalId
    userPrincipalId: principalId
    userPrincipalType: principalType
    privateEndpointSubnetId: vnetModuleExisting!.outputs.privateEndpointSubnetId
  }
}

// ===== Module 6: Key Vault =====
// Deployed after Automation and VM so we can grant them access

module keyVaultModuleNew 'keyvault.bicep' = if (createNewResourceGroup) {
  name: 'keyVaultDeployment'
  scope: newResourceGroup
  params: {
    location: location
    keyVaultName: keyVaultName
    privateEndpointSubnetId: vnetModuleNew!.outputs.privateEndpointSubnetId
    vmPrincipalId: vmModuleNew!.outputs.vmPrincipalId
    automationAccountPrincipalId: automationModuleNew!.outputs.automationAccountPrincipalId
  }
}

module keyVaultModuleExisting 'keyvault.bicep' = if (!createNewResourceGroup) {
  name: 'keyVaultDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    keyVaultName: keyVaultName
    privateEndpointSubnetId: vnetModuleExisting!.outputs.privateEndpointSubnetId
    vmPrincipalId: vmModuleExisting!.outputs.vmPrincipalId
    automationAccountPrincipalId: automationModuleExisting!.outputs.automationAccountPrincipalId
  }
}

// ===== Module 7: Runbook =====

module runbookModuleNew 'runbook.bicep' = if (createNewResourceGroup) {
  name: 'runbookDeployment'
  scope: newResourceGroup
  params: {
    automationAccountName: automationAccountName
    location: location
    runbookName: 'Copy-VmDigitalEvidence'
  }
  dependsOn: [
    automationModuleNew
  ]
}

module runbookModuleExisting 'runbook.bicep' = if (!createNewResourceGroup) {
  name: 'runbookDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    automationAccountName: automationAccountName
    location: location
    runbookName: 'Copy-VmDigitalEvidence'
  }
  dependsOn: [
    automationModuleExisting
  ]
}

// ===== Outputs =====

@description('Used resource group name')
output usedResourceGroupName string = resourceGroupName

@description('Whether a new resource group was created')
output createdNewResourceGroup bool = createNewResourceGroup

@description('VNet resource ID')
output vnetId string = createNewResourceGroup ? vnetModuleNew!.outputs.vnetId : vnetModuleExisting!.outputs.vnetId

@description('Private Endpoint subnet ID')
output privateEndpointSubnetId string = createNewResourceGroup
  ? vnetModuleNew!.outputs.privateEndpointSubnetId
  : vnetModuleExisting!.outputs.privateEndpointSubnetId

@description('VM subnet ID')
output vmSubnetId string = createNewResourceGroup
  ? vnetModuleNew!.outputs.vmSubnetId
  : vnetModuleExisting!.outputs.vmSubnetId

@description('Deployed storage account ID')
output storageAccountId string = createNewResourceGroup
  ? storageModuleNew!.outputs.storageAccountId
  : storageModuleExisting!.outputs.storageAccountId

@description('Storage container name')
output storageContainerName string = createNewResourceGroup
  ? storageModuleNew!.outputs.containerName
  : storageModuleExisting!.outputs.containerName

@description('Storage file share name')
output storageFileShareName string = createNewResourceGroup
  ? storageModuleNew!.outputs.fileShareName
  : storageModuleExisting!.outputs.fileShareName

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = createNewResourceGroup
  ? loggingModuleNew!.outputs.workspaceId
  : loggingModuleExisting!.outputs.workspaceId

@description('Automation Account ID')
output automationAccountId string = createNewResourceGroup
  ? automationModuleNew!.outputs.automationAccountId
  : automationModuleExisting!.outputs.automationAccountId

@description('Automation Account Principal ID')
output automationAccountPrincipalId string = createNewResourceGroup
  ? automationModuleNew!.outputs.automationAccountPrincipalId
  : automationModuleExisting!.outputs.automationAccountPrincipalId

@description('Key Vault ID')
output keyVaultId string = createNewResourceGroup
  ? keyVaultModuleNew!.outputs.keyVaultId
  : keyVaultModuleExisting!.outputs.keyVaultId

@description('Key Vault URI')
output keyVaultUri string = createNewResourceGroup
  ? keyVaultModuleNew!.outputs.keyVaultUri
  : keyVaultModuleExisting!.outputs.keyVaultUri

@description('VM ID')
output vmId string = createNewResourceGroup ? vmModuleNew!.outputs.vmId : vmModuleExisting!.outputs.vmId

@description('VM Principal ID')
output vmPrincipalId string = createNewResourceGroup
  ? vmModuleNew!.outputs.vmPrincipalId
  : vmModuleExisting!.outputs.vmPrincipalId

@description('Runbook Name')
output runbookName string = createNewResourceGroup
  ? runbookModuleNew!.outputs.runbookName
  : runbookModuleExisting!.outputs.runbookName

@description('Hybrid Worker Group Name')
output hybridWorkerGroupName string = createNewResourceGroup
  ? automationModuleNew!.outputs.hybridWorkerGroupName
  : automationModuleExisting!.outputs.hybridWorkerGroupName

@description('Hybrid Worker ID')
output hybridWorkerId string = createNewResourceGroup
  ? hybridWorkerModuleNew!.outputs.hybridWorkerId
  : hybridWorkerModuleExisting!.outputs.hybridWorkerId

@description('Deployment location')
output deploymentLocation string = location
