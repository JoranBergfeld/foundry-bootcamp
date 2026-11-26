targetScope = 'resourceGroup'

@description('Chosen by MicroHack. Existing environments remain in their current resource group region.')
param location string = resourceGroup().location

@minLength(1)
@description('Participant Entra user object IDs supplied by MicroHack.')
param participantObjectIds array

@minLength(1)
@description('Object ID of the authenticated MicroHack provisioner.')
param provisionerObjectId string

var accountName = 'foundry-${uniqueString(resourceGroup().id)}'
var projectName = 'bootcamp'
var searchName = 'srch-${uniqueString(resourceGroup().id)}'
var storageName = 'st${uniqueString(resourceGroup().id)}'
var logsName = 'log-${uniqueString(resourceGroup().id)}'
var insightsName = 'appi-${uniqueString(resourceGroup().id)}'
// Azure AI User is now displayed as Foundry User; the built-in role ID is unchanged.
var azureAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
var monitoringMetricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var searchServiceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var searchIndexDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchIndexDataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageBlobDataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var provisionerIsParticipant = contains(map(participantObjectIds, participantId => toLower(participantId)), toLower(provisionerObjectId))

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

// Basic is the smallest SKU with Entra data-plane RBAC, managed identity and semantic ranking for the labs.
resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchName
  location: location
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    disableLocalAuth: true
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storage
  name: 'default'
}

resource baselineContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  // #17 uploads the shared baseline dataset here; keep the name stable.
  name: 'baseline'
  properties: {
    publicAccess: 'None'
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      disableLocalAuth: true
    }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
    DisableLocalAuth: true
  }
}

// The resource provider requires this routing metadata even with project-managed identity.
// The RP/SDK accept ProjectManagedIdentity, but the published 2025-06-01 Bicep types predate it.
resource tracingConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: 'bootcamp-tracing'
  properties: {
    category: 'AppInsights'
    target: insights.id
    #disable-next-line BCP036
    authType: 'ProjectManagedIdentity'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: insights.id
      ApplicationInsightsConnectionString: insights.properties.ConnectionString
    }
  }
}

resource projectTraceIngestion 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(insights.id, project.id, monitoringMetricsPublisherRoleId)
  scope: insights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleId
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Participants build and query indexes and upload lab data with their own Entra identity.
resource participantSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for participantId in union(participantObjectIds, []): {
  name: guid(search.id, participantId, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: participantId
    principalType: 'User'
  }
}]

resource participantSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for participantId in union(participantObjectIds, []): {
  name: guid(search.id, participantId, searchIndexDataContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchIndexDataContributorRoleId
    principalId: participantId
    principalType: 'User'
  }
}]

resource participantBlobData 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for participantId in union(participantObjectIds, []): {
  name: guid(storage.id, participantId, storageBlobDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: participantId
    principalType: 'User'
  }
}]

resource provisionerSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!provisionerIsParticipant) {
  name: guid(search.id, provisionerObjectId, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: provisionerObjectId
  }
}

resource provisionerSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!provisionerIsParticipant) {
  name: guid(search.id, provisionerObjectId, searchIndexDataReaderRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchIndexDataReaderRoleId
    principalId: provisionerObjectId
  }
}

resource provisionerBlobData 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!provisionerIsParticipant) {
  name: guid(storage.id, provisionerObjectId, storageBlobDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: provisionerObjectId
  }
}

// The Foundry AI Search tool authenticates keylessly with the account identity; project-scoped
// connections use the project identity. Both get the documented Search roles.
resource accountSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, account.id, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: account.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource accountSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, account.id, searchIndexDataContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchIndexDataContributorRoleId
    principalId: account.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectSearchService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, project.id, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, project.id, searchIndexDataContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: searchIndexDataContributorRoleId
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Search indexers (#17) read the baseline container as the Search identity.
resource searchBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, search.id, storageBlobDataReaderRoleId)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataReaderRoleId
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: 'bootcamp-search'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    #disable-next-line BCP036
    authType: 'ProjectManagedIdentity'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: search.id
    }
  }
}

output FoundryProjectEndpoint string = uri(account.properties.endpoints['AI Foundry API'], 'api/projects/${project.name}')
output ChatDeploymentName string = chat.name
output EmbeddingDeploymentName string = embedding.name
output SearchEndpoint string = 'https://${search.name}.search.windows.net'
output StorageAccountName string = storage.name
output StorageBaselineContainerName string = baselineContainer.name
