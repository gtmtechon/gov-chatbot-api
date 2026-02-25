import azure.functions as func
import logging
# 필수 라이브러리 Import 추가
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="chatv1")
def chatv1(req: func.HttpRequest) -> func.HttpResponse:

    logging.info('Processing RAG request with Function Key authentication.')

    query = req.params.get('query')
    if not query:
        return func.HttpResponse("Query parameter is missing.", status_code=400)
    
    
    try:
        # 1. 클라이언트 초기화
        search_client = SearchClient(
            os.environ["SEARCH_ENDPOINT"], 
            "gov-handbook-index", 
            AzureKeyCredential(os.environ["SEARCH_KEY"])
        )
        ai_client = AzureOpenAI(
            azure_endpoint=os.environ["AOAI_ENDPOINT"],
            api_key=os.environ["AOAI_KEY"],
            api_version="2024-02-15-preview"
        )

        # 2. 질문 임베딩 생성
        embedding_res = ai_client.embeddings.create(
            input=[query], 
            model="text-embedding-3-small"
        )
        embedding = embedding_res.data[0].embedding

        # 3. Azure AI Search 벡터 검색
        vector_query = VectorizedQuery(vector=embedding, k_nearest_neighbors=3, fields="content_vector")
        results = search_client.search(search_text=None, vector_queries=[vector_query], select=["title", "content"])
        
        context = "\n".join([r['content'] for r in results])

        # 4. GPT-4o 응답 생성 (RAG)
        messages = [
            {"role": "system", "content": "제공된 컨텍스트를 바탕으로 간결하게 답변함."},
            {"role": "user", "content": f"Context: {context}\n\nQuestion: {query}"}
        ]
        
        response = ai_client.chat.completions.create(
            model=os.environ.get("AOAI_MODEL_ID", "gpt-4o"), 
            messages=messages
        )
        
        # 5. 결과 반환 (func.HttpResponse 사용)
        return func.HttpResponse(response.choices[0].message.content, status_code=200)

    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(f"Internal Error: {str(e)}", status_code=500)