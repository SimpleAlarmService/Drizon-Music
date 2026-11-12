# Drizon

> YouTube 오디오를 스트리밍하는 개인용 뮤직 플레이어 (Flutter) — Apple Music 스타일 UI, **서버 없음**

<br>

## 주요 기능

| 기능 | 설명 |
|------|------|
| 💧 **Liquid Glass UI** | 떠 있는 유리 탭바 · 미니 플레이어, 스프링 누름 효과, 출렁이는 탭 선택, Hero 커버 전환, 움직이는 배경 |
| 💿 **로고** | 에이투지체 "Drizon Music"의 o가 LP판 — 재생 중엔 33⅓ RPM으로 회전 |
| 🎠 **커버플로우 보관함** | 좋아요 · 최근 재생 · 내 플레이리스트를 3D 커버플로우로 넘겨보기 |
| 🔍 **검색** | YouTube Music 사제 엔진(InnerTube) — 입력 중 추천어, 노래 · 뮤직비디오 구분, 앨범 정보 |
| 💿 **앨범 커버 매칭** | 영상도 YouTube Music의 같은 음원을 찾아 정사각형 앨범 커버로 표시 |
| 🎤 **실시간 가사** | 벅스 싱크 가사를 자동 매칭 (보조: LRCLIB). 현재 줄 강조 · 자동 스크롤 · 줄 눌러 이동 · 직접 고르기 |
| ▶️ **재생** | 스트리밍이 기본. 백그라운드 재생, 잠금 화면 컨트롤 |
| ⬇️ **선택 다운로드** | 원하는 곡만 받아 오프라인 재생. 커버 · 싱크 가사도 함께 저장 |
| 🎬 **비디오** | 뮤직비디오 · 음악방송 무대 · 직캠 · 라이브 검색과 재생, 360p~1080p 다운로드 (기기에서 영상+소리 합치기) |
| 🎧 **지금 재생 중** | 블러 배경, 일시정지 시 줄어드는 커버, 스크러버, 대기열(드래그 정렬 · 스와이프 삭제) |
| 🔀 **셔플 / 반복** | 셔플 (히스토리 기반 뒤로가기), 반복 없음 / 한 곡 / 전체 |
| 💾 **플레이리스트 · 좋아요** | 생성 · 이름 변경 · 삭제, 곡 추가 / 제거 |
| 💿 **세션 복원** | 앱 재시작 후 이전 큐 · 위치 자동 복원 |

<br>

## 구조

```
                    ┌───────────────────────── Flutter (Dart) ─────────────────────────┐
                    │  ui/  (Apple Music 스타일)   services/  (재생 · 보관함 · 설정)     │
                    └───────────────┬─────────────────────────────────────┬─────────────┘
                       MethodChannel "music.extractor"                    │ just_audio
              ┌─────────────────────┴───────────┐                         ▼
        Android                                 iOS                  AVPlayer / ExoPlayer
        NewPipe (Kotlin)          Swift ── 내장 CPython ── yt-dlp
                                       └── JavaScriptCore (JS 챌린지 해독)
```

- **서버가 없습니다.** 검색, 스트림 URL 추출, 커버·가사 조회가 전부 기기 안에서 일어납니다.
- 자세한 구조는 [기술 문서](docs/ARCHITECTURE.md), 라이선스와 콘텐츠 출처는 [오픈소스 문서](docs/OPEN_SOURCE.md)에 있습니다.
- iOS는 앱 안에 **CPython**을 내장하고 **yt-dlp**를 라이브러리로 호출합니다.
- iOS는 서브프로세스를 띄울 수 없어서 yt-dlp의 JS 런타임(deno/node 등)을 쓸 수 없습니다.
  대신 yt-dlp의 챌린지 공급자(`JsChallengeProvider`)를 구현해 **시스템 JavaScriptCore**로 해독합니다
  (`ios/PythonApp/app/drizon_jsc.py` ⇄ `ios/Runner/JSSolver.swift`).
- 실패하면 Dart 구현(`youtube_explode_dart`)으로 자동 대체됩니다 (설정에서 끌 수 있음).
- yt-dlp는 앱 **재설치 없이 업데이트**됩니다: 설정 → *yt-dlp 업데이트*가 PyPI에서 새 wheel을
  체크섬 검증 후 내려받고, 다음 실행부터 번들된 버전보다 우선해서 로드합니다.

