# Drizon 오픈소스 및 외부 의존성

README는 Drizon 소스를 MIT로 표기합니다. 저장소에는 아직 LICENSE 파일이 없습니다. 아래 목록은 Drizon이 직접 사용하는 프로젝트, 배포 방식, 콘텐츠 출처를 기록합니다. Dart 패키지 버전은 [pubspec.lock](../pubspec.lock)을 기준으로 합니다.

> **Android 배포 시 주의.** Android 빌드에 포함되는 NewPipe Extractor는 GPL-3.0입니다. 이 라이브러리를 포함해 Android 앱을 배포하면 해당 바이너리에 GPL-3.0의 조건이 적용됩니다. iOS 빌드에는 포함되지 않습니다.

## 앱에 들어가는 구성 요소

| 구성 요소 | 라이선스 | 쓰는 곳 |
| --- | --- | --- |
| [Flutter](https://github.com/flutter/flutter/blob/master/LICENSE) | BSD-3-Clause | 앱 프레임워크와 엔진. 포함 구성 요소의 고지는 Flutter의 `LicenseRegistry`가 모읍니다. |
| [just_audio](https://pub.dev/packages/just_audio) 0.9.46 | MIT | 재생 엔진. iOS는 AVPlayer, Android는 ExoPlayer를 씁니다. |
| [just_audio_background](https://pub.dev/packages/just_audio_background) 0.0.1-beta.17 및 [audio_service](https://pub.dev/packages/audio_service) | MIT | 백그라운드 재생과 잠금 화면 컨트롤. |
| [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) 3.0.5 | BSD-3-Clause | 플랫폼 추출기가 실패할 때 쓰는 Dart 스트림 추출. |
| [http](https://pub.dev/packages/http) 1.6.0 | BSD-3-Clause | YouTube Music · 벅스 · LRCLIB 요청과 다운로드. |
| [path_provider](https://pub.dev/packages/path_provider) 2.1.5 | BSD-3-Clause | 다운로드 폴더 위치. |
| [shared_preferences](https://pub.dev/packages/shared_preferences) 2.5.5 | BSD-3-Clause | 보관함 · 설정 · 매칭 결과 저장. |
| [provider](https://pub.dev/packages/provider) 6.1.5+1 | MIT | 상태 관리. |
| [cached_network_image](https://pub.dev/packages/cached_network_image) 3.4.1 | MIT | 커버 이미지 캐시. |
| [rxdart](https://pub.dev/packages/rxdart) 0.27.7 | Apache-2.0 | 스트림 유틸리티. |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) 1.0.9 | MIT | iOS 스타일 아이콘. |
| [NewPipe Extractor](https://github.com/TeamNewPipe/NewPipeExtractor) v0.26.1 | GPL-3.0 | **Android만.** YouTube 검색과 스트림 주소 추출. |
| [CPython](https://docs.python.org/3/license.html) 3.13 | PSF 라이선스 및 포함 구성 요소별 고지 | **iOS만.** [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support)(MIT)가 iOS용으로 빌드한 `Python.xcframework`를 앱에 넣습니다. OpenSSL 등 포함 라이브러리의 고지는 해당 배포본을 따릅니다. |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) | Unlicense | **iOS만.** 앱 안의 Python에서 라이브러리로 실행하는 스트림 추출기. 설정에서 PyPI의 새 버전으로 바꿀 수 있습니다. |
| [yt-dlp-ejs](https://pypi.org/project/yt-dlp-ejs/) | Unlicense, MIT, ISC | **iOS만.** yt-dlp의 JS 챌린지 해독 스크립트. 포함된 [meriyah](https://github.com/meriyah/meriyah)(ISC)와 [astring](https://github.com/davidbonnet/astring)(MIT)의 라이선스가 함께 적용됩니다. |
| [certifi](https://pypi.org/project/certifi/) | MPL-2.0 | **iOS만.** Python HTTPS용 루트 인증서 묶음. |

iOS의 JavaScriptCore, AVFoundation과 Android의 미디어 프레임워크는 운영체제가 제공하며 앱에 포함하지 않습니다.

## 빌드 도구

| 프로젝트 | 라이선스 | 도입 방식과 역할 |
| --- | --- | --- |
| [Xcode](https://developer.apple.com/xcode/) 및 [CocoaPods](https://github.com/CocoaPods/CocoaPods) | Apple 라이선스, MIT | iOS 빌드. CocoaPods와 함께 설치되는 [xcodeproj](https://github.com/CocoaPods/Xcodeproj)(MIT) gem으로 Runner 프로젝트를 패치합니다. |
| [pip](https://pip.pypa.io/) | MIT | `setup_python.sh`에서 yt-dlp 등 순수 Python 패키지를 앱 번들 폴더에 설치합니다. |
| [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons), [flutter_lints](https://pub.dev/packages/flutter_lints), [just_audio_platform_interface](https://pub.dev/packages/just_audio_platform_interface) | MIT, BSD-3-Clause, MIT | 개발 의존성. 아이콘 생성, 린트, 테스트용 가짜 오디오 플랫폼. |

## 웹 서비스와 콘텐츠 출처

| 출처 | Drizon에서의 역할 |
| --- | --- |
| YouTube Music | 검색, 추천어, 앨범 커버, 앨범명에 비공식 InnerTube 호출을 사용합니다. |
| YouTube | 재생과 다운로드에 쓰는 스트림 주소. 플랫폼 추출기가 조회합니다. |
| 벅스 | 가사 매칭용 곡 검색과 싱크·일반 가사, 커버 보조. 비공식 경로를 사용합니다. |
| [LRCLIB](https://lrclib.net/docs) | 벅스에 싱크 가사가 없을 때의 보조 가사 제공처. |
| PyPI | iOS에서 yt-dlp 업데이트를 받을 때 사용합니다. |

외부 서비스의 음원·가사·이미지에는 각 자료의 권리와 이용 조건이 적용됩니다. Drizon 소스의 라이선스는 이 콘텐츠의 이용 허락을 대신하지 않습니다. 비공식 경로는 서비스 쪽 변경으로 예고 없이 동작하지 않을 수 있습니다.
