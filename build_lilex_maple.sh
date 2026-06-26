#!/usr/bin/env bash
set -euo pipefail

# Local builder for Lilex + Maple Mono.
# It mirrors the original CI flow, but downloads prebuilt upstream release zips
# instead of cloning/building JetBrains/Maple from source.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$ROOT_DIR/.build/lilex-maple"
CACHE_DIR="$ROOT_DIR/.cache/font-zips"
OUTPUT_DIR="$ROOT_DIR/dist"

PROXY_PREFIX="https://gh-proxy.org/"
LILEX_VERSION="2.700"
MAPLE_VERSION="v7.9"
NERD=1
NO_LIGATURES=0
KEEP_WORK=0
OPTIMIZE=0
STYLE_FILTER="all"

FUSION_NAME="Lilex Maple Mono"
FUSION_ID="LilexMapleMono"
FUSION_DEVELOPER="devillove084"
FUSION_URL="https://github.com/devillove084/Fusion-JetBrainsMapleMono"
FUSION_COPYRIGHT="Copyright 2026 devillove084 ($FUSION_URL)"
FUSION_LICENSE="This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: https://openfontlicense.org"
LILEX_COPYRIGHT="Copyright 2019 The Lilex Project Authors (https://github.com/mishamyrt/Lilex)"
MAPLE_COPYRIGHT="Copyright 2022 The Maple Mono Project Authors (https://github.com/subframe7536/maple-font)"

usage() {
  cat <<'USAGE'
Usage: ./build_lilex_maple.sh [options]

Options:
  --output-dir DIR       Output directory. Default: dist
  --work-dir DIR         Work directory. Default: .build/lilex-maple
  --cache-dir DIR        Download cache directory. Default: .cache/font-zips
  --proxy PREFIX         Proxy prefix for GitHub download URLs. Default: https://gh-proxy.org/
  --no-proxy             Download from GitHub directly.
  --lilex-version VER    Lilex release tag. Default: 2.700
  --maple-version VER    Maple Mono release tag. Default: v7.9
  --nerd                 Use MapleMonoNormal-NF-CN.zip, adding Nerd Font glyphs. Default.
  --no-nerd              Use MapleMonoNormal-CN.zip, without Nerd Font glyphs.
  --no-ligatures         Strip contextual alternates/ligatures from fused fonts.
  --styles LIST          Comma-separated styles to build, or "all". Example: Regular,BoldItalic
  --optimize             Run the original CI-style FontForge optimization pass. Slow.
  --keep-work            Keep temporary work directory.
  -h, --help             Show this help.

Examples:
  ./build_lilex_maple.sh --styles Regular
  ./build_lilex_maple.sh --no-ligatures
  ./build_lilex_maple.sh --no-nerd --styles Regular,Bold,Italic,BoldItalic
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --cache-dir)
      CACHE_DIR="$2"
      shift 2
      ;;
    --proxy)
      PROXY_PREFIX="$2"
      shift 2
      ;;
    --no-proxy)
      PROXY_PREFIX=""
      shift
      ;;
    --lilex-version)
      LILEX_VERSION="$2"
      shift 2
      ;;
    --maple-version)
      MAPLE_VERSION="$2"
      shift 2
      ;;
    --nerd)
      NERD=1
      shift
      ;;
    --no-nerd)
      NERD=0
      shift
      ;;
    --no-ligatures)
      NO_LIGATURES=1
      shift
      ;;
    --styles)
      STYLE_FILTER="$2"
      shift 2
      ;;
    --optimize)
      OPTIMIZE=1
      shift
      ;;
    --keep-work)
      KEEP_WORK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd unzip
need_cmd zip
need_cmd fontforge
need_cmd ttx
need_cmd gftools
need_cmd python3

