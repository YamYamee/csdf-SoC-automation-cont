// hybridworker.bicep
// Registers the VM as a Hybrid Runbook Worker and installs the extension

// ===== Parameters =====

@description('Location for resources.')
param location string

@description('Name of the Automation Account.')
param automationAccountName string

@description('Name of the Hybrid Worker Group.')
param hybridWorkerGroupName string

@description('Name of the Virtual Machine.')
param vmName string

@description('Resource ID of the Virtual Machine.')
param vmResourceId string

// ===== Resources =====

// Reference to existing Automation Account
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

// Reference to existing Hybrid Worker Group
resource hybridWorkerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2023-11-01' existing = {
  parent: automationAccount
  name: hybridWorkerGroupName
}

// Reference to existing VM
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: vmName
}

// Step 1: Register VM to Hybrid Worker Group
// This creates the association in Azure Automation
resource hybridWorker 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers@2023-11-01' = {
  parent: hybridWorkerGroup
  name: guid(vmResourceId) // Use GUID of VM resource ID as worker name
  properties: {
    vmResourceId: vmResourceId
  }
}

// Step 2: Install Hybrid Worker Extension on VM
resource hybridWorkerExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'HybridWorkerExtension'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Automation.HybridWorker'
    type: 'HybridWorkerForWindows'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      AutomationAccountURL: automationAccount.properties.automationHybridServiceUrl
    }
  }
  dependsOn: [
    hybridWorker
  ]
}

// ===== Outputs =====

@description('Hybrid Worker ID')
output hybridWorkerId string = hybridWorker.id

@description('Hybrid Worker Name')
output hybridWorkerName string = hybridWorker.name

@description('Hybrid Worker Extension Name')
output hybridWorkerExtensionName string = hybridWorkerExtension.name
