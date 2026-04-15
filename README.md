# Drizon

> YouTube 오디오를 스트리밍하는 개인용 뮤직 플레이어 앱 (Flutter)

<br>

## 주요 기능

| 기능 | 설명 |
|------|------|
| 🔍 **검색** | YouTube에서 실시간 트랙 검색 |
| ▶️ **재생** | 백그라운드 재생, 잠금 화면 컨트롤 지원 |
| 🔀 **셔플 / 반복** | 셔플 (히스토리 기반 뒤로가기), 반복 없음 / 한 곡 / 전체 |
| 📋 **큐 관리** | 추가, 제거, 드래그 재정렬 |
| 💾 **플레이리스트** | 생성 · 이름 변경 · 삭제, 곡 추가 / 제거 |
| ❤️ **좋아요** | 좋아요 표시 곡 보관 |
| 🕓 **재생 기록** | 최근 재생 50곡 자동 기록 |
| ⚙️ **설정** | 오디오 품질, 익스트랙터, 자동재생 등 |
| 💿 **세션 복원** | 앱 재시작 후 이전 큐 · 위치 자동 복원 |

<br>

## 기술 스택

```
Flutter 3  ·  Dart 3
just_audio + just_audio_background   — 오디오 엔진
youtube_explode_dart                 — YouTube 스트림 추출 (Dart)
NewPipe (MethodChannel)              — Android 네이티브 추출기 (1순위)
provider                             — 상태 관리
shared_preferences                   — 로컬 영속성
cached_network_image                 — 이미지 캐싱
Google Fonts (Epilogue · Manrope)    — 타이포그래피
```

<br>

## 아키텍처

```
lib/
├── main.dart                       # 앱 진입점, Provider 트리 초기화
│
├── models/
│   ├── track.dart                  # Track 데이터 모델
│   ├── playlist.dart               # Playlist 데이터 모델
│   └── settings_model.dart         # AppSettings (AudioQuality, ExtractorType …)
│
├── services/
│   ├── music_service.dart          # YouTube 검색 · 스트림 URL 추출
│   ├── player_service.dart         # 재생 상태 (ChangeNotifier) — 큐, 셔플, 반복
│   ├── storage_service.dart        # SharedPreferences 영속성
│   └── settings_service.dart       # 설정 관리 (ChangeNotifier)
│
├── screens/
│   ├── main_screen.dart            # 하단 내비게이션 + IndexedStack
│   ├── home_screen.dart            # 홈 (히어로 섹션, 트렌딩)
│   ├── search_screen.dart          # 검색
│   ├── library_screen.dart         # 보관함 (플레이리스트 / 좋아요 / 기록)
│   ├── playlist_detail_screen.dart # 플레이리스트 상세
│   ├── player_screen.dart          # 풀스크린 플레이어
│   └── settings_screen.dart        # 설정
│
└── widgets/
    ├── mini_player.dart            # 하단 미니 플레이어 바
    ├── track_tile.dart             # 트랙 목록 아이템 (옵션 시트 포함)
    ├── track_shelf.dart            # 가로 스크롤 트랙 캐러셀
    └── playlist_sheet.dart         # 플레이리스트 저장 바텀시트
```

<br>

## 스트림 추출 흐름

```
재생 요청
    │
    ▼
Android?
 ├─ Yes → NewPipe (MethodChannel)  ──실패──▶  youtube_explode_dart (fallback)
 └─ No  → youtube_explode_dart
                │
                ▼
         Audio Stream URL
                │
                ▼
        just_audio 재생
```

- 각 추출기는 **최대 2회 재시도** (1 s 백오프)
- 2회 모두 실패 시 자동으로 다음 곡으로 skip
- 설정에서 익스트랙터 / YouTube 클라이언트 타입 (ANDROID · WEB · TV) 변경 가능

<br>

## 설정 항목

| 카테고리 | 항목 |
|----------|------|
| 재생 | 자동 재생, 오디오 품질 (Low · Medium · High) |
| 네트워크 | Wi-Fi 전용, 데이터 절약 |
| 캐시 | 캐시 사용, 크기 (64 MB – 1 GB), 캐시 지우기 |
| 고급 *(개발자 모드)* | 익스트랙터 선택, YouTube 클라이언트 타입, Dart 폴백 |
| 디버그 | 고급 설정 표시, 전체 초기화 |

<br>

## 시작하기

### 요구 사항

- Flutter `≥ 3.x` / Dart `≥ 3.x`
- Android SDK 21+ 또는 iOS 14+

### 설치 및 실행

```bash
git clone https://github.com/your-username/drizon.git
cd drizon
flutter pub get
flutter run
```

### 릴리즈 빌드 (Android)

```bash
# APK
flutter build apk --release

# App Bundle
flutter build appbundle --release
```

<br>

## Android 권한

`AndroidManifest.xml`에 아래 권한이 필요합니다.

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

<br>

## 라이선스

MIT © 2025 Seonwoo