PYTHON_BIN="$(command -v python3)"
if [[ -x "$ROOT_DIR/.venv-tools/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/.venv-tools/bin/python"
elif /usr/bin/python3 -c 'import fontTools' >/dev/null 2>&1; then
  PYTHON_BIN="/usr/bin/python3"
fi

if ! "$PYTHON_BIN" -c 'import fontTools' >/dev/null 2>&1; then
  echo "Missing Python package: fontTools (checked with $PYTHON_BIN)" >&2
  exit 1
fi

FTCLI=""
if [[ -x "$ROOT_DIR/.venv-tools/bin/ftcli" ]]; then
  FTCLI="$ROOT_DIR/.venv-tools/bin/ftcli"
elif command -v ftcli >/dev/null 2>&1; then
  FTCLI="$(command -v ftcli)"
fi

if [[ -z "$FTCLI" ]]; then
  echo "Warning: ftcli was not found; monospace metadata fix will be skipped." >&2
fi

if [[ $NERD -eq 1 ]]; then
  MAPLE_PACKAGE="MapleMonoNormal-NF-CN"
  NERD_SUFFIX="NF"
else
  MAPLE_PACKAGE="MapleMonoNormal-CN"
  NERD_SUFFIX="XX"
fi

LIGA_SUFFIX="XX"
if [[ $NO_LIGATURES -eq 1 ]]; then
  LIGA_SUFFIX="NL"
fi

NARROW_SUFFIX="XX"
LILEX_VERSION_ID="${LILEX_VERSION//./}"
MAPLE_VERSION_ID="${MAPLE_VERSION#v}"
MAPLE_VERSION_ID="${MAPLE_VERSION_ID//./}"
FUSION_VERSION="1.${LILEX_VERSION_ID}.${MAPLE_VERSION_ID}"
FUSION_DESCRIPTION="The free and open-source font fused with Lilex & Maple Mono"
FUSION_COPYRIGHTS="$LILEX_COPYRIGHT
$MAPLE_COPYRIGHT
$FUSION_COPYRIGHT"

OUTPUT_HT="$OUTPUT_DIR/${FUSION_ID}-${NERD_SUFFIX}-${NARROW_SUFFIX}-${LIGA_SUFFIX}-HT"
OUTPUT_XX="$OUTPUT_DIR/${FUSION_ID}-${NERD_SUFFIX}-${NARROW_SUFFIX}-${LIGA_SUFFIX}-XX"

ALL_STYLES=(
  Thin ThinItalic
  ExtraLight ExtraLightItalic
  Light LightItalic
  Regular Italic
  Medium MediumItalic
  SemiBold SemiBoldItalic
  Bold BoldItalic
)

select_styles() {
  if [[ "$STYLE_FILTER" == "all" ]]; then
    printf '%s\n' "${ALL_STYLES[@]}"
    return
  fi

  local requested=()
  IFS=',' read -r -a requested <<< "$STYLE_FILTER"
  local style known
  for style in "${requested[@]}"; do
    style="${style//[[:space:]]/}"
    known=0
    for candidate in "${ALL_STYLES[@]}"; do
      if [[ "$candidate" == "$style" ]]; then
        known=1
        break
      fi
    done
    if [[ $known -ne 1 ]]; then
      echo "Unknown or unavailable Lilex style: $style" >&2
      echo "Available styles: ${ALL_STYLES[*]}" >&2
      exit 2
    fi
    printf '%s\n' "$style"
  done
}

proxy_url() {
  local url="$1"
  if [[ -n "$PROXY_PREFIX" ]]; then
    printf '%s%s\n' "$PROXY_PREFIX" "$url"
  else
    printf '%s\n' "$url"
  fi
}

valid_zip() {
  local archive="$1"
  [[ -s "$archive" ]] && unzip -tq "$archive" >/dev/null 2>&1
}

download() {
  local url="$1"
  local output="$2"
  local fallback="${3:-}"
  local actual_url

  if valid_zip "$output"; then
    echo "Using cached: $output"
    return
  fi

  if [[ -e "$output" ]]; then
    echo "Removing incomplete or invalid cache: $output"
    rm -f "$output"
  fi

  if [[ -n "$fallback" && -e "$fallback" ]]; then
    if valid_zip "$fallback"; then
      echo "Using existing local zip: $fallback -> $output"
      mkdir -p "$(dirname "$output")"
      cp "$fallback" "$output"
      return
    fi
    echo "Ignoring invalid local zip: $fallback"
  fi

  actual_url="$(proxy_url "$url")"
  echo "Downloading: $actual_url"
  mkdir -p "$(dirname "$output")"
  curl -fL --retry 3 --retry-delay 2 -o "$output" "$actual_url"

  if ! valid_zip "$output"; then
    rm -f "$output"
    echo "Downloaded file is not a valid zip: $output" >&2
    exit 1
  fi
}

remove_hints() {
  local input="$1"
  local output="$2"

  "$PYTHON_BIN" -m fontTools.subset "$input" \
    --output-file="$output" \
    --glyphs='*' \
    --layout-features='*' \
    --name-IDs='*' \
    --name-languages='*' \
    --name-legacy \
    --notdef-outline \
    --recommended-glyphs \
    --glyph-names \
    --symbol-cmap \
    --legacy-cmap \
    --retain-gids \
    --passthrough-tables \
    --no-prune-unicode-ranges \
    --no-prune-codepage-ranges \
    --no-recalc-average-width \
    --no-hinting
}

fix_monospace() {
  local font_path="$1"
  if [[ -n "$FTCLI" ]]; then
    "$FTCLI" fix monospace "$font_path" >/dev/null
  fi
}

update_nameids() {
  local font_path="$1"
  local unique_id="$2"
  local args=(
    update-nameids "$font_path"
    --uniqueid "$unique_id"
    --designer "$FUSION_DEVELOPER"
    --manufacturer "$FUSION_DEVELOPER"
    --trademark "$FUSION_NAME"
    --version "$FUSION_VERSION"
    --copyright "$FUSION_COPYRIGHTS"
    --license "$FUSION_LICENSE"
    --urlvendor "$FUSION_URL"
    --urldesigner "https://www.spacetimee.xyz"
    --urllicense "https://openfontlicense.org"
  )

  if gftools update-nameids --help 2>&1 | grep -q -- '--description'; then
    args+=(--description "$FUSION_DESCRIPTION")
  fi

  gftools "${args[@]}"
}

normalize_name_table() {
  local font_path="$1"
  local style="$2"
  local unique_id="$3"

  "$PYTHON_BIN" - "$font_path" "$style" "$unique_id" \
    "$FUSION_ID" "$FUSION_NAME" "$FUSION_VERSION" \
    "$FUSION_DESCRIPTION" "$FUSION_DEVELOPER" "$FUSION_COPYRIGHTS" \
    "$FUSION_LICENSE" "$FUSION_URL" <<'PY'
from fontTools.ttLib import TTFont
import sys

(
    font_path,
    style,
    unique_id,
    fusion_id,
    family_name,
    version,
    description,
    developer,
    copyrights,
    license_text,
    vendor_url,
) = sys.argv[1:]

designer_url = "https://www.spacetimee.xyz"
license_url = "https://openfontlicense.org"

weight_names = {
    "Thin": "Thin",
    "ExtraLight": "ExtraLight",
    "Light": "Light",
    "Regular": "Regular",
    "Medium": "Medium",
    "SemiBold": "SemiBold",
    "Bold": "Bold",
}
weight_classes = {
    "Thin": 100,
    "ExtraLight": 200,
    "Light": 300,
    "Regular": 400,
    "Medium": 500,
    "SemiBold": 600,
    "Bold": 700,
}

is_italic = style.endswith("Italic")
base_style = style[:-6] if is_italic else style
if base_style == "":
    base_style = "Regular"
weight_name = weight_names[base_style]
weight_class = weight_classes[base_style]

style_human = weight_name
if is_italic:
    style_human = "Italic" if weight_name == "Regular" else f"{weight_name} Italic"

# Name IDs 1/2 are legacy/RIBBI names. For non-RIBBI weights, put the weight
# in the legacy family and use Regular/Italic as the legacy subfamily.
if style in {"Regular", "Italic", "Bold", "BoldItalic"}:
    legacy_family = family_name
    legacy_subfamily = style_human
else:
    legacy_family = f"{family_name} {weight_name}"
    legacy_subfamily = "Italic" if is_italic else "Regular"

full_name = f"{family_name} {style_human}"
postscript_name = f"{fusion_id}-{style}"

font = TTFont(font_path)
name_table = font["name"]
managed_ids = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17}
name_table.names = [n for n in name_table.names if n.nameID not in managed_ids]

def set_name(name_id, value):
    # Windows Unicode + Macintosh Roman covers common Linux/macOS/Windows font selectors.
    name_table.setName(value, name_id, 3, 1, 0x409)
    name_table.setName(value, name_id, 1, 0, 0)

set_name(0, copyrights)
set_name(1, legacy_family)
set_name(2, legacy_subfamily)
set_name(3, unique_id)
set_name(4, full_name)
set_name(5, version)
set_name(6, postscript_name)
set_name(7, family_name)
set_name(8, developer)
set_name(9, developer)
set_name(10, description)
set_name(11, vendor_url)
set_name(12, designer_url)
set_name(13, license_text)
set_name(14, license_url)
set_name(16, family_name)
set_name(17, style_human)

if "OS/2" in font:
    os2 = font["OS/2"]
    os2.usWeightClass = weight_class
    fs = os2.fsSelection
    # Clear ITALIC, BOLD, REGULAR, OBLIQUE, then set the appropriate bits.
    for bit in (0, 5, 6, 9):
        fs &= ~(1 << bit)
    if is_italic:
        fs |= 1 << 0
    if weight_class >= 700:
        fs |= 1 << 5
    if style == "Regular":
        fs |= 1 << 6
    os2.fsSelection = fs

if "head" in font:
    head = font["head"]
    mac_style = head.macStyle
    mac_style &= ~0b11
    if weight_class >= 700:
        mac_style |= 1
    if is_italic:
        mac_style |= 2
    head.macStyle = mac_style

font.save(font_path)
PY
}

finalized_gftools_path() {
  local font_path="$1"
  if [[ -f "$font_path.fix" ]]; then
    printf '%s.fix\n' "$font_path"
  else
    printf '%s\n' "$font_path"
  fi
}

cleanup() {
  if [[ $KEEP_WORK -ne 1 ]]; then
    rm -rf "$WORK_DIR/tmp"
  fi
}
trap cleanup EXIT

mkdir -p "$WORK_DIR" "$CACHE_DIR"
rm -rf "$WORK_DIR/source-fonts" "$WORK_DIR/tmp" "$OUTPUT_HT" "$OUTPUT_XX"
mkdir -p "$WORK_DIR/source-fonts/lilex" "$WORK_DIR/source-fonts/maple" "$WORK_DIR/tmp" "$OUTPUT_HT" "$OUTPUT_XX"

LILEX_ZIP="$CACHE_DIR/Lilex-${LILEX_VERSION}.zip"
MAPLE_ZIP="$CACHE_DIR/${MAPLE_PACKAGE}-${MAPLE_VERSION}.zip"

download "https://github.com/mishamyrt/Lilex/releases/download/${LILEX_VERSION}/Lilex.zip" "$LILEX_ZIP" "/tmp/Lilex.zip"
download "https://github.com/subframe7536/maple-font/releases/download/${MAPLE_VERSION}/${MAPLE_PACKAGE}.zip" "$MAPLE_ZIP" "/tmp/${MAPLE_PACKAGE}.zip"

echo "Extracting fonts..."
unzip -oq "$LILEX_ZIP" -d "$WORK_DIR/source-fonts/lilex"
unzip -oq "$MAPLE_ZIP" -d "$WORK_DIR/source-fonts/maple"

cp "$ROOT_DIR/OFL.txt" "$OUTPUT_HT/LICENSE.txt"
cp "$ROOT_DIR/OFL.txt" "$OUTPUT_XX/LICENSE.txt"

mapfile -t STYLES < <(select_styles)

FUSE_SCRIPT="$ROOT_DIR/fuse_fonts_fast.ff"
if [[ $OPTIMIZE -eq 1 ]]; then
  FUSE_SCRIPT="$ROOT_DIR/fuse_fonts.ff"
fi

echo "Fusion name: $FUSION_NAME"
echo "Fusion version: $FUSION_VERSION"
echo "Styles: ${STYLES[*]}"
echo "FontForge script: $FUSE_SCRIPT"
echo "Python: $PYTHON_BIN"
echo "Output HT: $OUTPUT_HT"
echo "Output XX: $OUTPUT_XX"

for STYLE in "${STYLES[@]}"; do
  LILEX_FONT="$WORK_DIR/source-fonts/lilex/ttf/Lilex-${STYLE}.ttf"
  MAPLE_FONT="$WORK_DIR/source-fonts/maple/${MAPLE_PACKAGE}-${STYLE}.ttf"

  if [[ ! -f "$LILEX_FONT" ]]; then
    echo "Missing Lilex font: $LILEX_FONT" >&2
    exit 1
  fi
  if [[ ! -f "$MAPLE_FONT" ]]; then
    echo "Missing Maple font: $MAPLE_FONT" >&2
    exit 1
  fi

  echo "==> Fusing $STYLE"
  HT_TMP="$WORK_DIR/tmp/fused-${STYLE}-HT.ttf"
  XX_TMP="$WORK_DIR/tmp/fused-${STYLE}-XX.ttf"

  fontforge "$FUSE_SCRIPT" \
    "$MAPLE_FONT" \
    "$LILEX_FONT" \
    "${FUSION_ID}-${STYLE}" \
    "$FUSION_NAME" \
    "$FUSION_NAME $STYLE" \
    "$STYLE" \
    "$HT_TMP"

  if [[ $NO_LIGATURES -eq 1 ]]; then
    fontforge "$ROOT_DIR/strip_ligas.py" "$HT_TMP"
  fi

  ttx "$HT_TMP" >/dev/null
  sed -i 's|<xAvgCharWidth value=".*"/>|<xAvgCharWidth value="600"/>|' "${HT_TMP%.ttf}.ttx"
  sed -i 's|<ulCodePageRange1 value=".*"/>|<ulCodePageRange1 value="00100000 00010110 00000001 10011111"/>|' "${HT_TMP%.ttf}.ttx"
  ttx -o "$HT_TMP" "${HT_TMP%.ttf}.ttx" >/dev/null
  rm "${HT_TMP%.ttf}.ttx"

  gftools rename-font "$HT_TMP" "$FUSION_NAME" >/dev/null
  update_nameids "$HT_TMP" "${FUSION_ID}-${STYLE}-${FUSION_VERSION}" >/dev/null
  HT_FIXED="$(finalized_gftools_path "$HT_TMP")"
  normalize_name_table "$HT_FIXED" "$STYLE" "${FUSION_ID}-${STYLE}-${FUSION_VERSION}"

  remove_hints "$HT_FIXED" "$XX_TMP"
  normalize_name_table "$XX_TMP" "$STYLE" "${FUSION_ID}-${STYLE}-${FUSION_VERSION}"

  fix_monospace "$HT_FIXED"
  fix_monospace "$XX_TMP"

  mv "$HT_FIXED" "$OUTPUT_HT/${FUSION_ID}-${STYLE}.ttf"
  mv "$XX_TMP" "$OUTPUT_XX/${FUSION_ID}-${STYLE}.ttf"

  rm -f "$HT_TMP" "$HT_TMP.fix"
done

HT_ZIP="$OUTPUT_DIR/${FUSION_ID}-${NERD_SUFFIX}-${NARROW_SUFFIX}-${LIGA_SUFFIX}-HT.zip"
XX_ZIP="$OUTPUT_DIR/${FUSION_ID}-${NERD_SUFFIX}-${NARROW_SUFFIX}-${LIGA_SUFFIX}-XX.zip"
rm -f "$HT_ZIP" "$XX_ZIP"
zip -qr -j "$HT_ZIP" "$OUTPUT_HT"
zip -qr -j "$XX_ZIP" "$OUTPUT_XX"

echo "Done."
echo "Hinted zip:   $HT_ZIP"
echo "Unhinted zip: $XX_ZIP"
