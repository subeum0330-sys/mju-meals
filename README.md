# 명지밥

명지대학교 학식을 확인하는 **비공식 iPhone 앱**입니다. 자연캠퍼스를 기본으로 열고 명진당·학생회관·생활관·교직원식당의 메뉴를 보여줍니다. SwiftUI / iOS 17 이상으로 만들었습니다.

현재 앱에는 **2026년 10월 5일~9일 인스타그램 식단 확인본 35개 항목**이 들어 있습니다. 네 식당의 원본 이미지와 대조했고, 메뉴와 공휴일 안내를 포함합니다. 확인 시각은 10월 9일 11:22(한국 시간)입니다.

현재는 **Codex가 매주 월요일 오전 9시(한국 시간)에 네 식당의 인스타그램을 열어 식단 사진을 확인하는 방식**입니다. 확인된 식단을 저장소에 반영하면 GitHub Pages에 게시되고 앱이 새 자료를 받아옵니다. Meta 개발자 등록이나 별도 API 키는 필요하지 않습니다. 예약은 이 프로젝트의 로컬 대화에 등록되어 있으므로 해당 시간에 Mac과 앱이 켜져 있고 브라우저·GitHub 연결을 사용할 수 있어야 합니다. 로그인 제한이나 미게시 때문에 확인하지 못한 자료는 추측하지 않습니다. [주간 확인과 게시 안내](docs/REVIEWED_UPDATES.md)를 참고하세요.

인스타그램 공식 API 수집 코드는 나중에 사용할 수 있도록 보관했습니다. 현재 방식에는 필요하지 않으며, [자동 수집 설정](docs/AUTOMATIC_UPDATES.md)은 선택 사항입니다.

## 사용 기능

- 식당·날짜 선택, 이전·다음 주 이동, 오늘로 돌아오기
- 출처에 게시된 메뉴·가격·운영시간·위치 확인
- 출처와 확인 또는 수집 시각 표시, 학교·인스타그램 원문 열기
- 당겨서 새로고침, 미게시와 연결 오류 구분, 과거 날짜 안내
- 캠퍼스·식당 선택 기억, 인문캠퍼스로 전환
- 다크 모드, VoiceOver 및 시스템 글자 크기 대응

식당과 주가 정확히 일치하는 데이터만 표시합니다. 미게시를 휴무로 추정하거나 과거 메뉴를 이번 주로 바꾸지 않습니다. 자동 수집한 식단은 이미지 인식 오류가 있을 수 있어 직접 검수한 확인본과 구분합니다. 앱 이용자 로그인, 광고, 분석 SDK는 없습니다.

## 아이폰에서 실행

1. Mac에 **Xcode 16 이상**을 설치합니다. Command Line Tools만으로는 iOS 앱을 빌드할 수 없습니다.
2. `MyongjiMeals.xcodeproj`를 Xcode로 엽니다.
3. 실제 iPhone은 케이블로 연결하고 **Signing & Capabilities → Team**에서 본인의 Apple 계정을 선택합니다. 필요하면 Bundle Identifier도 고유 값으로 변경합니다.
4. 실행 대상에서 연결한 iPhone(또는 iPhone 시뮬레이터)을 선택하고 **⌘R**을 누릅니다. 실제 기기에서는 개발자 모드를 켜야 하며, 첫 실행 시 본인 개발자 계정에 대한 신뢰 확인이 필요할 수 있습니다.

공유 실행 Scheme이 포함되어 있고 추가 패키지 다운로드는 필요하지 않습니다. App Store 또는 TestFlight 배포·서명은 아직 설정하지 않았습니다.

## 데이터 출처

