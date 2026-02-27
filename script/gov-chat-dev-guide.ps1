# ===================================================================================
# Azure RAG (Retrieval-Augmented Generation) Chatbot Deployment Script
# ===================================================================================
#
# 구성 순서 (Deployment Order):
# 1. 리소스 그룹 생성 (Create Resource Group)
# 2. 스토리지 계정/Blob 컨테이너 생성 (Create Storage Account & Blob Container)
# 3. Azure OpenAI 리소스 생성 및 모델 배포 (Create AOAI & Deploy Models)
# 4. Azure AI Search 리소스 생성 (Create Azure AI Search)
# 5. AI Search 파이프라인 설정: 데이터소스, 인덱스, 스킬셋, 인덱서 (Configure AI Search Pipeline)
# 6. 원본 문서 업로드 및 인덱싱 실행 (Upload Document & Trigger Indexing)
# 7. 응답용 Azure Function App 생성 및 배포 (Create & Deploy Chatbot Function App)
# 8. 채팅 웹페이지 배포 및 테스트 (Deploy & Test Chat Web UI)
#
# 사전 준비사항 (Prerequisites):
# - Azure CLI 설치: https://learn.microsoft.com/cli/azure/install-azure-cli
# - Azure Functions Core Tools 설치: https://learn.microsoft.com/azure/azure-functions/functions-run-local
# - Azure CLI 로그인 (`az login`) 및 대상 구독 선택 (`az account set --subscription "Your-Subscription-ID"`)
#
# ===================================================================================

# -----------------------------------------------------------------------------------
# Step 0: 스크립트 변수 설정 (Script Variable Configuration)
# -----------------------------------------------------------------------------------
Write-Host "Step 0: Configuring script variables..." -ForegroundColor Green

$VERSION = "v1d"
$LOCATION = "koreacentral"
$API_VERSION = "2024-07-01" # 안정적인 AI Search API 버전

# 리소스 이름 (Resource Names)
$RESOURCE_GROUP = "rg-gov-chatbot-$VERSION"
$STORAGE_NAME = "stgovhandbook$VERSION"
$CONTAINER_NAME = "handbook-data"
$AOAI_NAME = "aoai-gov-expert-$VERSION"
$SEARCH_NAME = "srch-gov-expert-$VERSION"
$FUNCTION_APP_NAME = "gov-chatbot-api-$VERSION"
$APP_SERVICE_PLAN_NAME = "gov-chatbot-plan" # App Service Plan 이름

# Azure AI Search 객체 이름 (AI Search Object Names)
$INDEX_NAME = "gov-handbook-index"
$DATASOURCE_NAME = "gov-handbook-datasource"
$SKILLSET_NAME = "gov-handbook-skillset"
$INDEXER_NAME = "gov-handbook-indexer"

# Azure OpenAI 모델 배포 이름 (AOAI Model Deployment Names)
$AOAI_MODEL_ID = "gpt-4o"
$EMBEDDING_MODEL_ID = "text-embedding-3-small"


# -----------------------------------------------------------------------------------
# Step 1: 리소스 그룹 생성 (Create Resource Group)
# -----------------------------------------------------------------------------------
Write-Host "Step 1: Creating Resource Group '$RESOURCE_GROUP'..." -ForegroundColor Green
az group create --name $RESOURCE_GROUP --location $LOCATION


# -----------------------------------------------------------------------------------
# Step 2: Azure Storage Account 및 Blob 컨테이너 생성 (Create Storage & Container)
# -----------------------------------------------------------------------------------
Write-Host "Step 2: Creating Storage Account '$STORAGE_NAME' and container '$CONTAINER_NAME'..." -ForegroundColor Green

# 스토리지 계정 생성
az storage account create --name $STORAGE_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --sku Standard_LRS `
    --kind StorageV2

# 스토리지 연결 문자열 가져오기 (후속 단계에서 사용)
$STORAGE_CONNECTION_STRING = az storage account show-connection-string --name $STORAGE_NAME --resource-group $RESOURCE_GROUP --query connectionString -o tsv

# Blob 컨테이너 생성 (문서 업로드용)
az storage container create `
    --name $CONTAINER_NAME `
    --account-name $STORAGE_NAME `
    --connection-string $STORAGE_CONNECTION_STRING


