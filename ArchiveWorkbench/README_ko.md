# Mac Unzip

> **모든 압축 파일을 열어라. 압축을 당신의 의지대로.**
> 네이티브 Swift로 단련한, 현대 Mac을 위한 사이버펑크급 압축 해제 엔진.

[English](README.md) | [中文](README_zh.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [日本語](README_ja.md) | **[한국어](README_ko.md)**

---

**Mac Unzip**은 **Swift 6.2**와 **SwiftUI**로 처음부터 다시 설계된 네이티브 macOS 압축 유틸리티입니다. **Apple Silicon**에 최적화되어 ZIP, 7z, RAR, TAR, DMG, ISO 등 중요한 모든 형식의 압축을 열고, 만들고, 보호합니다. 당신이 신뢰하는 그 Mac 안에서 말이죠.

Electron도, 번들된 런타임도, 원격 측정도 없습니다. 오직 한 가지를 탁월하게 해내는 빠르고 집중된 도구일 뿐입니다.

## 주요 기능

### 지원 형식
- **열기:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO
- **만들기:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST
- **암호화:** ZIP 및 7z에 AES-256 보호 적용

### 워크플로
- **드래그 앤 드롭** — 창 어디에든 압축 파일을 놓으면 바로 풀거나 미리보기
- **Finder 동기화 확장** — 파일이나 폴더를 오른쪽 클릭으로 압축 또는 열기
- **앱 내 미리보기** — 이미지, PDF, 동영상, 텍스트, Markdown을 전체 압축 해제 없이 확인
- **다중 창 지원** — 여러 압축 파일을 동시에 처리
- **다크 / 라이트 모드** — 시스템 외형에 자동 연동

### 보안과 안정성
- **안전한 압축 해제** — zip-slip(경로 순회) 공격 방어
- **심볼릭 링크 거부**와 리소스 한도로 악성 압축 파일을 원천 차단
- **충돌 복구 저널** — 중단된 압축 해제는 손상되지 않고 이어서 진행
- **AES-256 암호화** — 민감한 ZIP·7z 자료를 안전하게 보호

## 스크린샷

![Mac Unzip](Assets/Logo.svg)

## 설치

### 요구 사항
- **macOS 26** 이상
- **Apple Silicon**(M 시리즈) Mac
- 소스 빌드를 위한 **Xcode 26**

### 소스에서 빌드

```bash
git clone https://github.com/smkzw/ArchiveWorkbench.git
cd ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

Xcode 26에서 **App** 스킴을 선택하고 대상 기기를 지정한 뒤 **⌘R**을 누르세요.

저장소 루트에는 빠른 체험을 위한 빌드된 `ArchiveWorkbench-1.0.dmg`도 함께 제공됩니다.

## 시스템 요구 사항

| 항목 | 최소 사양 |
| --- | --- |
| 운영 체제 | macOS 26 |
| 아키텍처 | Apple Silicon (arm64) |
| 빌드 도구 | Xcode 26, Swift 6.2 |
| 디스크 공간 | 앱 번들 약 150 MB |

## 라이선스

**개인 사용은 무료입니다.** 상업적·기업용 사용에는 유료 라이선스가 필요합니다.

- 개인, 교육, 비영리 오픈소스 용도 — 무료
- 기업, 프리랜서 수주 작업, 고객 업무, 수익 창출 용도 — [유료 라이선스 필요](LICENSE)

전체 약관은 [LICENSE](LICENSE) 파일을 참고하세요.

---

© 2026 smkzw. All rights reserved.
