// keyvault.bicep
// Creates a secure, RBAC-enabled Key Vault with a Private Endpoint

// ===== Parameters (Inputs from main.bicep) =====

@description('Location for the Key Vault.')
param location string = resourceGroup().location

@description('Globally unique name for the Key Vault.')
param keyVaultName string

@description('The Subnet ID where the Private Endpoint will be deployed.')
param privateEndpointSubnetId string

@description('Principal ID of the VM Managed Identity (Hybrid Worker)')
param vmPrincipalId string

@description('Principal ID of the Automation Account Managed Identity')
param automationAccountPrincipalId string

// ===== Variables =====

// Role Definition IDs
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ===== Resources =====

// 1. Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  location: location
  properties: {
    // [Security] Use RBAC for permissions, not legacy Access Policies
    enableRbacAuthorization: true

    // [Security] Deny all public internet access
    publicNetworkAccess: 'Disabled'

    sku: {
      family: 'A'
      name: 'standard'
    }
    // (Required for RBAC)
    tenantId: tenant().tenantId
  }
}

// 2. Private Endpoint (Secures the Key Vault to your VNet)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-10-01' = {
  name: '${keyVaultName}-pe'
  location: location
  properties: {
    // Connects this endpoint to the correct subnet
    subnet: {
      id: privateEndpointSubnetId
    }
    // Links this endpoint to the Key Vault
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-pe-conn'
        properties: {
          privateLinkServiceId: keyVault.id
          // 'vault' is the required Group ID for Key Vault
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  // (Optional but good practice) Add a Private DNS Zone Group
  // This automatically creates the 'A' record (e.g., myvault.vault.azure.net -> 10.0.1.4)
  // in a Private DNS Zone named 'privatelink.vaultcore.azure.net'.
  // We assume this zone is already created and linked to the VNet.
  // If not, it should be created in main.bicep.
}

// ===== RBAC Assignments =====

// 1. VM (Hybrid Worker): Key Vault Secrets User
resource vmKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vmPrincipalId, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Hybrid Worker VM to store hash values in Key Vault'
  }
}

// 2. Automation Account: Key Vault Secrets User
resource automationKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, automationAccountPrincipalId, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Automation Account to access Key Vault secrets'
  }
}

// ===== Outputs (Return to main.bicep) =====

@description('The Resource ID of the created Key Vault.')
output keyVaultId string = keyVault.id

@description('The URI of the created Key Vault (e.g., https://mykv.vault.azure.net).')
output keyVaultUri string = keyVault.properties.vaultUri