# 1. 변수 설정
$githubRawUrl = "https://raw.githubusercontent.com/gtmtechon/gov-chatbot-api/HEAD/data/administrative-work-op-manual.pdf"

$blobName = "administrative-work-op-manual.pdf" # 저장될 이름
$localTempPath = ".\tmp_administrative-work-op-manual.pdf"

# 2. GitHub에서 파일 다운로드
Invoke-WebRequest -Uri $githubRawUrl -OutFile $localTempPath

# 3. Storage Account Context 가져오기 (이미 로그인된 경우)
$storageAccount = Get-AzStorageAccount -ResourceGroupName "$RESOURCE_GROUP" -Name $STORAGE_NAME
$ctx = $storageAccount.Context

# 4. Blob Storage로 업로드
Set-AzStorageBlobContent -File $localTempPath `
                         -Container $CONTAINER_NAME `
                         -Blob $blobName `
                         -Context $ctx `
                         -Force

# 5. 로컬 임시 파일 정리
#Remove-Item $localTempPath

Write-Host "업로드 완료: $blobName" -ForegroundColor Green


# -----------------------------------------------------------------------------------
# Step 3: Azure OpenAI 리소스 생성 및 모델 배포 (Create AOAI & Deploy Models)
# -----------------------------------------------------------------------------------
Write-Host "Step 3: Creating AOAI service '$AOAI_NAME' and deploying models..." -ForegroundColor Green

# Azure OpenAI 서비스 생성
az cognitiveservices account create --name $AOAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --kind "OpenAI" `
    --sku S0 `
    --custom-domain $AOAI_NAME

# 임베딩 모델 배포 (text-embedding-3-small)
Write-Host "Deploying embedding model '$EMBEDDING_MODEL_ID'..." -ForegroundColor Cyan
az cognitiveservices account deployment create --name $AOAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --deployment-name $EMBEDDING_MODEL_ID `
    --model-name "text-embedding-3-small" `
    --model-version "1" `
    --model-format "OpenAI" `
    --sku-name "GlobalStandard" `
    --sku-capacity 120

# 채팅 모델 배포 (gpt-4o)
Write-Host "Deploying chat model '$AOAI_MODEL_ID'..." -ForegroundColor Cyan
az cognitiveservices account deployment create --name $AOAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --deployment-name $AOAI_MODEL_ID `
    --model-name "gpt-4o" `
    --model-version "2024-05-13" `
    --model-format "OpenAI" `
    --sku-capacity 10 `
    --sku-name "GlobalStandard"


# -----------------------------------------------------------------------------------
# Step 4: Azure AI Search 생성 (Create Azure AI Search)
# -----------------------------------------------------------------------------------
Write-Host "Step 4: Creating Azure AI Search service '$SEARCH_NAME'..." -ForegroundColor Green
az search service create --name $SEARCH_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --sku basic

# AI Search 및 AOAI의 키/엔드포인트 정보 가져오기 (후속 단계에서 사용)
$SEARCH_KEY = az search admin-key show --service-name $SEARCH_NAME -g $RESOURCE_GROUP --query primaryKey -o tsv
$SEARCH_ENDPOINT = "https://$($SEARCH_NAME).search.windows.net"
$AOAI_KEY = az cognitiveservices account keys list -n $AOAI_NAME -g $RESOURCE_GROUP --query key1 -o tsv
$AOAI_ENDPOINT = az cognitiveservices account show -n $AOAI_NAME -g $RESOURCE_GROUP --query properties.endpoint -o tsv


# -----------------------------------------------------------------------------------
# Step 5: AI Search 파이프라인 설정 (Configure AI Search Pipeline)
# -----------------------------------------------------------------------------------
Write-Host "Step 5: Configuring the AI Search pipeline (DataSource, Index, Skillset, Indexer)..." -ForegroundColor Green

# RAG 파이프라인 생성 순서: 1.DataSource -> 2.Index -> 3.Skillset -> 4.Indexer

