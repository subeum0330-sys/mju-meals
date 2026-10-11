# 식단 게시와 선택 사항인 자동 수집

현재 기본 방식은 **사진 확인본 게시**입니다. `python3 -m backend.publish_reviewed --output-dir _site`는 API 키 없이 검수된 JSON을 검증하고 앱용 공개 파일을 만듭니다. 이 프로젝트 대화의 주 1회 예약이 브라우저에서 인스타 식단을 확인하고 검수 자료를 업데이트합니다. 이 프로그램 자체는 사진을 수집하거나 판독하지 않습니다. [사용 안내](../docs/REVIEWED_UPDATES.md)를 먼저 읽으세요.

아래는 현재 꺼져 있는 인스타 자동 수집기의 설명입니다. `MEAL_UPDATE_MODE=instagram`을 명시적으로 설정해야 GitHub에서 이 수집기가 실행됩니다.

`collect.py`는 매일 세 번 네 식당의 새 주간 식단과 수정 게시물을 확인하는 선택 사항인 GitHub Actions 수집기입니다. 별도 서버 프로세스나 데이터베이스가 필요하지 않습니다. **아직 실제 자격 증명으로 실행하지 않았습니다.** 식당의 공개 프로필을 브라우저에서 볼 수 있다는 사실만으로 공식 API 접근이 보장되지는 않습니다.

## 실행 흐름

1. `MEAL_FEED_URL`의 기존 공개 `meals.json`을 읽습니다.
2. Meta Instagram API with Facebook Login의 Business Discovery로 네 계정의 최근 25개 게시물을 조회합니다. 공개 Business/Creator 계정만 지원하며, 호출자의 연결된 Professional Instagram 계정·Facebook Page·유효한 권한/토큰이 필요합니다. 네 대상 계정의 실제 API 조회 가능 여부는 설정 후 확인해야 합니다.
3. 최근 28일의 이미지와 캡션을 확인합니다. 이미지 바이트와 캡션의 SHA-256이 기존 데이터와 같으면 유료 이미지 판독을 생략합니다.
4. 변경된 게시물만 OpenAI Responses API의 이미지 입력과 엄격한 JSON Schema로 판독합니다. `OPENAI_MODEL`은 이미지 입력·Structured Outputs를 지원하는 모델을 명시적으로 설정해야 합니다. `store: false`를 사용합니다.
5. 날짜·주차·계정·원문 링크·항목을 검사한 후 기존 피드와 병합하고 GitHub Pages에 `meals.json`을 게시합니다. 앱은 이 공개 URL만 사용합니다. 토큰과 이미지 원본은 게시하지 않습니다.

전체 설치 순서는 [자동 갱신 설정 안내](../docs/AUTOMATIC_UPDATES.md)를 참고하세요.

## GitHub 설정값

Repository → Settings → Secrets and variables → Actions에 추가합니다. 비밀 값을 앱 코드나 채팅에 붙여 넣지 마세요.

| 구분 | 이름 | 값 |
|---|---|---|
| Secret | `INSTAGRAM_ACCESS_TOKEN` | 해당 Meta 앱과 호출자 계정의 유효한 액세스 토큰 |
| Secret | `INSTAGRAM_USER_ID` | 호출자의 Instagram Professional 계정 숫자 ID |
| Secret | `OPENAI_API_KEY` | OpenAI API 프로젝트 키 |
| Variable | `IG_GRAPH_VERSION` | Meta 앱에서 현재 지원되는 버전, `v숫자.숫자` 형식 |
| Variable | `OPENAI_MODEL` | 사용할 이미지·Structured Outputs 지원 모델 ID |
| Variable | `MEAL_FEED_URL` | `https://계정.github.io/저장소/meals.json` |
| Variable | `MEAL_AUTOMATION_ENABLED` | 테스트 후 `true`로 설정하면 예약 실행 시작 |

Pages의 Source는 `GitHub Actions`로 설정합니다. `Instagram collection (optional)` 작업의 수동 실행은 기본적으로 **dry_run=true**이며 API 조회/판독만 수행합니다. 최초 실행에는 **bootstrap=true**도 선택해야 아직 없는 피드의 HTTP 404에 한해 검수한 초기 자료를 읽습니다. dry_run 성공 후 dry_run=false, bootstrap=true로 최초 게시하고, 이후 bootstrap=false로 사용합니다. 이미 게시된 피드에 문제가 생기면 임의로 초기 자료로 덮어쓰지 않습니다.

