#!/usr/bin/env bash
# install-figlet-system-fonts.sh
# Pasang figlet dan salin koleksi font FIGlet terus ke /usr/share/figlet
# Direka untuk Debian 13 (apt). Jalankan sebagai root (sudo).
set -euo pipefail

FONT_ZIP_URL="https://github.com/xero/figlet-fonts/archive/refs/heads/master.zip"
DEST_DIR="/usr/share/figlet"
TMPDIR="$(mktemp -d /tmp/figlet-install-XXXX)"
TMPZIP="$TMPDIR/figlet-fonts.zip"
EXTRACT_DIR="$TMPDIR/extracted"
BACKUP_DIR="/usr/share/figlet.bak.$(date +%Y%m%d%H%M%S)"

echoinfo(){ printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
echook(){ printf '\e[1;32m[OK]\e[0m %s\n' "$*"; }
echoerr(){ printf '\e[1;31m[ERR]\e[0m %s\n' "$*" >&2; }

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echoerr "Sila jalankan skrip ini sebagai root (gunakan sudo)."
    exit 1
  fi
}

detect_apt() {
  if command -v apt-get >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

install_dependencies() {
  echoinfo "Memastikan pakej asas tersedia (figlet, wget, unzip)..."
  if detect_apt; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y figlet wget unzip ca-certificates || {
      echoerr "Gagal pasang pakej menggunakan apt."
      exit 1
    }
  else
    echoerr "Hanya disokong automatik untuk sistem ber-apt (Debian/Ubuntu). Sila pasang figlet, wget, unzip manual."
    exit 1
  fi
  echook "Pakej asas dipasang."
}

backup_dest() {
  if [[ -d "$DEST_DIR" ]]; then
    echoinfo "Membuat backup $DEST_DIR -> $BACKUP_DIR ..."
    cp -a "$DEST_DIR" "$BACKUP_DIR" || {
      echoerr "Gagal backup $DEST_DIR. Pastikan anda ada ruang disk dan kebenaran."
      exit 1
    }
    echook "Backup disimpan di $BACKUP_DIR"
  else
    echoinfo "$DEST_DIR tidak wujud — akan dibuat."
    mkdir -p "$DEST_DIR"
    chmod 755 "$DEST_DIR"
  fi
}

download_fonts() {
  echoinfo "Muat turun arkib font dari: $FONT_ZIP_URL"
  # cuba wget; jika gagal cuba curl
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMPZIP" --timeout=30 --tries=3 "$FONT_ZIP_URL" || {
      echoerr "Muat turun gagal dengan wget."
      exit 1
    }
  elif command -v curl >/dev/null 2>&1; then
    curl -sSL -o "$TMPZIP" "$FONT_ZIP_URL" || {
      echoerr "Muat turun gagal dengan curl."
      exit 1
    }
  else
    echoerr "Tiada wget atau curl ditemui; sila pasang salah satu."
    exit 1
  fi
  echook "Arkib dimuat turun ke $TMPZIP"
}

extract_fonts() {
  mkdir -p "$EXTRACT_DIR"
  echoinfo "Mengekstrak arkib..."
  unzip -qq "$TMPZIP" -d "$EXTRACT_DIR" || {
    echoerr "Gagal ekstrak arkib."
    exit 1
  }
  echook "Diekstrak ke $EXTRACT_DIR"
}

install_flfs() {
  echoinfo "Mencari dan menyalin semua .flf ke $DEST_DIR ..."
  shopt -s nullglob
  found=0
  # Cari semua .flf di dalam folder diekstrak dan salin
  while IFS= read -r -d '' f; do
    cp -f "$f" "$DEST_DIR/" || {
      echoerr "Gagal salin $f ke $DEST_DIR"
      exit 1
    }
    found=$((found+1))
  done < <(find "$EXTRACT_DIR" -type f -iname '*.flf' -print0)

  shopt -u nullglob

  if (( found == 0 )); then
    echoerr "Tiada fail .flf ditemui dalam arkib. Pastikan URL $FONT_ZIP_URL mempunyai font .flf."
    exit 1
  fi

  # tetapkan kebenaran
  chmod 644 "$DEST_DIR"/*.flf || true
  echook "Berjaya salin $found font ke $DEST_DIR"
}

final_check() {
  echoinfo "Menjalankan ujian ringkas figlet..."
  # paparkan contoh; tidak gagal keseluruhan jika figlet error
  if command -v figlet >/dev/null 2>&1; then
    # source environment not required, figlet baca dari /usr/share/figlet
    figlet "Mantap!" || echoinfo "contoh figlet gagal — tetapi font mungkin sudah dipasang."
  else
    echoerr "figlet tidak ditemui walaupun pemasangan sepatutnya berjaya."
    exit 1
  fi

  total=$(find "$DEST_DIR" -maxdepth 1 -type f -iname '*.flf' | wc -l)
  printf '\n\e[1;32m[Selesai]\e[0m Total .flf di %s: %d\n' "$DEST_DIR" "$total"
  printf 'Backup asal (jika ada) disimpan di: %s\n' "$BACKUP_DIR"
}

main() {
  require_root
  install_dependencies
  backup_dest
  download_fonts
  extract_fonts
  install_flfs
  final_check
}

main "$@"