# 5.1. 데이터 소스 (Data Source) 생성
Write-Host "  5.1. Creating DataSource '$DATASOURCE_NAME'..." -ForegroundColor Cyan
$headers = @(
    "Content-Type=application/json",
    "api-key=$SEARCH_KEY"
)


$datasourceBody = @"
{
    "name": "$DATASOURCE_NAME",
    "description": "Blob storage container for government handbook documents.",
    "type": "azureblob",
    "credentials": { "connectionString": "$STORAGE_CONNECTION_STRING" },
    "container": { "name": "$CONTAINER_NAME" }
}
"@

az rest --method put `
    --uri "$SEARCH_ENDPOINT/datasources/$DATASOURCE_NAME`?api-version=$API_VERSION" `
    --body $datasourceBody `
    --headers $headers

# 5.2. 인덱스 (Index) 생성
Write-Host "  5.2. Creating Index '$INDEX_NAME'..." -ForegroundColor Cyan
$indexBody = @"
{
  "name": "$INDEX_NAME",
  "fields": [
    { "name": "chunk_id", "type": "Edm.String", "key": true, "searchable": true, "filterable": true, "analyzer": "keyword" },
    { "name": "parent_id", "type": "Edm.String", "searchable": false, "filterable": true },
    { "name": "title", "type": "Edm.String", "searchable": true, "filterable": true },
    { "name": "content", "type": "Edm.String", "searchable": true, "filterable": false },
    { "name": "content_vector", "type": "Collection(Edm.Single)", "searchable": true, "dimensions": 1536, "vectorSearchProfile": "my-vector-profile" }
  ],
  "vectorSearch": {
    "algorithms": [ { "name": "my-hnsw", "kind": "hnsw" } ],
    "profiles": [ { "name": "my-vector-profile", "algorithm": "my-hnsw" } ]
  }
}
"@
az rest --method put `
    --uri "$SEARCH_ENDPOINT/indexes/$INDEX_NAME`?api-version=$API_VERSION" `
    --body $indexBody `
    --headers $headers

# 5.3. 기술 세트 (Skillset) 생성
Write-Host "  5.3. Creating Skillset '$SKILLSET_NAME'..." -ForegroundColor Cyan


$skillsetBody = @"
{
    "name": "$SKILLSET_NAME",
    "description": "Skills to parse PDFs, chunk text, and generate vector embeddings.",
    "skills": [
        {
            "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
            "name": "chunking-skill",
            "context": "/document/content",
            "defaultLanguageCode": "ko",
            "textSplitMode": "pages",
            "maximumPageLength": 1000,
            "pageOverlapLength": 100,
            "inputs": [ { "name": "text", "source": "/document/content" } ],
            "outputs": [ { "name": "textItems", "targetName": "chunks" } ]
        },
        {
            "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
            "name": "embedding-skill",
            "context": "/document/content/chunks/*",
            "resourceUri": "$AOAI_ENDPOINT",
            "apiKey": "$AOAI_KEY",
            "deploymentId": "$EMBEDDING_MODEL_ID",
            "modelName": "text-embedding-3-small",
            "inputs": [ { "name": "text", "source": "/document/content/chunks/*" } ],
            "outputs": [ { "name": "embedding", "targetName": "vector" } ]
        }
    ],
    "indexProjections": {
        "selectors": [
            {
                "targetIndexName": "$INDEX_NAME",
                "parentKeyFieldName": "parent_id",
                "sourceContext": "/document/content/chunks/*",
                "mappings": [
                    { "name": "content", "source": "/document/content/chunks/*" },
                    { "name": "content_vector", "source": "/document/content/chunks/*/vector" },
                    { "name": "title", "source": "/document/metadata_storage_name" }
                ]
            }
        ],
        "parameters": { "projectionMode": "skipIndexingParentDocuments" }
    }
}
"@

