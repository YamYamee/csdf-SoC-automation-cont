// logging.bicep
// Creates a central Log Analytics Workspace for SOC logging

// ===== Parameters (Inputs from main.bicep) =====

@description('Location for the Log Analytics Workspace.')
param location string

@description('Name for the Log Analytics Workspace (must be globally unique).')
param logAnalyticsWorkspaceName string = 'default-soc-log'

@description('Log retention in days.')
param retentionInDays int = 90 // (SOC/Forensics standard)

// ===== Resources =====

// 1. Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    // Pay-as-you-go SKU
    sku: {
      name: 'PerGB2018'
    }
    // Set data retention
    retentionInDays: retentionInDays
    
    // [Security] We can also lock this down with Private Endpoints later
  }
}

// ===== Outputs (Return to main.bicep) =====

@description('The Resource ID of the created Log Analytics Workspace.')
output workspaceId string = logAnalyticsWorkspace.id
