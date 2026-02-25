
# 필수 라이브러리 Import 추가
# from azure.search.documents import SearchClient
# from azure.search.documents.models import VectorizedQuery
# from azure.core.credentials import AzureKeyCredential
# from openai import AzureOpenAI

import azure.functions as func
import logging

app = func.FunctionApp()

@app.function_name(name="HttpTrigger1")
@app.route(route="hello", auth_level=func.AuthLevel.ANONYMOUS)
def test_function(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    return func.HttpResponse(
        "This HTTP triggered function executed successfully.",
        status_code=200
        )