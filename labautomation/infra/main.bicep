// PROTOTYPE: inferred from syash-git/foundryIQ-rag-workshop@973494c prerequisites. Unwired and never deployed.
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param allowedEntraUserIds array = []
param chatModelName string = 'gpt-4.1-mini'
param chatModelVersion string = '2025-04-14'
param embeddingModelName string = 'text-embedding-3-large'
param embeddingModelVersion string = '1'
param containerName string = 'it-desk'

var suffix = uniqueString(resourceGroup().id)

var roles = {
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  azureAIUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
  azureAIProjectManager: 'eadc314b-1a2d-4efa-be10-5d325db5065e'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${suffix}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: 'srch-${suffix}'
  location: location
  sku: { name: 'basic' }
  identity: { type: 'SystemAssigned' }
  properties: {
    semanticSearch: 'standard'
    authOptions: {
      aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' }
    }
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'aif-${suffix}'
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: 'aif-${suffix}'
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: 'bootcamp'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: chatModelName
  sku: { name: 'GlobalStandard', capacity: 30 }
  properties: {
    model: { format: 'OpenAI', name: chatModelName, version: chatModelVersion }
  }
}

resource embedding 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: embeddingModelName
  sku: { name: 'GlobalStandard', capacity: 30 }
  properties: {
    model: { format: 'OpenAI', name: embeddingModelName, version: embeddingModelVersion }
  }
  dependsOn: [ chat ]
}

// Search managed identity invokes the chat and embedding deployments.
resource searchToFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, search.id, roles.cognitiveServicesOpenAIUser)
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

// Managed-identity alternative to the source workshop's storage connection string.
resource searchToStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, search.id, roles.storageBlobDataReader)
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataReader)
  }
}

// Foundry project managed identity reads the knowledge base through the agent's MCP connection.
resource projectToSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, project.id, roles.searchIndexDataReader)
  properties: {
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataReader)
  }
}

resource participantSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in allowedEntraUserIds: {
  scope: search
  name: guid(search.id, id, roles.searchServiceContributor)
  properties: {
    principalId: id
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
  }
}]

resource participantSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in allowedEntraUserIds: {
  scope: search
  name: guid(search.id, id, roles.searchIndexDataContributor)
  properties: {
    principalId: id
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}]

resource participantFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in allowedEntraUserIds: {
  scope: foundry
  name: guid(foundry.id, id, roles.azureAIUser)
  properties: {
    principalId: id
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.azureAIUser)
  }
}]

resource participantProjectManager 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in allowedEntraUserIds: {
  scope: foundry
  name: guid(foundry.id, id, roles.azureAIProjectManager)
  properties: {
    principalId: id
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.azureAIProjectManager)
  }
}]

output FOUNDRY_PROJECT_ENDPOINT string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${project.name}'
output FOUNDRY_PROJECT_RESOURCE_ID string = project.id
output AZURE_SEARCH_ENDPOINT string = 'https://${search.name}.search.windows.net'
output AZURE_OPENAI_ENDPOINT string = 'https://${foundry.name}.openai.azure.com'
output AZURE_STORAGE_CONTAINER_NAME string = container.name
output AZURE_OPENAI_CHAT_DEPLOYMENT string = chat.name
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = embedding.name
