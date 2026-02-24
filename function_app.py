import azure.functions as functions
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI
import os

app = functions.FunctionApp(http_auth_level=functions.AuthLevel.ANONYMOUS)

@app.route(route="ask")
def chat_request(req: functions.HttpRequest) -> functions.HttpResponse:
    query = req.params.get('query')
    
    # 1. 클라이언트 초기화
    search_client = SearchClient(os.environ["SEARCH_ENDPOINT"], "gov-handbook-index", AzureKeyCredential(os.environ["SEARCH_KEY"]))
    ai_client = AzureOpenAI(
        azure_endpoint=os.environ["AOAI_ENDPOINT"],
        api_key=os.environ["AOAI_KEY"],
        api_version="2024-02-15-preview"
    )

    # 2. 질문 임베딩 생성
    embedding = ai_client.embeddings.create(input=[query], model="text-embedding-3-small").data[0].embedding

    # 3. Azure AI Search 벡터 검색
    vector_query = VectorizedQuery(vector=embedding, k_nearest_neighbors=3, fields="content_vector")
    results = search_client.search(search_text=None, vector_queries=[vector_query], select=["title", "content"])
    
    context = "\n".join([r['content'] for r in results])

    # 4. GPT-4o 응답 생성 (RAG)
    messages = [
        {"role": "system", "content": f"다음 정보를 바탕으로 답변해줘: {context}"},
        {"role": "user", "content": query}
    ]
    
    response = ai_client.chat.completions.create(model="gpt-4o", messages=messages)
    
    return functions.HttpResponse(response.choices[0].message.content, status_code=200)