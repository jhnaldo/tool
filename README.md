# tool

자주 쓰는 간단한 도구 모음. 새 작업을 시작하기 전에 여기 이미 있는 도구가 있는지 먼저 확인한다.

## 도구 목록

| 도구 | 설명 |
| --- | --- |
| [`pptx2pdf.sh`](pptx2pdf.sh) | PowerPoint(.pptx)를 깨짐 없이 PDF로 변환 (내장 글꼴 복원, 치장용 배경 제거, 이미지 다운샘플) |

---

### pptx2pdf.sh

PowerPoint(.pptx)를 깨짐 없이 PDF로 변환한다.

1. pptx에 내장된 글꼴(Windows 전용 압축 EOT 형식)을 풀어서 임시 설치
2. 레이아웃/마스터에 깔린 치장용 배경 이미지(대형 사진, 반복 패턴) 제거
3. LibreOffice로 PDF 변환 (본문 이미지는 지정 dpi로 다운샘플)

```bash
./pptx2pdf.sh 발표자료.pptx [다른파일.pptx ...]
```

| 옵션 | 설명 |
| --- | --- |
| `-o DIR` | PDF 저장 폴더 (기본: 원본과 같은 폴더) |
| `-r DPI` | 본문 이미지 최대 해상도 (기본 150, 더 작게: 100) |
| `-q QUALITY` | JPEG 품질 1~100 (기본 70) |
| `--keep-decor` | 치장용 배경 이미지 지우지 않음 |
| `--keep-fonts` | 추출한 글꼴을 변환 후에도 설치된 채로 둠 (Mac PowerPoint에서도 원본이 제대로 보임) |
| `-h`, `--help` | 도움말 |

필요한 것 (최초 1회):

- LibreOffice: `brew install --cask libreoffice`
- Xcode Command Line Tools (python3, cc): `xcode-select --install`
- `eot2ttf`(내장 글꼴 해제 도구)는 처음 실행할 때 자동으로 받아서 `~/.local/share/pptx2pdf/bin`에 빌드됨

---

## 도구 추가 규칙

- 스크립트는 저장소 루트에 두고 실행 권한(`chmod +x`)을 준다.
- 파일 상단 주석에 설명·사용법·옵션·의존성을 적는다 (`-h`가 이 주석을 출력하도록).
- 추가하면 위 **도구 목록** 표와 상세 섹션을 함께 갱신한다.
