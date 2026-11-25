targetScope = 'resourceGroup'

@description('Chosen by MicroHack. Existing environments remain in their current resource group region.')
param location string = resourceGroup().location

@minLength(1)
@description('Participant Entra user object IDs supplied by MicroHack.')
param participantObjectIds array

var accountName = 'foundry-${uniqueString(resourceGroup().id)}'
var projectName = 'bootcamp'
// Azure AI User is now displayed as Foundry User; the built-in role ID is unchanged.
var azureAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Winter Bootcamp'
    description: 'One participant project shared by all six independent labs.'
  }
}

// Capacity is 10 units per model per participant. Organizers verify current TPM/RPM mappings and quota.
resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: 'bootcamp-chat'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5.4-mini'
      version: '2026-03-17'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource embedding 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: 'bootcamp-embedding'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  dependsOn: [
    chat
  ]
}

resource participantAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for participantId in union(participantObjectIds, []): {
  name: guid(account.id, participantId, azureAiUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: azureAiUserRoleId
    principalId: participantId
    principalType: 'User'
  }
}]

output FoundryProjectEndpoint string = uri(account.properties.endpoints['AI Foundry API'], 'api/projects/${project.name}')
output ChatDeploymentName string = 'bootcamp-chat'
output EmbeddingDeploymentName string = 'bootcamp-embedding'
