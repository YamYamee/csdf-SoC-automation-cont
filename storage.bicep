// storage.bicep

// 1. (param) Input parameters for the module
param location string
param storageAccountName string

@description('Allowed public IP addresses (CIDR notation, e.g., "203.0.113.5/32"). Leave empty to deny all public access.')
param allowedIpAddresses array = []

@description('Enable network isolation (recommended for production)')
param enableNetworkIsolation bool = true

@description('Principal ID of the VM Managed Identity (Hybrid Worker)')
param vmPrincipalId string

@description('Principal ID of the Automation Account Managed Identity')
param automationAccountPrincipalId string

@description('Principal ID of the user/service principal')
param userPrincipalId string

@description('Type of user principal (User, ServicePrincipal, or Group)')
@allowed(['User', 'ServicePrincipal', 'Group'])
param userPrincipalType string = 'User'

@description('The Subnet ID where the Private Endpoint will be deployed.')
param privateEndpointSubnetId string

// Variables
// Azure Storage IP rules must be in IPv4 CIDR format (x.x.x.x or x.x.x.x/y)
var ipRules = [
  for ip in allowedIpAddresses: {
    value: ip
    action: 'Allow'
  }
]

// Role Definition IDs
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageAccountContributorRoleId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'

// 2. (resource) Step 1: Create the main storage account
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    // [Security] Allow Shared Key access for File Share mounting on Hybrid Worker
    // Note: While RBAC is preferred, File Share SMB mounting requires shared key access
    allowSharedKeyAccess: true
    // [Security] Block anonymous public blob access
    allowBlobPublicAccess: false
    // [Security] Enforce HTTPS-only traffic
    supportsHttpsTrafficOnly: true
    // [Security] Set minimum TLS version
    minimumTlsVersion: 'TLS1_2'

    // [Security] Network access control
    networkAcls: enableNetworkIsolation
      ? {
          // Default: Deny all public access
          defaultAction: 'Deny'
          // Allow trusted Azure services (e.g., Azure Monitor, Backup, Log Analytics)
          bypass: 'AzureServices'
          // IP allow list (configured via parameter)
          ipRules: ipRules
          // Virtual network rules (empty for now, can be added later)
          virtualNetworkRules: []
        }
      : {
          // If network isolation is disabled, allow all
          defaultAction: 'Allow'
          bypass: 'AzureServices'
          ipRules: []
          virtualNetworkRules: []
        }
  }
}

// 3. (resource) Step 2: Create Blob Service and enable versioning
// Declared as a child resource of the storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  // Specify 'parent' to indicate this is a child resource of the storage account
  parent: storage
  name: 'default' // (fixed value)
  properties: {
    // [Important] Versioning must be enabled to use immutable storage
    isVersioningEnabled: true
  }
}

// 4. (resource) Step 3: Declare the 'immutable' container
// [Key] Immutable container for forensic evidence storage
resource evidenceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  // Specify 'parent' as blobService (storage/default/containers)
  parent: blobService
  name: 'immutable' // (container name - matches runbook expectation)
  properties: {
    // [Key] Enable immutable storage with versioning
    immutableStorageWithVersioning: {
      enabled: true
    }
    // [Security] Block public access to the container itself
    publicAccess: 'None'
  }
}

// 4.1. (resource) Apply immutability policy to container
// Time-based retention policy for forensic evidence (1 day for testing)
resource immutabilityPolicy 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-05-01' = {
  parent: evidenceContainer
  name: 'default'
  properties: {
    immutabilityPeriodSinceCreationInDays: 1 // 1 day for testing (change to 1095 for production)
    allowProtectedAppendWrites: false // Prevent any modifications
    allowProtectedAppendWritesAll: false
  }
}

// 4.5. (resource) Create File Service for temporary hash storage
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

// 4.6. (resource) Create File Share for hash calculation
resource hashFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'hash'
  properties: {
    shareQuota: 5120 // 5TB quota for temporary hash storage
    enabledProtocols: 'SMB' // SMB protocol for Windows Hybrid Worker
  }
}

// ===== Private Endpoints =====

// Private Endpoint for File Share (enables VNet internal access without public IP)
resource privateEndpointFile 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${storageAccountName}-file-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-file-pe-conn'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'file' // File Share service
          ]
        }
      }
    ]
  }
}

// Private Endpoint for Blob Storage (enables VNet internal access to immutable evidence)
resource privateEndpointBlob 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${storageAccountName}-blob-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-blob-pe-conn'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob' // Blob Storage service
          ]
        }
      }
    ]
  }
}

// ===== RBAC Assignments =====

// 1. VM (Hybrid Worker): Storage Blob Data Contributor
resource vmStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, vmPrincipalId, 'StorageBlobDataContributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Hybrid Worker VM to upload forensic evidence to immutable storage'
  }
}

// 1-2. VM (Hybrid Worker): Storage Account Contributor (for listKeys in runbook)
resource vmStorageAccountRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, vmPrincipalId, 'StorageAccountContributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleId)
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Hybrid Worker VM to get storage keys for File Share mounting in runbook'
  }
}

// 2. Automation Account: Storage Blob Data Contributor
resource automationStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, automationAccountPrincipalId, 'StorageBlobDataContributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Automation Account to access storage'
  }
}

// 2-1. Automation Account: Storage Account Contributor (to list keys for File Share access)
resource automationStorageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, automationAccountPrincipalId, 'StorageAccountContributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleId)
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Automation Account to list storage keys for File Share mounting'
  }
}

// 3. User: Storage Blob Data Contributor
resource userStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, userPrincipalId, 'StorageBlobDataContributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId: userPrincipalId
    principalType: userPrincipalType
    description: 'Allow user to access forensic evidence in storage'
  }
}

// 8. (output) Module output values
output storageAccountId string = storage.id
output storageAccountName string = storage.name
output containerName string = evidenceContainer.name
output fileShareName string = hashFileShare.name
output networkIsolationEnabled bool = enableNetworkIsolation
output primaryEndpoint string = storage.properties.primaryEndpoints.blob
output fileEndpoint string = storage.properties.primaryEndpoints.file
