# 서버 없이 자동 갱신 연결하기

**이 문서는 나중에 선택할 수 있는 인스타 자동 수집 방식입니다.** 현재는 [식단 사진을 확인해 등록하는 방식](REVIEWED_UPDATES.md)을 사용하므로 아래 Meta·OpenAI 계정 설정은 필요하지 않습니다. 공식 API 수집은 아직 실제 자격 증명으로 검증하지 않았습니다.

인스타 자동 수집을 다시 선택할 때만 이 문서를 따라가세요. 저장소 변수 `MEAL_UPDATE_MODE`를 `instagram`으로 설정해야 아래 작업이 실행됩니다. 이 값은 사진 확인본 게시 작업을 중단시키므로 계정 설정을 준비한 뒤 수동 검사 직전에 변경하세요. 확인본 게시 방식으로 돌아오려면 이 변수를 `reviewed`로 바꾸면 됩니다.

자동 수집 경로는 **식당 인스타그램 → 공식 Meta API → 이미지 판독 → GitHub Pages의 meals.json → iPhone 앱**입니다. 먼저 Meta API로 네 계정을 읽을 수 있는지 확인해야 합니다. 계정 이름만으로 자동 수집이 보장되지는 않습니다.

## 1. 필요한 계정 준비

| 준비물 | 용도 |
| --- | --- |
| GitHub 계정과 이 프로젝트를 올릴 저장소 | 예약 실행과 공개 식단 파일 제공 |
| Meta 개발자 앱 + 호출자 본인의 Instagram Professional 계정 + 연결된 Facebook Page | 다른 공개 Business/Creator 계정의 게시물 조회 |
| OpenAI API 프로젝트와 API 키 | 주간 식단 이미지 판독 |

