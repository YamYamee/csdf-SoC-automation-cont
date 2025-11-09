// runbook.bicep
// Deploys the forensic evidence collection runbook to the Automation Account

// ===== Parameters (Inputs from main.bicep) =====

@description('Name of the Automation Account to deploy the runbook to.')
param automationAccountName string

@description('Location for the runbook.')
param location string

@description('Name of the runbook.')
param runbookName string = 'Copy-VmDigitalEvidence'

@description('Description of the runbook.')
param runbookDescription string = 'Performs digital evidence capture operation on a target VM with parallel hash calculation'

@description('GitHub repository in format: owner/repo')
param githubRepo string = 'YamYamee/csdf-soc-automation-cont'

@description('GitHub branch name')
param githubBranch string = 'main'

// ===== Resources =====

// 1. Automation Account Reference
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

// 2. Runbook
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  location: location
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: runbookDescription
    // [Key] Load script from local repository
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/${githubRepo}/${githubBranch}/Copy-VmDigitalEvidenceWin_v21.ps1'
      version: '1.0.0.0'
    }
  }
}

// Alternative: Use inline script content (for fully local deployment)
/*
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  location: location
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: runbookDescription
  }
}

// Deploy script content separately using Azure CLI or PowerShell
*/

// ===== Outputs (Return to main.bicep) =====

@description('The Resource ID of the created runbook.')
output runbookId string = runbook.id

@description('The name of the created runbook.')
output runbookName string = runbook.name

@description('The state of the runbook.')
output runbookState string = runbook.properties.state