az rest --method put `
    --uri "$SEARCH_ENDPOINT/skillsets/$SKILLSET_NAME`?api-version=$API_VERSION" `
    --body $skillsetBody `
    --headers $headers


# 5.4. 인덱서 (Indexer) 생성
Write-Host "  5.4. Creating Indexer '$INDEXER_NAME'..." -ForegroundColor Cyan
$indexerBody = @"
{
    "name": "$INDEXER_NAME",
    "dataSourceName": "$DATASOURCE_NAME",
    "targetIndexName": "$INDEX_NAME",
    "skillsetName": "$SKILLSET_NAME",
    "schedule": { "interval": "PT2H" },
    "parameters": {
        "configuration": { "indexedFileNameExtensions": ".pdf", "parsingMode": "default" }
    }
}
"@
az rest --method put `
    --uri "$SEARCH_ENDPOINT/indexers/$INDEXER_NAME`?api-version=$API_VERSION" `
    --body $indexerBody `
    --headers $headers


# -----------------------------------------------------------------------------------
# Step 6: 문서 업로드 및 인덱싱 실행 (Upload Document & Run Indexing)
# -----------------------------------------------------------------------------------


# Write-Host "Step 6: Uploading PDF document and running the indexer..." -ForegroundColor Green


# 인덱서를 수동으로 즉시 실행
#Write-Host "Running the indexer '$INDEXER_NAME' now..." -ForegroundColor Cyan
#az rest --method post --uri "$SEARCH_ENDPOINT/indexers/$INDEXER_NAME/run`?api-version=$API_VERSION" --headers "api-key=$SEARCH_KEY"
#Write-Host "Indexer run command issued. Check the Azure Portal for progress."


# -----------------------------------------------------------------------------------
# Step 7: Azure Function App 생성 및 설정 (Create & Configure Function App)
# -----------------------------------------------------------------------------------
Write-Host "Step 7: Creating and configuring Function App '$FUNCTION_APP_NAME'..." -ForegroundColor Green

# App Service Plan 생성 (Consumption Plan 대신 Basic Plan 사용 예시)
az appservice plan create `
    --name $APP_SERVICE_PLAN_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --is-linux `
    --sku B1

# Function App 리소스 생성
az functionapp create `
    --name $FUNCTION_APP_NAME `
    --storage-account $STORAGE_NAME `
    --plan $APP_SERVICE_PLAN_NAME `
    --resource-group $RESOURCE_GROUP `
    --runtime "python" `
    --runtime-version "3.11" `
    --functions-version 4 `
    --os-type Linux

    

# 잠시 대기 후 환경 변수 설정
Start-Sleep -Seconds 15
Write-Host "Injecting environment variables into '$FUNCTION_APP_NAME'..." -ForegroundColor Cyan
az functionapp config appsettings set --name $FUNCTION_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings `
    "SEARCH_ENDPOINT=$SEARCH_ENDPOINT" `
    "SEARCH_KEY=$SEARCH_KEY" `
    "INDEX_NAME=$INDEX_NAME" `
    "AOAI_ENDPOINT=$AOAI_ENDPOINT" `
    "AOAI_KEY=$AOAI_KEY" `
    "AOAI_MODEL_ID=$AOAI_MODEL_ID" `
    "EMBEDDING_MODEL_ID=$EMBEDDING_MODEL_ID" `
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true" 


Write-Host "Function App created. Now, deploy your Python code from '../gov-chatbot-api/' folder." -ForegroundColor Yellow


# -----------------------------------------------------------------------------------
# Step 8: 코드 배포 (Deploy Code)
# -----------------------------------------------------------------------------------
# Write-Host "Step 8: Deploying function code to '$FUNCTION_APP_NAME'..." -ForegroundColor Green
# cd ../gov-chatbot-api
# func azure functionapp publish $FUNCTION_APP_NAME --python
# cd ../scripts
# Write-Host "Deployment complete."


# ===================================================================================
# 리소스 정리 (Cleanup)
# 아래 주석을 해제하고 실행하면 이 스크립트로 생성된 모든 리소스를 삭제합니다.
# ===================================================================================
# Write-Host "To delete all created resources, uncomment and run the following line:" -ForegroundColor Red
# az group delete --name $RESOURCE_GROUP --yes --no-wait
# az cognitiveservices account purge --name $AOAI_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

Write-Host "Script finished." -ForegroundColor Green
