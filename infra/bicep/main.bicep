// =====================================================================================
// Pipeline ML événementiel sur Azure - socle complet en Bicep (bonus « Infrastructure as Code »)
// Redéploiement en une commande :  bash infra/bicep/deploy.sh
// (= az deployment group create -g rg-projet-<equipe> -f infra/bicep/main.bicep -p infra/bicep/main.bicepparam
//    + activation du site web statique, qui n'est pas une propriété ARM)
// =====================================================================================

targetScope = 'resourceGroup'

@description('Nom court de l\'équipe (minuscules / chiffres)')
param eq string

@description('Région autorisée par la stratégie de l\'abonnement et compatible Flex Consumption')
param location string = resourceGroup().location

@description('Dépôt GitHub propriétaire/nom (sujet OIDC)')
param ghRepo string

@description('Identifiants numériques GitHub (sujet OIDC immuable repo:owner@id/repo@id:...). Vide = non créé.')
param ghOwnerId string = ''
param ghRepoId string = ''

@description('Image de l\'API (GHCR public)')
param apiImage string

@description('E-mail des alertes et du budget (jamais dans le dépôt : variable d\'environnement ALERT_EMAIL)')
param alertEmail string

@description('Date de début du budget (1er jour d\'un mois, UTC)')
param budgetStartDate string = '${substring(utcNow('yyyy-MM-dd'), 0, 8)}01'

@description('Date de fin du budget (12 mois plus tard)')
param budgetEndDate string = dateTimeAdd('${budgetStartDate}T00:00:00Z', 'P1Y', 'yyyy-MM-dd')

@description('Créer les attributions de rôles (exige le rôle Owner ; false si elles existent déjà sous un autre nom)')
param assignRoles bool = true

@description('Créer l\'abonnement Event Grid (exige que la fonction dispatcher soit déjà déployée)')
param deployEventGrid bool = true

@description('Noms des ressources (surchargeables pour un environnement existant)')
param storageName string = 'st${eq}pipe'
param cosmosName string = 'cosmos-${eq}'
param lawName string = 'log-${eq}'
param appiName string = 'appi-${eq}'
param envName string = 'cae-${eq}'
param apiName string = 'api-${eq}'
param planName string = 'plan-${eq}'
param funcName string = 'func-${eq}'
param deploymentContainerName string = 'app-package-${funcName}'
param githubIdentityName string = 'id-github-${eq}'
param actionGroupName string = 'ag-${eq}'

var tags = {
  projet: 'dscc'
  equipe: eq
}
var queueName = 'inference-requests'

// Rôles intégrés
var roleStorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleStorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var roleStorageQueueDataContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var roleContributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var cosmosDataContributor = '00000000-0000-0000-0000-000000000002'

// ------------------------------------------------------------------ Stockage
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    isVersioningEnabled: true
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for c in ['input', 'output', 'rejected', 'models', deploymentContainerName]: {
    parent: blobService
    name: c
    properties: { publicAccess: 'None' }
  }
]

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource queues 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = [
  for q in [queueName, '${queueName}-poison']: {
    parent: queueService
    name: q
  }
]

// ------------------------------------------------------------------ Cosmos DB Free Tier
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: true
    enableAutomaticFailover: true
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ]
  }
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'pipeline'
  properties: {
    resource: { id: 'pipeline' }
    options: { throughput: 400 }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDb
  name: 'inferences'
  properties: {
    resource: {
      id: 'inferences'
      partitionKey: { paths: ['/fileName'], kind: 'Hash' }
    }
  }
}

// ------------------------------------------------------------------ Supervision (plafond 0,2 Go/jour)
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json('0.2') }
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appiName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

// ------------------------------------------------------------------ Container Apps (API, 0 à 2 réplicas)
resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: apiName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: cae.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
        allowInsecure: false
      }
      secrets: [
        { name: 'appi-cs', value: appi.properties.ConnectionString }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: [
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appi-cs' }
            { name: 'OTEL_SERVICE_NAME', value: 'sentiment-api' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 5
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 3
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 2
        rules: [
          { name: 'http', http: { metadata: { concurrentRequests: '20' } } }
        ]
      }
    }
  }
}

// ------------------------------------------------------------------ Function App Flex Consumption (Python 3.12, 512 Mo)
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

var webOrigin = replace(replace(storage.properties.primaryEndpoints.web, 'https://', ''), '/', '')

