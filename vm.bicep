// vm.bicep
// Deploys a Windows VM with Hybrid Runbook Worker extension

targetScope = 'resourceGroup'

// ===== Parameters (Inputs from main.bicep) =====

@description('Location for the VM.')
param location string

@description('Name of the Virtual Machine.')
param vmName string

@description('Resource ID of the VM Subnet to connect to.')
param subnetId string

@description('Admin username for the VM.')
param adminUsername string

@description('Admin password for the VM.')
@secure()
param adminPassword string

// ===== Variables =====

var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'

// ===== Resources =====

// 1. Network Interface (NIC)
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// 2. Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D8s_v3'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        name: osDiskName
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// 3. Custom Script Extension to install Az PowerShell modules
resource vmAzModulesExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'InstallAzModules'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name Az -Repository PSGallery -Force -AllowClobber -Scope AllUsers"'
    }
  }
}

// ===== Outputs (Return to main.bicep) =====

@description('The Resource ID of the created VM.')
output vmId string = vm.id

@description('The Principal ID (Object ID) of the VM (for RBAC).')
output vmPrincipalId string = vm.identity.principalId