| 자연캠퍼스 식당 | 10월 5일~9일 게시물 원문 | 확인 범위 |
| --- | --- | --- |
| 명진당 | [@mju_lounge](https://www.instagram.com/mju_lounge/p/DeIOnYUzFxS/) | B코너 백반 |
| 학생회관 | [@mjhs_yongin](https://www.instagram.com/mjhs_yongin/p/DeIIv_SzIMb/) | 조식·중식 |
| 생활관·복지동 | [@mj_bokji_foodist](https://www.instagram.com/mj_bokji_foodist/p/DeIjXAxDzEo/) | 중식·석식 |
| 교직원·방목관 | [@mj_bangmok_foodist](https://www.instagram.com/mj_bangmok_foodist/p/DeIg1_ukzE2/) | 중식·석식 |

앱은 연결된 공개 피드 → 앱에 포함된 확인본 → 학교 홈페이지 순으로 선택한 식당·주의 데이터를 찾습니다. 공개 피드 주소는 `https://subeum0330-sys.github.io/mju-meals/meals.json`입니다. 다음 주 확인본이 없고 학교 홈페이지에도 메뉴가 없으면 미게시로 표시합니다. 서버 주소 변경 후에는 앱을 한 번 다시 빌드해야 합니다.

10월 8일 조사 때 비어 있던 것은 **학교 홈페이지의 10월 5일~11일 식단**입니다. 초기 미리보기의 9월 10일 메뉴는 과거 학교 게시물이었으며 이번 주 메뉴가 아니었습니다. 위 인스타그램 식단은 별도로 확인해 추가한 데이터입니다. 상세한 출처와 처리 기준은 [데이터 출처](docs/DATA_SOURCE.md)를 참고하세요.

## 개발과 검증

```sh
# 네트워크 없이 식단 파서·날짜·출처·요청 처리 검사
swift test --disable-xctest

# 자연캠퍼스 학교 홈페이지를 직접 조회하는 선택 검사
MJU_LIVE_TEST=1 swift test --disable-xctest --filter LiveMealServiceTests

# 수집기 오프라인 검사
python3 -m unittest discover -s backend/tests -v

# Mac에서 같은 SwiftUI 화면 실행 (iOS 시뮬레이터가 아님)
swift run MyongjiMealsPreview

# SwiftUI 파일 추가 후 Xcode 프로젝트 갱신
python3 scripts/generate_xcode_project.py
```

Xcode 27.0에서 **iPhone용 Debug 빌드·개인 계정 서명·실제 iPhone 17 설치·실행**을 확인했습니다. 완성된 앱에 공개 식단 주소가 들어 있고, 실행 후 앱 프로세스가 유지되는 것도 확인했습니다. 시뮬레이터 실행과 기기에서의 상세 기능 검사는 별도입니다. 최신 결과는 [검증 기록](docs/VALIDATION.md)에 있습니다.

Command Line Tools만 설치된 Mac이나 동기화 폴더의 서명 오류 환경에서는 `bash scripts/check_local.sh`를 사용하세요. SDK와 임시 빌드 폴더를 설정합니다. 테스트에는 Swift 6 도구 체인의 Swift Testing을 사용합니다.

`output/명지밥 미리보기.app`은 같은 화면 코드를 실행하는 Mac 개발용 미리보기이며 iPhone 설치 파일이 아닙니다.

## 구조

| 경로 | 역할 |
| --- | --- |
| `Sources/MealCore` | 날짜·식당 모델, 학교 HTML 수신·파싱, 식단 확인본과 원격 피드 검증 |
| `Sources/MealCore/Resources/instagram-reviewed.json` | 원본 사진과 직접 대조한 주간 식단 확인본 |
| `Sources/MyongjiMealsApp` | SwiftUI 화면과 상태 관리 |
| `backend/publish_reviewed.py` | 키 없이 확인본을 검증하고 공개 식단 생성 |
| `.github/workflows/publish-reviewed-meals.yml` | 확인본이 바뀌면 GitHub Pages 배포 |
| `backend/collect.py`, `.github/workflows/update-meals.yml` | 선택 사항인 인스타 자동 수집, 기본 중단 |
| `App/MealFeedConfiguration.json` | 앱에 넣을 공개 피드 URL |
| `MyongjiMeals.xcodeproj` | iPhone 앱 실행용 프로젝트 |

홈 화면 위젯, 점심 전 알림, 선호 메뉴 알림은 현재 버전에 포함되지 않습니다.
