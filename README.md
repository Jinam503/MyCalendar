# 내 캘린더 (MyCalendar)

아이폰용 캘린더 앱 + 홈 화면·잠금 화면 위젯. SwiftUI / WidgetKit, iOS 17 이상.

## 기능

**앱**
- 월요일 시작 달력 + 앞뒤 달 날짜(연하게), 달력 7 : 일정 3 비율
- 한국 공휴일·대체공휴일·선거일(빨간 날) 2020~2040, 주요 기념일 표시
- 화면 어디서든 좌우로 밀면 달 이동, 오늘 칸은 흰색
- 일정: 제목, 색, 할 일(기본)/시간 일정, 종료 시간 선택, 반복(일·주·월·년 + 종료일), 알림(기본 30분 전), 위치, URL, 메모, 이미지
- 아래 목록: 할 일 먼저, 그다음 시간 순 / 길게 눌러 삭제
- 검색 (제목·위치·메모·URL)

**구글 캘린더 연동**
1. 아이폰 설정 → 앱 → 캘린더 → 캘린더 계정 → 계정 추가 → Google 로그인, "캘린더" 켜기
2. 앱 오른쪽 위 캘린더 버튼 → "캘린더 접근 허용하기"
3. 보여줄 캘린더를 고르고, 새 일정 기본 저장 위치를 정할 수 있어요 (일정마다 편집 화면에서도 변경 가능)
- 구글 일정에는 이미지·앱 색상이 저장되지 않아요 (캘린더 색을 따라감)

**위젯**: 월간 달력(작게·중간·크게), 다가오는 일정(작게·중간), 잠금 화면(직사각형·한 줄·원형)

---|---|---|
| 월간 달력 | 작게 / 중간 / 크게 | 이번 달 달력 + 오늘 일정 (중간·크게는 날짜 누르면 그 날로 이동) |
| 다가오는 일정 | 작게 / 중간 | 오늘 날짜 + 곧 있을 일정 2~4개 |
| 다음 일정 (잠금 화면) | 직사각형 / 한 줄 / 원형 | 다음 일정, 오늘 일정 개수 |

위젯은 자정과 일정 시작·종료 시각에 자동으로 갱신되고, 앱에서 일정을 바꾸면 바로 반영됩니다.

---

## Mac 없이 아이폰에 설치하기

Mac이 없으니 **GitHub의 무료 Mac 서버로 빌드** → **Windows PC의 AltStore로 설치**하는 방식입니다.
무료 Apple ID로 가능하지만, **7일마다 갱신**이 필요합니다(아래 5번).

### 1. GitHub에 올리기
1. [github.com](https://github.com) 가입 후 오른쪽 위 **+ → New repository**
2. 이름 `MyCalendar`, **Public** 선택(Public이면 빌드 시간 무제한 무료. Private도 되지만 월 무료 Mac 빌드 시간이 짧음) → Create
3. "uploading an existing file" 링크 클릭 → 이 폴더 **안의 내용 전부**(`.github` 폴더 포함)를 끌어다 놓고 **Commit changes**
   - `.github/workflows/build.yml` 이 꼭 올라가야 합니다. 안 보이면 숨김 파일 표시를 켜세요.

### 2. 앱 빌드 (.ipa 만들기)
1. 저장소의 **Actions** 탭 → 처음이면 "I understand… enable" 클릭
2. 왼쪽 **Build iOS app** → **Run workflow** → 초록 버튼
3. 5~10분 뒤 초록 체크가 뜨면 클릭 → 맨 아래 **Artifacts**의 `MyCalendar-ipa` 다운로드 → 압축 풀면 `MyCalendar.ipa`
   - 빨간 X가 뜨면 로그 내용을 Claude에게 붙여 주세요.

### 3. PC에 AltServer, 아이폰에 AltStore 설치
AltStore 공식 안내(Windows): https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

요약:
1. PC에 **iTunes**와 **iCloud**를 Microsoft Store 버전이 아닌 **애플 웹사이트 버전**으로 설치
2. AltServer 설치 후 실행 (작업 표시줄 트레이에 아이콘)
3. 아이폰을 USB로 연결, iTunes에서 "이 컴퓨터 신뢰" + **Wi-Fi 동기화** 켜기
4. 트레이 AltServer 아이콘 → Install AltStore → 내 아이폰 → Apple ID 로그인
5. 아이폰 **설정 → 개인정보 보호 및 보안 → 개발자 모드** 켜고 재시동
6. **설정 → 일반 → VPN 및 기기 관리** → 내 Apple ID 신뢰

### 4. 앱 설치
1. `MyCalendar.ipa`를 아이폰으로 옮기기 (AirDrop 불가 시: 카카오톡 나에게 보내기 / iCloud Drive → "파일" 앱에 저장)
2. 아이폰에서 **AltStore** 열기 → **My Apps** → 왼쪽 위 **+** → `MyCalendar.ipa` 선택
3. 홈 화면에 **내 캘린더** 생성

**위젯 추가:** 홈 화면 빈 곳 길게 누르기 → 왼쪽 위 **+ (편집)** → "내 캘린더" 검색
**잠금 화면:** 잠금 화면 길게 누르기 → 사용자화 → 잠금 화면 → 위젯 영역 → "내 캘린더"

### 5. 7일마다 갱신 (무료 Apple ID 제한)
- PC에서 AltServer가 켜져 있고 아이폰과 **같은 Wi-Fi**면 AltStore가 백그라운드로 자동 갱신합니다.
- 수동: AltStore → My Apps → **Refresh All**
- 기간이 지나 앱이 안 열려도 **일정 데이터는 남아 있고**, Refresh 하면 다시 열립니다. (앱을 삭제하면 데이터도 지워져요.)
- 무료 계정은 사이드로딩 앱 3개까지(AltStore 포함)입니다.

### 문제 해결
- **위젯에 일정이 안 뜨고 "오늘 일정 없음"만 나옴** → 앱과 위젯 간 데이터 공유(App Group)가 안 된 경우입니다. AltStore 최신 버전으로 다시 설치해 보고, 그래도 안 되면 Claude에게 알려 주세요.
- **설치 시 "maximum number of apps" 오류** → 다른 사이드로딩 앱 정리, 또는 며칠 뒤 다시.
- AltStore 대신 **Sideloadly**로도 .ipa 설치가 가능합니다.

### 7일 갱신이 귀찮다면
- **Apple Developer Program (연 $99 / 약 13만 원)** 가입 시 1년간 유지, TestFlight 설치도 가능
- 클라우드 Mac 대여 서비스로 Xcode를 직접 써서 설치할 수도 있음

---

## 코드 구조
```
project.yml              XcodeGen 설정 (Xcode 프로젝트 생성)
.github/workflows/       GitHub Actions 빌드 스크립트
App/                     앱 화면 (달력, 일정 목록, 편집)
Widget/                  위젯 3종
Shared/                  일정 모델, 저장소 (앱·위젯 공용)
```
일정은 App Group 공유 폴더의 `events.json`에 저장됩니다.