예약 시각은 한국 시간 09:17·13:17·18:17입니다. GitHub의 예약 작업은 지연되거나 건너뛸 수 있으며 정확한 시각을 보장하지 않습니다. 앱을 배포한 뒤에도 토큰 만료, Meta 권한/API 버전 변경, 계정 유형 변경, GitHub의 예약 실행 중지와 비용 한도를 관리해야 합니다.

## 검증 기준과 제한

- 게시물의 식당 계정과 링크를 고정된 네 계정에 대조합니다. 공식 API의 `/p/게시물ID/` 링크는 검증된 응답 계정을 붙인 정식 링크로 정규화합니다.
- 인쇄된 연도가 있으면 날짜와 일치해야 합니다. 연도가 없으면 **명시된 월/일과 요일**이 모두 필요합니다. 인증된 게시 시각 기준 7일 전부터 14일 후까지 유일하게 맞는 주차를 계산합니다. 실행일이나 모델의 연도 추측을 쓰지 않습니다. 연말·연초의 한 주는 두 연도를 처리합니다.
- 자동 기록은 `processingMethod: automatic`, `collectedAt`, `sourcePublishedAt`, `sourceDigest`, `temporalBasis`를 보존합니다. `verifiedAt`은 기존 앱 형식 호환용 수집 시각이며 사람이 검수했다는 뜻이 아닙니다.
- 날짜/요일 충돌, 흐린 글씨, 복수 주차, 불명확한 항목은 공개하지 않습니다. 빈 칸이나 법정 공휴일만으로 휴무를 만들지 않습니다. AI 판독의 사실 정확성을 완전히 보장하지는 못하므로 앱에는 원문 링크와 자동 판독 표시가 필요합니다.
- 이미지 판독이 실패하면 그 계정의 이전 유효 자료를 유지합니다. 식단표가 아닌 게시물은 건너뜁니다. 이전 주 메뉴를 이번 주로 바꾸지 않습니다.
- 일부 식당만 실패하면 성공한 갱신과 이전 유효 자료를 게시한 후 작업을 실패 상태로 표시합니다. `status.json`과 GitHub 작업 로그에서 실패 코드를 확인할 수 있습니다. 전체 피드 다운로드 실패나 형식 오류는 게시 자체를 중단합니다.
- 주간 식단은 게시 시각 7일 전~14일 후의 날짜만 신규 수집하며, 주간 수집 창은 실행 주 기준 지난 2주~다음 1주입니다. 이 창 밖의 판독된 과거/미래 식단은 실패 없이 건너뛰고, 미래 식단은 이후 다시 확인합니다. 최근 25개에 주간 메뉴가 없거나 월/일·요일 증거가 부족한 계정은 자동 등록되지 않습니다.
- 공개 피드는 최대 26주 전까지 보관하며 앱의 2MiB 응답 제한을 넘지 않도록 오래된 자료부터 줄입니다. 이번 주·다음 주 자료는 용량을 맞추려고 삭제하지 않고, 그래도 제한을 넘으면 게시를 중단합니다.
- 현재 구현은 이미지 게시물과 최대 10장 이미지 캐러셀을 지원합니다. 동영상만 있는 식단은 지원하지 않습니다. 네 계정 중 하나가 공식 Business Discovery로 조회되지 않으면 그 계정의 운영자와 공식 데이터 제공 경로를 협의해야 합니다.

## 로컬 확인

외부 패키지 없이 Python 3.11 이상을 사용합니다. 저장소 루트에서 실행하세요.

```sh
python3 -m unittest discover -s backend/tests -v
python3 -m backend.collect --fixture backend/tests/fixtures/weekly-posts.json --dry-run
```

픽스처는 가상 테스트 데이터입니다. `--fixture`는 `--dry-run` 없이는 실행되지 않으며 게시할 파일을 만들지 않습니다. 실제 API 테스트는 위 환경 변수들을 별도로 설정한 뒤 아래 명령을 실행합니다. 명령줄 인수로 키를 전달하지 않습니다.

```sh
python3 -m backend.collect --dry-run --bootstrap
```

## 공식 참고 자료

- [Meta Instagram API 공식 Postman 컬렉션](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api)
- [Meta Business Discovery](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/business-discovery/) — 이번 구현 검토 시 상세 페이지가 HTTP429를 반환하여 실제 API 응답 검증은 남아 있습니다.
- [OpenAI 이미지 입력](https://developers.openai.com/api/docs/guides/images-vision), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)
- [GitHub Pages 사용자 지정 워크플로](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
