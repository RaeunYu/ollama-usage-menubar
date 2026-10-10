# Ollama Usage (menubar)

Ollama Cloud 구독의 **크레딧 잔액을 macOS 메뉴바에서 실시간에 가깝게** 보여주는 개인용 앱. 메뉴바에는 잔여 %와 progress bar가 함께 표시되고, 드롭다운에서 잔여 크레딧·제공 크레딧·플랜 시작일·플랜 초기화를 확인할 수 있다.

> Ollama Cloud가 2026-08-31에 GPU-time 과금에서 **토큰 단가 기반 크레딧 풀**로 요금제를 전환한 뒤, "이번 달 크레딧이 얼마나 남았나"를 한눈에 보고 싶어 만든 도구다. 데이터 소스가 되는 `GET /api/balance`는 Ollama가 공식 문서화한 엔드포인트이고, 그 사실과 스키마는 `docs/research/ollama-cloud-balance-api.md`에 정리되어 있다.

## Language

### 사용량

**크레딧 (Credit)**:
Ollama Cloud가 플랜에 따라 부여하는 달러화 표기의 사용량 풀. 소비는 모델별 토큰 단가로 계산된다. "토큰 기반"이라 부르지 않는다 — 부여·소진의 단위는 크레딧(달러)이고 토큰은 계산식일 뿐이다.
_Avoid_: 토큰 잔액, balance

**제공 크레딧 (Allowance)**:
이번 주기에 부여된 크레딧 총액. Balance API의 `allowance_usd`에서 온다.
_Avoid_: Pool(설정 파일에서 오던 시절의 이름), quota, 총 크레딧

**잔여 비율 (Remaining Ratio)**:
잔여 크레딧 ÷ 제공 크레딧. 두 값 모두 서버에서 오고 앱은 나눗셈만 한다 — 표시의 1차 지표.
_Avoid_: 사용률, 퍼센트(표시할 때만)

**잔여 크레딧 (Remaining Credits)**:
포함 크레딧의 남은 금액. Balance API의 `included.balance_usd`를 그대로 쓴다.
_Avoid_: 잔액(추가 결제 잔액과 혼동), 사용 가능 크레딧

**추가 결제 잔액 (Purchased Balance)**:
따로 결제해 둔 추가 크레딧의 남은 금액(`purchased.balance_usd`). 만료되는 크레딧이다. 지금은 표시하지 않고 보관만 한다.

**플랜 시작일 (Plan Start)**:
현재 주기가 시작된 시각(`period.from`).
_Avoid_: 결제일

**플랜 초기화 (Plan Reset)**:
제공 크레딧이 다음 주기로 리셋되는 시각(`period.until`).
_Avoid_: 갱신 예정일(설정으로 계산하던 시절의 이름), 만료일

**소진 (Exhaustion)**:
잔여 크레딧이 0이 된 상태. 오류가 아니므로 통신 오류와 구분해 표시한다.

### 앱

**설정 파일 (Config File)**:
사용자가 직접 편집하는 JSON. 폴링 간격과 색상 단계처럼 API가 알려 주지 않는 값을 담는다. 각 속성에 한국어 설명 키를 함께 둔다. API 키는 절대 담지 않는다(키체인 전용).

**색상 단계 (Color Stage)**:
잔여 비율 구간마다 메뉴바 표시에 적용하는 색. 임계값과 hex 색상으로 정의하며 사용자가 설정 파일에서 바꿀 수 있다.

**폴링 (Polling)**:
일정 간격으로 잔액을 다시 조회하는 동작. 기본 60초(서비스 권장값), 드롭다운을 열면 즉시 1회 다시 조회.