GitHub Free의 공개 저장소에서 Pages를 사용할 수 있습니다. 비공개 저장소의 Pages 지원은 계정 요금제를 확인해야 합니다. [GitHub 공식 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

이 수집기는 API 키 방식으로 OpenAI를 호출합니다. API 결제와 사용 한도를 별도로 설정해야 하며, ChatGPT 앱에 로그인한 것만으로 이 수집기의 API 사용이 연결되지는 않습니다. 실제 비용은 선택한 모델과 이미지·출력량에 따라 달라집니다. [OpenAI API 시작 안내](https://developers.openai.com/api/docs/quickstart), [API 요금](https://developers.openai.com/api/docs/pricing)

## 2. Meta API 접근 준비

이번 코드는 **Instagram API with Facebook Login의 Business Discovery**를 사용합니다.

1. [Meta 개발자 사이트](https://developers.facebook.com/)에서 본인의 앱을 만들고 해당 Instagram API 구성을 설정합니다.
2. 호출에 사용할 본인의 Instagram 계정을 Professional(Business 또는 Creator) 계정으로 준비하고 Facebook Page에 연결합니다.
3. 앱에서 요구하는 권한과 접근 수준을 설정한 뒤 호출자 계정의 액세스 토큰과 **숫자 Instagram 사용자 ID**를 확보합니다. 운영 환경에 따라 앱 검수 등 추가 절차가 필요할 수 있습니다.
4. 아래 네 대상 계정의 Business Discovery 조회가 가능한지 확인합니다.

`mju_lounge`, `mjhs_yongin`, `mj_bangmok_foodist`, `mj_bokji_foodist`

대상은 공개 Business/Creator 계정이어야 합니다. 네 식당 각각의 운영자 로그인이 항상 필요한 방식은 아니지만, **각 계정의 실제 유형과 API 접근 가능 여부는 아직 확인하지 못했습니다.** 공개 웹 프로필이 보인다는 것과 API 조회 가능 여부는 다릅니다. 조회되지 않는 계정은 운영자에게 공식 데이터 제공 경로를 문의해야 합니다.

Meta 설정 화면·요구 권한은 앱 유형에 따라 달라지므로 [Meta 공식 Instagram API 컬렉션](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api)의 Facebook Login / Business Discovery 절차를 따라야 합니다. 상세한 [Business Discovery 문서](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/business-discovery/)도 참고하세요.

## 3. 저장소와 Pages 준비

1. 이 프로젝트 전체를 본인의 GitHub 저장소 기본 브랜치에 올립니다. `.github/workflows/update-meals.yml`도 포함되어야 합니다. API 키 파일은 올리지 않습니다.
2. 저장소 **Settings → Pages → Build and deployment → Source**에서 **GitHub Actions**를 선택합니다. [공식 설정 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
3. 공개 식단 주소를 정합니다. 일반적인 프로젝트 저장소라면 아래 형식입니다.

```text
https://OWNER.github.io/REPO/meals.json
```

`OWNER`와 `REPO`는 예시 자리표시자입니다. 각각 본인의 GitHub 계정명과 저장소명으로 바꾸세요. 실제 Pages 주소가 다르면 그 주소에 `/meals.json`을 붙입니다. 최초 게시 전 404는 정상이며 아래 최초 실행 옵션으로 처리합니다.

## 4. GitHub에 설정값 등록

저장소 **Settings → Secrets and variables → Actions**로 이동합니다. 비밀 값은 **Secrets → New repository secret**, 일반 설정은 **Variables → New repository variable**에 넣습니다. [GitHub Secrets 안내](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

| 위치 | 이름 | 넣을 값 |
| --- | --- | --- |
| Secrets | `INSTAGRAM_ACCESS_TOKEN` | 준비한 Meta 액세스 토큰 |
| Secrets | `INSTAGRAM_USER_ID` | 호출자 Professional 계정의 숫자 ID |
| Secrets | `OPENAI_API_KEY` | OpenAI API 프로젝트 키 |
| Variables | `IG_GRAPH_VERSION` | Meta 앱이 지원하는 버전, `v숫자.숫자` 형식 |
| Variables | `OPENAI_MODEL` | 이미지 입력과 Structured Outputs를 지원하며 본인 프로젝트에서 사용 가능한 모델 ID |
| Variables | `MEAL_FEED_URL` | 위에서 정한 공개 `meals.json` 주소 |
| Variables | `MEAL_UPDATE_MODE` | 자동 수집 검사 직전에 `instagram`으로 설정 |
| Variables | `MEAL_AUTOMATION_ENABLED` | 처음에는 `false` |

모델은 코드에 기본값을 넣지 않았습니다. 사용할 모델의 이미지 입력·구조화 출력 지원을 확인해 지정하세요. [이미지 입력](https://developers.openai.com/api/docs/guides/images-vision), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

토큰과 키는 GitHub Secrets에만 저장합니다. 앱·공개 JSON·채팅에는 넣지 않습니다.

## 5. 게시 없이 실제 연결 검사

1. 저장소 **Actions → Instagram collection (optional) → Run workflow**를 엽니다.
2. 기본 브랜치를 선택합니다.
3. **dry_run = true**, **bootstrap = true**로 실행합니다.
4. 실행 결과에서 네 계정의 실패 여부를 확인합니다. 실패했다면 로그의 계정과 실패 코드를 보고 권한·토큰·모델·날짜 인식 문제를 해결합니다.

`dry_run`은 공개 파일을 만들지 않지만 실제 API 조회와 이미지 판독을 수행하므로 API 비용은 발생할 수 있습니다. `bootstrap`은 아직 게시하지 않은 피드가 **HTTP 404일 때만** 앱에 포함된 검수 자료를 초기 데이터로 사용합니다. 다른 오류를 초기화로 덮어쓰지 않습니다.

## 6. 최초 게시 후 정기 실행 켜기

1. 검사가 성공하면 다시 **Run workflow**에서 **dry_run = false**, **bootstrap = true**로 실행합니다.
2. 배포가 끝나면 공개 `meals.json` 주소를 열어 JSON이 나오고, 같은 위치의 `status.json`에서 `hasFailures`가 `false`인지 확인합니다. 새 주의 메뉴와 날짜는 식당 원문과 대조하세요.
3. GitHub Variables의 `MEAL_AUTOMATION_ENABLED`를 **true**로 바꿉니다.
4. 이후 수동 실행은 **bootstrap = false**로 사용합니다. 게시를 원하면 `dry_run = false`, 검사만 하려면 `true`입니다.

기본 워크플로는 **매일 한국 시간 09:17·13:17·18:17**에 확인합니다. 주간 게시물이 늦게 올라오거나 수정되는 경우도 반영하기 위한 주기입니다. 이미지·캡션이 바뀌지 않으면 기존 판독 결과를 재사용합니다. 매주 바뀌는 메뉴를 앱 업데이트 없이 전달하지만 새 메뉴 게시 자체를 보장하지는 않습니다.

## 7. 앱에 공개 주소 연결

Mac 터미널에서 이 프로젝트 폴더로 이동한 뒤 다음 명령을 실행합니다. 예시 주소를 실제 배포 주소로 바꾸세요.

```sh
python3 scripts/configure_meal_feed.py 'https://OWNER.github.io/REPO/meals.json'
```

명령은 `App/MealFeedConfiguration.json`에 공개 URL을 저장하고 Xcode 프로젝트를 갱신합니다. **그다음 앱을 다시 빌드·설치해야 주소가 적용됩니다.** 이후 같은 주소의 메뉴 데이터가 바뀔 때마다 앱을 다시 배포할 필요는 없습니다. 앱에서 불러오거나 새로고침하면 공개 피드를 요청합니다.

앱 설정의 ‘연결 주소 설정됨’은 주소가 들어 있다는 뜻입니다. 실제 수집·배포 성공 여부는 Actions와 `status.json`을 확인해야 합니다. 현재 개발 환경에는 Xcode가 없어 iPhone 빌드·설치는 아직 검증하지 못했습니다.

연결을 해제하려면 `python3 scripts/configure_meal_feed.py --clear` 후 앱을 다시 빌드합니다. 예약 수집 자체를 중지하려면 GitHub의 `MEAL_AUTOMATION_ENABLED`를 `false`로 변경하세요.

## 운영 중 확인할 것

- 토큰 만료, Meta 권한·API 버전·대상 계정 유형 변경, API 결제 한도 때문에 수집이 멈출 수 있습니다. 실패한 토큰을 교체한 뒤 수동 검사부터 다시 실행합니다.
- 자동 판독은 사람이 검수한 결과가 아닙니다. 날짜 증거가 부족하거나 불확실하면 새 자료를 등록하지 않고 이전 유효 자료를 유지합니다. 지난주 자료를 이번 주로 이동하지 않습니다.
- 일부 식당만 실패하면 성공한 갱신과 이전 유효 자료를 게시하고 작업은 실패로 표시합니다. `status.json`과 작업 로그를 함께 확인하세요.
- GitHub 예약 실행은 지연·누락될 수 있고 공개 저장소가 **60일 동안 활동이 없으면 자동 중지**될 수 있습니다. 장기간 방치하지 말고 Actions 실행 이력을 확인해야 합니다. [GitHub 예약 실행 제한](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

데이터 검증과 지원 형식의 세부 제한은 [수집기 설명](../backend/README.md), 현재 출처는 [데이터 출처](DATA_SOURCE.md)를 참고하세요.
