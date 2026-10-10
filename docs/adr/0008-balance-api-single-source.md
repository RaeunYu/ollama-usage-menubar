# 데이터 소스를 Balance API 하나로 바꾸고 모델별 내역을 버린다

Ollama가 `/api/usage`를 기간별 사용 통계(`range=24h|7d|30d`, 요청 수·토큰·일자별 버킷)로 바꾸고 `GET /api/balance`를 새로 문서화하면서, 이 앱이 쓰던 `limits.monthly.usage`/`activity.period` 스키마는 공식 표면에서 사라졌다(두 엔드포인트 모두 이제 OpenAPI 스펙에 포함 — docs.ollama.com/api/balance.md, docs.ollama.com/api/cloud-usage.md). 이 앱의 목적은 "이번 주기 잔여 크레딧"이므로, 잔액을 직접 주는 `/api/balance`만 쓴다: 제공 크레딧 `allowance_usd`, 잔여 크레딧 `included.balance_usd`, 플랜 주기 `period.from`/`period.until`. `/api/usage`는 "이번 달 1일부터 오늘까지" 같은 임의 기간을 지정할 수 없어(24h·7d·30d뿐) 목적에 부적합하다. 모델별 요청 수는 어느 엔드포인트에도 없으므로 UI와 코드에서 제거했다 — 공식 문서의 "Coming soon"(모델·API 키별 내역)이 나오면 그때 다시 조사한다.

이 결정으로 앞선 ADR 세 건이 대체된다: **ADR-0001**(무문서 API 의존 — 이제 공식 문서·스펙이 있다), **ADR-0002**(서버 '사용 비율'을 단일 출처로 — 잔여 비율은 이제 `잔여 ÷ 제공`으로 두 서버 값에서 나온다), **ADR-0007**(설정 앵커로 갱신일 계산 — 플랜 초기화 시각은 `period.until`이 직접 준다). 설정 파일에서 `monthly_pool_usd`와 `billing_day_of_month`를 제거했다(폴링 간격·색상 단계만 남는다).

레이트 리밋도 이제 문서화됐다 — 사용자당 분당 10회, 분당 1회 폴링 권장. 이 앱의 기본 60초 폴링이 정확히 그 권장값이다.

**알려진 한계**: 공식 스펙의 `included`는 `oneOf`라 레거시 플랜은 `session`/`weekly`(`remaining_percent`, `resets_at`)만 주고 `balance_usd`·`allowance_usd`·`period`가 없다. 이 앱은 그 경우 값을 비우고 `—`로 표시한다(레거시 지원은 필요해지면 추가). 또한 Ollama 로컬 서버 v0.40.1+ 는 API 키 없이 같은 데이터를 중계하는 로컬 `/api/balance` 프록시를 제공한다 — 키 없는 경로가 필요해지면 그때 검토한다.
