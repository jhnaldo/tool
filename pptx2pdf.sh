#!/usr/bin/env bash
# pptx2pdf.sh — PowerPoint(.pptx)를 깨짐 없이 PDF로 변환
#
#  1) pptx에 내장된 글꼴(Windows 전용 압축 EOT 형식)을 풀어서 임시 설치
#  2) 레이아웃/마스터에 깔린 치장용 배경 이미지(대형 사진, 반복 패턴) 제거
#  3) LibreOffice로 PDF 변환 (본문 이미지는 지정 dpi로 다운샘플)
#
# 사용법:
#   pptx2pdf.sh 발표자료.pptx [다른파일.pptx ...]
#
# 옵션:
#   -o DIR          PDF 저장 폴더 (기본: 원본과 같은 폴더)
#   -r DPI          본문 이미지 최대 해상도 (기본 150, 더 작게: 100)
#   -q QUALITY      JPEG 품질 1~100 (기본 70)
#   --keep-decor    치장용 배경 이미지 지우지 않음
#   --keep-fonts    추출한 글꼴을 변환 후에도 설치된 채로 둠
#                   (그러면 Mac PowerPoint에서도 원본이 제대로 보임)
#   -h, --help      도움말
#
# 필요한 것 (최초 1회):
#   - LibreOffice : brew install --cask libreoffice
#   - Xcode Command Line Tools (python3, cc) : xcode-select --install
#   eot2ttf(내장 글꼴 해제 도구)는 처음 실행할 때 자동으로 받아서 빌드합니다.

