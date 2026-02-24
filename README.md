# gov-chatbot-api
gov-chatbot-api-demo

* vsocde
func init ./ --worker-runtime python --model V2

func new --template "Http Trigger" --name MyHttpTrigger

func azure functionapp publish gov-chatbot-api --python


## azure function env 등록
# 1. 대상 리소스 이름 설정 (이 변수들만 정확하면 됨)
$RG_NAME = "your-resource-group"
$FUNCTION_APP_NAME = "gov-chatbot-api"
$SEARCH_NAME = "your-search-service-name"
$AOAI_NAME = "your-aoai-account-name"

Write-Host "Fetching resource information via AZ CLI..." -ForegroundColor Cyan

# 2. Azure AI Search 정보 추출
$SEARCH_ENDPOINT = "https://$($SEARCH_NAME).search.windows.net"
$SEARCH_KEY = az search admin-key show --service-name $SEARCH_NAME -g $RG_NAME --query primaryKey -o tsv

# 3. Azure OpenAI 정보 추출
$AOAI_ENDPOINT = az cognitiveservices account show -n $AOAI_NAME -g $RG_NAME --query properties.endpoint -o tsv
$AOAI_KEY = az cognitiveservices account keys list -n $AOAI_NAME -g $RG_NAME --query key1 -o tsv

# 4. 모델 배포 명칭 (이미 배포된 이름을 쿼리하거나 직접 지정)
# 배포 이름을 모르겠다면: az cognitiveservices account deployment list -n $AOAI_NAME -g $RG_NAME
$AOAI_MODEL_ID = "gpt-4o"
$EMBEDDING_MODEL_ID = "text-embedding-3-small"

# 5. Function App 환경 변수 일괄 등록
Write-Host "Injecting environment variables into $FUNCTION_APP_NAME..." -ForegroundColor Green

az functionapp config appsettings set --name $FUNCTION_APP_NAME `
    --resource-group $RG_NAME `
    --settings `
    "SEARCH_ENDPOINT=$SEARCH_ENDPOINT" `
    "SEARCH_KEY=$SEARCH_KEY" `
    "AOAI_ENDPOINT=$AOAI_ENDPOINT" `
    "AOAI_KEY=$AOAI_KEY" `
    "AOAI_MODEL_ID=$AOAI_MODEL_ID" `
    "EMBEDDING_MODEL_ID=$EMBEDDING_MODEL_ID"

# 6. 최종 등록 확인
az functionapp config appsettings list --name $FUNCTION_APP_NAME --resource-group $RG_NAME --output table