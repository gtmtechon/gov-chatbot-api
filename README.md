# 정부 지침 조회 RAG 시스템 구축 전체 공정 가이드

이 문서는 PowerShell 스크립트를 기반으로 한 리소스 생성 및 RAG 파이프라인 구성의 전체 단계를 설명함.

---

## 1. 사전 준비 및 환경 변수 설정
본격적인 리소스 생성 전 필요한 도구를 설치하고 공통 변수를 정의함.

* **사전 준비사항**: Azure CLI 설치, Azure Functions Core Tools 설치, `ai` 확장 프로그램 추가 (`az extension add --name ai`).
* **주요 변수**: 리소스 그룹명(`rg-gov-chatbot`), 위치(`koreacentral`), 스토리지명, AOAI 리소스명, 인덱스명 등 정의함.

---

## 2. 단계별 리소스 생성 공정

### 1단계: 리소스 그룹 및 스토리지 생성
데이터 보관 및 시스템 관리를 위한 기초 인프라를 구축함.
* **리소스 그룹**: `az group create`를 통해 모든 자원을 묶을 그룹 생성함.
* **스토리지 계정**: LRS(Standard_LRS) 방식의 StorageV2 계정 생성함.
* **컨테이너**: PDF 원본 파일을 저장할 `handbook-data` 컨테이너 생성함.

### 2단계: Azure AI Foundry(Hub & Project) 구성
협업 및 모델 관리를 위한 AI 작업 영역을 설정함.
* **AI Hub 생성**: `az ml workspace create --kind "hub"`로 공유 설정 관리용 허브 구축함.
* **AI Project 생성**: 생성된 허브 ID를 참조하여 실제 작업을 수행할 프로젝트(`kind "project"`) 생성함.

### 3단계: Azure OpenAI 리소스 및 모델 배포
텍스트 임베딩과 채팅 응답을 위한 LLM 환경을 구축함.
* **AOAI 계정**: S0 SKU와 커스텀 도메인을 가진 OpenAI 리소스 생성함.
* **임베딩 모델**: `text-embedding-3-small` (버전 1) 모델 배포함.
* **채팅 모델**: `gpt-4o` (버전 2024-05-13) 모델 배포함.

### 4단계: Azure AI Search 및 연결 등록
검색 엔진을 생성하고 AI Foundry 프로젝트와 연결함.
* **검색 서비스**: Basic SKU의 AI Search 서비스 생성함.
* **연결(Connections)**: AOAI, Search, Storage 각각의 엔드포인트와 키를 사용하여 AI Project 내에 연결 정보를 등록함.

### 5단계: RAG 파이프라인(The Pipeline) 구성
데이터가 검색 가능하도록 처리하는 4단계 워크플로우를 설정함.
* **데이터 소스(Data Source)**: Blob Storage와 연결 설정을 정의함.
* **인덱스(Index)**: `chunk_id`, `content`, `content_vector`(1536차원) 등 검색 필드 스키마 생성함.
* **기술 세트(Skillset)**: PDF를 페이지 단위로 쪼개고(Chunking), AOAI를 통해 벡터로 변환하는 로직 정의함.
* **인덱서(Indexer)**: 위 3 요소를 결합하여 5분 간격으로 자동 실행되도록 설정함.

### 6단계: 데이터 업로드 및 인덱싱 트리거
* **PDF 업로드**: `az storage blob upload`를 통해 행정업무운영 편람 파일을 스토리지에 저장함.
* **인덱서 실행**: `reset` 및 `run` 명령을 통해 즉시 인덱싱을 시작함.

### 7단계: Azure Function App(백엔드) 인프라 구축
챗봇 로직이 구동될 서버리스 환경을 구성함.
* **App Service Plan**: Linux B1 SKU 기반 서비스 플랜 생성함.
* **Function App**: Python 3.11 런타임 환경으로 함수 앱 생성함.
* **환경 변수 설정**: 검색 및 AOAI의 키, 엔드포인트 정보를 App Settings에 일괄 등록함.

### 8단계: 소스 코드 배포 및 보안 설정
실제 실행 코드를 배포하고 권한을 관리함.
* **코드 배포**: GitHub 저장소 연동을 통해 소스 코드를 동기화함.
* **관리 ID(UAMI)**: User-assigned Managed Identity를 생성하여 보안 접속 환경 구축함.
* **권한 할당**: 생성된 ID에 함수 앱 제어 권한(Contributor) 부여함.
* **GitHub Actions 연동**: 페더레이션 자격 증명을 설정하여 CI/CD 자동화 완료함.

---

## 3. 최종 검증 절차
* **로그 모니터링**: Azure Portal 로그 스트림에서 텍스트 추출 및 인덱싱 성공 여부 확인함.
* **데이터 확인**: AI Search 인덱스 브라우저에서 벡터 데이터 생성 유무 확인함.