{
set -euo pipefail

DPI=150
QUALITY=70
OUTDIR=""
KEEP_DECOR=0
KEEP_FONTS=0
FILES=()

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUTDIR="$2"; shift 2 ;;
    -r) DPI="$2"; shift 2 ;;
    -q) QUALITY="$2"; shift 2 ;;
    --keep-decor) KEEP_DECOR=1; shift ;;
    --keep-fonts) KEEP_FONTS=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; usage 1 ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[[ ${#FILES[@]} -eq 0 ]] && usage 1

TOOL_HOME="$HOME/.local/share/pptx2pdf"
mkdir -p "$TOOL_HOME/bin"

command -v python3 >/dev/null || { echo "python3가 없습니다: xcode-select --install" >&2; exit 1; }

SOFFICE="$(command -v soffice || true)"
[[ -z "$SOFFICE" && -x /Applications/LibreOffice.app/Contents/MacOS/soffice ]] \
  && SOFFICE=/Applications/LibreOffice.app/Contents/MacOS/soffice
[[ -z "$SOFFICE" ]] && { echo "LibreOffice가 없습니다: brew install --cask libreoffice" >&2; exit 1; }

EOT2TTF="$(command -v eot2ttf || true)"
[[ -z "$EOT2TTF" && -x "$TOOL_HOME/bin/eot2ttf" ]] && EOT2TTF="$TOOL_HOME/bin/eot2ttf"
if [[ -z "$EOT2TTF" ]]; then
  echo "▸ eot2ttf 빌드 중 (최초 1회)..."
  command -v cc >/dev/null || { echo "C 컴파일러가 없습니다: xcode-select --install" >&2; exit 1; }
  B="$(mktemp -d)"
  curl -fsSL https://codeload.github.com/umanwizard/libeot/tar.gz/refs/heads/master | tar xz -C "$B"
  ( cd "$B"/libeot-* && cc -O2 -w -std=gnu99 -DDECOMPRESS_ON -Iinc -Isrc \
      -o "$TOOL_HOME/bin/eot2ttf" src/eot2ttf.c src/libeot.c src/EOT.c src/writeFontFile.c \
      src/triplet_encodings.c src/ctf/*.c src/util/stream.c src/lzcomp/*.c )
  rm -rf "$B"
  EOT2TTF="$TOOL_HOME/bin/eot2ttf"
fi

if [[ "$(uname)" == "Darwin" ]]; then FONT_DIR="$HOME/Library/Fonts"; else FONT_DIR="$HOME/.fonts"; fi
mkdir -p "$FONT_DIR"

INSTALLED_LIST="$(mktemp)"
WORK_ROOT="$(mktemp -d)"
cleanup() {
  if [[ $KEEP_FONTS -eq 0 && -s "$INSTALLED_LIST" ]]; then
    while IFS= read -r f; do rm -f "$f"; done < "$INSTALLED_LIST"
    if command -v fc-cache >/dev/null; then fc-cache -f >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$WORK_ROOT" "$INSTALLED_LIST"
}
trap cleanup EXIT

prep() {
  python3 - "$1" "$2" "$EOT2TTF" "$FONT_DIR" "$INSTALLED_LIST" "$KEEP_DECOR" <<'PY'
import sys, zipfile, re, os, struct, subprocess, tempfile, posixpath, shutil
src, dst, eot2ttf, font_dir, installed_list, keep_decor = sys.argv[1:7]
keep_decor = keep_decor == "1"

SKIP = {"arial", "tahoma", "times new roman", "verdana", "georgia", "trebuchet ms",
        "courier new", "wingdings", "symbol", "webdings", "apple sd gothic neo"}

def font_names(path):
    d = open(path, "rb").read()
    n = struct.unpack(">H", d[4:6])[0]
    for i in range(n):
        tag, _, off, _ = struct.unpack(">4sIII", d[12 + 16*i: 28 + 16*i])
        if tag != b"name":
            continue
        _, cnt, so = struct.unpack(">HHH", d[off:off+6])
        out = {}
        for j in range(cnt):
            pid, eid, lid, nid, ln, o = struct.unpack(">6H", d[off+6+12*j: off+18+12*j])
            raw = d[off+so+o: off+so+o+ln]
            s = raw.decode("utf-16-be", "ignore") if pid in (0, 3) else raw.decode("latin-1")
            if nid not in out or (pid == 3 and lid == 0x409):
                out[nid] = s
        return out.get(1, ""), out.get(2, "Regular")
    return "", "Regular"

zin = zipfile.ZipFile(src)
files = {i.filename: zin.read(i.filename) for i in zin.infolist()}

installed = 0
tmpd = tempfile.mkdtemp()
for name in [n for n in files if n.startswith("ppt/fonts/") and n.endswith(".fntdata")]:
    eot = os.path.join(tmpd, "f.eot"); ttf = os.path.join(tmpd, "f.ttf")
    open(eot, "wb").write(files[name])
    if os.path.exists(ttf):
        os.remove(ttf)
    subprocess.run([eot2ttf, eot, ttf], capture_output=True)
    if not os.path.exists(ttf) or os.path.getsize(ttf) == 0:
        continue
    fam, sty = font_names(ttf)
    if not fam or fam.lower() in SKIP:
        continue
    safe = re.sub(r"[^\w.-]+", "_", f"{fam}-{sty}")
    target = os.path.join(font_dir, f"pptx2pdf_{safe}.ttf")
    if not os.path.exists(target):
        shutil.move(ttf, target)
        with open(installed_list, "a") as f:
            f.write(target + "\n")
        installed += 1
shutil.rmtree(tmpd, ignore_errors=True)
print(f"  · 내장 글꼴 {installed}개 설치")

if not keep_decor:
    removed = 0
    pres = files["ppt/presentation.xml"].decode("utf8")
    m = re.search(r'<p:sldSz cx="(\d+)" cy="(\d+)"', pres)
    slide_area = int(m.group(1)) * int(m.group(2)) if m else 12192000 * 6858000
    for part in [n for n in files if re.match(r"ppt/(slideMasters|slideLayouts)/[^/]+\.xml$", n)]:
        relp = posixpath.join(posixpath.dirname(part), "_rels", posixpath.basename(part) + ".rels")
        if relp not in files:
            continue
        target = {}
        for r in re.findall(r"<Relationship [^>]*>", files[relp].decode("utf8")):
            i = re.search(r'Id="([^"]+)"', r); t = re.search(r'Target="([^"]+)"', r)
            if i and t:
                target[i.group(1)] = posixpath.normpath(posixpath.join(posixpath.dirname(part), t.group(1)))
        x = files[part].decode("utf8")
        embeds = re.findall(r'<p:pic>.*?r:embed="([^"]+)".*?</p:pic>', x, re.S)
        kept = []
        def judge(mm):
            pic = mm.group(0)
            e = re.search(r'r:embed="([^"]+)"', pic)
            if not e:
                return pic
            rid = e.group(1)
            size = len(files.get(target.get(rid, ""), b""))
            ext = re.search(r'<a:ext cx="(\d+)" cy="(\d+)"', pic)
            area = int(ext.group(1)) * int(ext.group(2)) if ext else 0
            if size >= 700_000 or area >= 0.30 * slide_area or embeds.count(rid) >= 2:
                kept.append(1)
                return ""
            return pic
        nx = re.sub(r"<p:pic>.*?</p:pic>", judge, x, flags=re.S)
        removed += len(kept)
        nx, nb = re.subn(r"(<p:bgPr>)<a:blipFill.*?</a:blipFill>",
                         r'\1<a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>', nx, flags=re.S)
        removed += nb
        files[part] = nx.encode("utf8")
    print(f"  · 치장용 이미지 {removed}개 제거")

order = ["[Content_Types].xml"] + [n for n in files if n != "[Content_Types].xml"]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for n in order:
        if n in files:
            z.writestr(n, files[n])
PY
}

FILTER='pdf:impress_pdf_Export:{"ReduceImageResolution":{"type":"boolean","value":"true"},"MaxImageResolution":{"type":"long","value":"'"$DPI"'"},"Quality":{"type":"long","value":"'"$QUALITY"'"},"UseLosslessCompression":{"type":"boolean","value":"false"}}'

for IN in "${FILES[@]}"; do
  [[ -f "$IN" ]] || { echo "파일 없음: $IN" >&2; continue; }
  BASE="$(basename "$IN")"; STEM="${BASE%.*}"
  DEST="${OUTDIR:-$(cd "$(dirname "$IN")" && pwd)}"
  mkdir -p "$DEST"
  W="$(mktemp -d "$WORK_ROOT/job.XXXX")"
  echo "▸ $BASE"
  prep "$IN" "$W/in.pptx"
  if command -v fc-cache >/dev/null; then fc-cache -f >/dev/null 2>&1 || true; else sleep 2; fi
  "$SOFFICE" "-env:UserInstallation=file://$W/profile" --headless \
    --convert-to "$FILTER" --outdir "$W" "$W/in.pptx" >"$W/log.txt" 2>&1 || true
  if [[ -f "$W/in.pdf" ]]; then
    mv -f "$W/in.pdf" "$DEST/$STEM.pdf"
    echo "  ✓ $DEST/$STEM.pdf ($(du -h "$DEST/$STEM.pdf" | cut -f1 | tr -d ' '))"
  else
    echo "  ✗ 변환 실패: $BASE" >&2
    sed 's/^/    /' "$W/log.txt" >&2
  fi
done
exit 0
}
