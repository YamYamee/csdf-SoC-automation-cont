// vnet.bicep - Virtual Network for SOC team

// ===== Parameters =====

@description('Azure region to deploy VNet')
param location string

@description('Virtual Network name')
param vnetName string

@description('VNet address prefix (CIDR notation)')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Private Endpoint subnet name')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('Private Endpoint subnet address prefix')
param privateEndpointSubnetPrefix string = '10.0.1.0/24'

@description('VM/Compute subnet name')
param vmSubnetName string = 'soc-subnet'

@description('VM/Compute subnet address prefix')
param vmSubnetPrefix string = '10.0.2.0/24'

// ===== NSG for Private Endpoint Subnet =====

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${privateEndpointSubnetName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all inbound traffic (Private Endpoints handle their own rules)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ===== NSG for VM Subnet =====

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${vmSubnetName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          description: 'Allow HTTPS inbound for management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ===== Virtual Network =====

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointNsg.id
          }
          // [Important] Disable private endpoint network policies for Private Endpoints
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: {
            id: vmNsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ===== Outputs =====

@description('Virtual Network resource ID')
output vnetId string = vnet.id

@description('Virtual Network name')
output vnetName string = vnet.name

@description('Private Endpoint subnet resource ID')
output privateEndpointSubnetId string = vnet.properties.subnets[0].id

@description('Private Endpoint subnet name')
output privateEndpointSubnetName string = vnet.properties.subnets[0].name

@description('VM subnet resource ID')
output vmSubnetId string = vnet.properties.subnets[1].id

@description('VM subnet name')
output vmSubnetName string = vnet.properties.subnets[1].name

@description('VNet address space')
output vnetAddressSpace string = vnetAddressPrefix

@description('Private Endpoint NSG ID')
output privateEndpointNsgId string = privateEndpointNsg.id

@description('VM NSG ID')
output vmNsgId string = vmNsg.id