resource func 'Microsoft.Web/sites@2024-04-01' = {
  name: funcName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 512
        maximumInstanceCount: 100
      }
      runtime: { name: 'python', version: '3.12' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      cors: { allowedOrigins: ['https://${webOrigin}'] }
      appSettings: [
        // Connexions par identité : aucune clé ni chaîne de connexion de stockage
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'STORAGE__blobServiceUri', value: storage.properties.primaryEndpoints.blob }
        { name: 'STORAGE__queueServiceUri', value: storage.properties.primaryEndpoints.queue }
        { name: 'STORAGE__credential', value: 'managedidentity' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appi.properties.ConnectionString }
        { name: 'OTEL_SERVICE_NAME', value: 'pipeline-functions' }
        { name: 'COSMOS_ENDPOINT', value: cosmos.properties.documentEndpoint }
        { name: 'COSMOS_DATABASE', value: 'pipeline' }
        { name: 'COSMOS_CONTAINER', value: 'inferences' }
        { name: 'API_URL', value: 'https://${api.properties.configuration.ingress.fqdn}' }
        { name: 'API_TIMEOUT_SECONDS', value: '45' }
        { name: 'MAX_FILE_BYTES', value: '1000000' }
      ]
    }
  }
  dependsOn: [containers]
}

// ------------------------------------------------------------------ Identité GitHub Actions (OIDC)
resource ghIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: githubIdentityName
  location: location
  tags: tags
}

resource ghFederatedEnv 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: ghIdentity
  name: 'github-production'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${ghRepo}:environment:production'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource ghFederatedIds 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (!empty(ghOwnerId) && !empty(ghRepoId)) {
  parent: ghIdentity
  name: 'github-production-ids'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${split(ghRepo, '/')[0]}@${ghOwnerId}/${split(ghRepo, '/')[1]}@${ghRepoId}:environment:production'
    audiences: ['api://AzureADTokenExchange']
  }
  dependsOn: [ghFederatedEnv] // une seule écriture concurrente autorisée par identité
}

// ------------------------------------------------------------------ Attributions de rôles (propriétaire uniquement)
resource raFuncBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRoles) {
  name: guid(storage.id, func.id, roleStorageBlobDataOwner)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataOwner)
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raFuncQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRoles) {
  name: guid(storage.id, func.id, roleStorageQueueDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageQueueDataContributor)
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raFuncCosmos 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = if (assignRoles) {
  parent: cosmos
  name: guid(cosmos.id, func.id, cosmosDataContributor)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributor}'
    principalId: func.identity.principalId
    scope: cosmos.id
  }
}

resource raGithubRg 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRoles) {
  name: guid(resourceGroup().id, ghIdentity.id, roleContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleContributor)
    principalId: ghIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raGithubWeb 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRoles) {
  name: guid(storage.id, ghIdentity.id, roleStorageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataContributor)
    principalId: ghIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------------ Event Grid : BlobCreated sur input/ -> dispatcher
resource blobToDispatcher 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = if (deployEventGrid) {
  name: 'blob-to-dispatcher'
  scope: storage
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${func.id}/functions/dispatcher'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: ['Microsoft.Storage.BlobCreated']
      subjectBeginsWith: '/blobServices/default/containers/input/'
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 60
    }
  }
}

// ------------------------------------------------------------------ Alerte (journal, toutes les 15 min) + budget 25 $
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'pipealert'
    enabled: true
    emailReceivers: [
      { name: 'admin', emailAddress: alertEmail, useCommonAlertSchema: false }
    ]
  }
}

resource alertErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-pipeline-errors'
  location: location
  tags: tags
  properties: {
    description: 'Worker errors > 0 in the last 15 min (poison messages, API down...)'
    severity: 2
    enabled: true
    scopes: [appi.id]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'customMetrics | where name == \'pipeline.errors\' and valueSum > 0'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    autoMitigate: true
    actions: { actionGroups: [actionGroup.id] }
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'budget-${eq}'
  properties: {
    category: 'Cost'
    amount: 25
    timeGrain: 'Monthly'
    timePeriod: { startDate: budgetStartDate, endDate: budgetEndDate }
    notifications: {
      Actual_20: { enabled: true, operator: 'GreaterThan', threshold: 20, thresholdType: 'Actual', contactEmails: [alertEmail] }
      Actual_50: { enabled: true, operator: 'GreaterThan', threshold: 50, thresholdType: 'Actual', contactEmails: [alertEmail] }
      Actual_80: { enabled: true, operator: 'GreaterThan', threshold: 80, thresholdType: 'Actual', contactEmails: [alertEmail] }
    }
  }
}

// ------------------------------------------------------------------ Sorties
output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output functionHost string = func.properties.defaultHostName
output dashboardUrl string = storage.properties.primaryEndpoints.web
output githubClientId string = ghIdentity.properties.clientId
output functionPrincipalId string = func.identity.principalId