```
lib/
├── main.dart                  # 진입점, Provider 트리
├── theme.dart                 # Apple Music 팔레트 (라이트/다크), 텍스트 스타일
├── models/                    # Track · Playlist · AppSettings
├── services/
│   ├── engines/               # YouTube Music 검색 · 벅스 · LRCLIB · 매칭 점수
│   ├── metadata_service.dart  # 곡별 앨범 커버 · 가사 매칭과 캐시
│   ├── download_service.dart  # 선택 다운로드 (10 MB Range 분할)
│   ├── music_service.dart     # 스트림 추출 (Android: NewPipe, iOS: yt-dlp, 공통 폴백: Dart)
│   ├── player_service.dart    # 큐 · 셔플 · 반복 · 재생 상태
│   ├── library_service.dart   # 좋아요 · 기록 · 플레이리스트 (변경 시 UI 갱신)
│   ├── storage_service.dart   # SharedPreferences 영속성
│   └── settings_service.dart
└── ui/
    ├── app_shell.dart         # 탭바 + 미니 플레이어
    ├── pages/                 # home · search · library · now_playing · settings
    └── widgets/               # cover_flow · artwork · track_row · mini_player · actions

ios/
├── Runner/
│   ├── PythonRuntime.swift    # CPython 부팅 · 호출 (GIL, 큰 스택 스레드)
│   ├── JSSolver.swift         # JavaScriptCore로 yt-dlp 챌린지 스크립트 실행
│   └── ExtractorChannel.swift # MethodChannel ⇄ Python
├── PythonApp/
│   ├── app/                   # drizon_extractor.py · drizon_jsc.py
│   ├── app_packages/          # yt-dlp 등 (setup 스크립트가 채움, git 제외)
│   └── tests/                 # 호스트에서 도는 Python 테스트
└── scripts/
    ├── setup_python.sh        # Python.xcframework 다운로드 + yt-dlp 설치 + 프로젝트 패치
    └── patch_xcodeproj.rb     # Runner.xcodeproj에 위 구성요소를 연결 (멱등)
```

<br>

## 시작하기

### 요구 사항

- Flutter `≥ 3.38` / Dart `≥ 3.10`
- iOS: **Mac + Xcode** (iOS 13+), `python3`, `ruby` (CocoaPods와 함께 설치된 `xcodeproj` gem)
- Android: Android SDK 21+

### iOS

```bash
git clone <repo> && cd Drizon-Music
flutter pub get
./ios/scripts/setup_python.sh      # 최초 1회 (Python.xcframework + yt-dlp 설치, 프로젝트 연결)
flutter run                        # 실기기 또는 시뮬레이터
```

`setup_python.sh`는 BeeWare [Python-Apple-support](https://github.com/beeware/Python-Apple-support)의
최신 3.13 iOS 빌드를 받습니다 (`PY_MINOR`, `SUPPORT_URL` 환경변수로 변경 가능).
yt-dlp를 번들 버전으로 올리고 싶을 때도 같은 스크립트를 다시 실행하면 됩니다.

> **첫 실행이 느릴 수 있습니다.** yt-dlp는 추출기 모듈이 수천 개라 첫 import에 몇 초가 걸리고,
> 이후에는 캐시된 바이트코드를 씁니다. 앱은 시작과 동시에 백그라운드에서 미리 로드합니다.

### TestFlight

Mac에서 Xcode에 개발자 팀(`WSH6T8F59M`)으로 로그인하고, App Store Connect에 번들 ID `com.oye.oye` 앱이 있으면:

```bash
./ios/scripts/testflight.sh
```

빌드 번호를 시각으로 자동 지정해 IPA를 만들고 App Store Connect에 올립니다. Xcode 로그인 대신 API 키를 쓰려면 `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`를 지정합니다.

### 앱 아이콘

아이콘은 앱의 LP · Liquid Glass 위젯으로 그립니다([AppIconArt](lib/ui/brand/app_icon_art.dart)). 바꾼 뒤에는:

```bash
DRIZON_RENDER_ICON=1 flutter test test/render_app_icon_test.dart
dart run flutter_launcher_icons
```

### Android

```bash
flutter pub get
flutter run

# 릴리즈 빌드
flutter build apk --release
```

`AndroidManifest.xml`에 `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 권한이 필요합니다.

<br>

## 테스트

```bash
flutter test                                   # 보관함 · 커버플로우 · 엔진 파서/매칭 · 다운로드 · 전체 화면
DRIZON_LIVE=1 flutter test test/live_engines_test.dart   # 실제 YouTube Music · 벅스 · LRCLIB 호출
DRIZON_SHOT_DIR=/tmp/shots flutter test       # 각 화면을 PNG로도 저장 (레이아웃 확인용)

python3 -m unittest discover -s ios/PythonApp/tests -v   # Python 레이어 (setup 후)
```

<br>

## 알려진 제한

- **App Store 배포는 어렵습니다.** YouTube 오디오를 추출해 재생하는 방식은 YouTube 약관과 충돌하므로
  개인용 사이드로드(Xcode 직접 설치)를 전제로 합니다. 무료 Apple ID는 7일마다 재서명이 필요합니다.
- YouTube Music · 벅스는 비공식 경로라 서비스 쪽 변경으로 검색 · 가사가 깨질 수 있습니다.
- Android 빌드는 GPL-3.0인 NewPipe Extractor를 포함합니다 ([오픈소스 문서](docs/OPEN_SOURCE.md) 참고).
- YouTube 측 변경으로 추출이 깨질 수 있습니다. iOS는 설정의 *yt-dlp 업데이트*로 대응합니다.
- 앱 프로세스 안의 JavaScriptCore는 JIT 없이 돌아서, 영상마다 첫 재생 시 챌린지 해독에 시간이 더 걸릴 수 있습니다.
- iOS 코드(Swift/Python 내장)는 Linux 개발 환경에서 작성되어 **실제 기기에서의 빌드 · 실행은 아직 검증되지 않았습니다.**
  Dart UI와 Python 레이어는 자동 테스트로 검증됩니다.

<br>

## 라이선스

MIT © 2025 Seonwoo
