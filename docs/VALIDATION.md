# 검증 기록

최종 정리: 2026-10-11 (Asia/Seoul). 인스타 원본 대조 시각은 2026-10-09 11:22이며, 이를 새 검수 시각으로 바꾸지 않았습니다.

## 통과한 검사

- 2026-10-10 사진 확인본 게시 방식 추가: 자격 증명 없이 공개 JSON·상태·안내 페이지 생성, 기존 메뉴 날짜와 확인 시각 보존
- 확인본 게시 테스트 **10개**, 기존 수집기 테스트 **22개**, 합계 **32개** 통과. 계정·주차·중복·알 수 없는 필드·자동 기록·앱이 거부하는 명시적 URL 포트 거부, 용량 제한, 실패 시 기존 공개 파일 보존, HTML 이스케이프, 한국 시간 기준 주 경계를 검사합니다. 주차별 테스트는 고정 테스트 자료를 사용하여 실제 다음 주 식단 추가를 막지 않습니다.
- 2026-10-11 [GitHub Actions 확인본 게시 실행](https://github.com/subeum0330-sys/mju-meals/actions/runs/38102635938): 검사·파일 생성·Pages 설정·업로드·배포가 모두 성공했습니다. 실제 [공개 meals.json](https://subeum0330-sys.github.io/mju-meals/meals.json)이 검수 원본과 완전히 같고, 네 식당의 4개 주간 레코드·35개 식사 항목 및 기존 확인 시각을 그대로 제공하는 것을 확인했습니다.
- 공개 피드 URL을 앱 설정과 생성된 iOS 프로젝트, Mac 미리보기 번들에 반영했습니다. 이번 변경의 Mac 빌드와 Swift 오프라인 검사도 통과했습니다. 아이폰 설치·빌드는 별도 미검증입니다.
- SwiftUI 앱과 MealCore의 macOS 빌드
- Swift Testing 오프라인 테스트 **24개**: 학교 HTML·한국 날짜 처리 9개, 확인본과 출처 8개, 원격 피드 7개
- 학교 라이브 테스트 **1개**: 자연캠퍼스 네 식당에 실제 요청하여 식당·주·날짜 일치 확인. 인스타 사본으로 우회하지 않는 별도 학교 요청을 검사했습니다.
- Python 수집기 테스트 **22개**: 주차와 연말·연초, 인쇄된 요일, 계정/링크 검증, API 실패 시 보존, 중복 판독 생략, 오래된 게시물 건너뛰기, 판독 실패한 새 게시물의 보호, 최초 게시 조건, 보관 기간 및 앱의 2MiB 용량 제한
- 수집기 CLI를 가상 픽스처와 `--dry-run`으로 실행. 공개 파일을 생성하지 않고 1주 자료 변환 성공
- Xcode 프로젝트 및 Mac 미리보기 Info.plist 문법 검사, Python 스크립트 구문 검사, GitHub Actions YAML 파싱
- Mac 미리보기 실행: 실제 10월 5~9일 확인본 로딩, 10월 9일의 공휴일 안내, 인스타 원문 링크·식당별 출처·확인 시각 표시
- 미리보기 앱에 MealCore 데이터 번들을 포함하여 빌드 폴더 밖에서도 실제 확인본 로딩

Swift 기본 실행에서는 라이브 테스트 1개를 건너뜁니다. 위 학교 라이브 테스트는 별도로 활성화하여 통과했습니다. 원격 피드 단위 테스트는 URLProtocol 모의 응답을 사용합니다. 공개 서버의 실제 응답과 원본 대조는 위 Pages 배포 후 별도로 확인했습니다. Python 픽스처의 메뉴와 날짜는 가상 테스트 자료이며 게시하지 않습니다.

## 데이터 대조

사용자가 알려준 네 계정의 공개 2026년 10월 5~9일 주간 식단 이미지와 JSON **35개 식사 항목**을 대조했습니다. 명진당 B코너 중식, 학생회관 조식/중식, 생활관 중식/석식, 교직원 중식/석식이며 게시물 링크는 [출처 기록](DATA_SOURCE.md)에 보존했습니다. 학생회관 쌀국수 가격은 원본에 별도 명시되지 않아 덮밥 가격을 붙이지 않았습니다.

## 아직 검증하지 않은 부분

- **주간 브라우저 확인 예약의 첫 무인 실행**: 매주 월요일 오전 9시(한국 시간) 예약은 등록했지만 첫 실행 결과는 아직 없습니다. 실행 시 Mac·앱·브라우저·GitHub 연결과 사용 한도가 필요합니다.
- **실제 Instagram Business Discovery 조회 및 OpenAI 이미지 판독**: API 자격 증명과 사용할 모델이 제공되지 않았습니다. 네 계정의 공식 API 조회 가능 여부도 미확인입니다.
- **GitHub Actions 인스타 예약 수집**: 실제 자격 증명이 없어 가동 중이 아닙니다. 기본값은 사진 확인본 게시 방식이며, `MEAL_UPDATE_MODE=instagram`이 아니면 인스타 수집기는 실행되지 않습니다.
- **iOS 시뮬레이터와 실제 iPhone 빌드**: Xcode가 설치되어 있지 않습니다. 기기에서 글자 크기·VoiceOver·네트워크 중단 상황과 서명도 확인해야 합니다.
- **AI 판독의 실제 정확도**: 날짜·형식 검증을 통과해도 글자를 잘못 읽을 수 있습니다. 실제 메뉴 이미지로 API 시험 실행 후 원본을 대조해야 합니다.
- TestFlight/App Store 배포

현재 사용하는 방식은 [사진 확인본 업데이트](REVIEWED_UPDATES.md)입니다. 인스타 자동 수집의 시작 절차와 성공 기준은 [선택 사항인 자동 수집 설정](AUTOMATIC_UPDATES.md)을 참고하세요.

## 재현

```sh
bash scripts/check_local.sh
MJU_LIVE_TEST=1 bash scripts/check_local.sh --skip-build --filter LiveMealServiceTests
python3 -m unittest discover -s backend/tests -v
python3 -m backend.collect --fixture backend/tests/fixtures/weekly-posts.json --dry-run
python3 -m backend.publish_reviewed --output-dir _site
```

수집기는 Python 3.11 이상이며 이번 로컬 검증에는 제공된 Python 런타임을 사용했습니다. 외부 Python 패키지는 필요하지 않습니다.

Swift 환경은 Apple Swift 6.4 / Command Line Tools / macOS SDK 26.5입니다. `check_local.sh`에는 이 환경에서 필요한 SDK 선택, Swift Testing 매크로 경로, 로컬 캐시, 임시 빌드 폴더 설정이 포함되어 있습니다. 기본 SDK 27.0의 SwiftUI 매크로 플러그인 누락과 동기화 폴더의 번들 서명 오류를 피하기 위한 설정입니다. 앱의 HTTPS 인증서 검사를 완화하지 않습니다.

Mac 빌드나 Xcode 프로젝트 문법 검사는 iOS 빌드 성공을 의미하지 않습니다.
