# Фальшивый wine для тестов (tests/default.nix). Это НЕ Wine: он
# эмулирует ровно то, что используют скрипты tflex17*, и записывает
# каждый вызов в журнал $MOCK_LOG, чтобы тест мог проверить порядок и
# аргументы. Проверки на нём не говорят ничего о работе T-FLEX CAD.
#
# Управление из теста:
#   MOCK_WINEBOOT_ARCH=win32  — wineboot создаёт 32-битный префикс;
#   MOCK_WINEBOOT_FAIL=1      — wineboot завершается с ошибкой;
#   MOCK_NO_PROGID=1          — тип TFLEX.Document не зарегистрирован;
#   в файле .msi/.exe строки MOCK-PRODUCT=<каталог в Program Files> и
#   MOCK-EXIT=<код> задают результат «установки».

log="${MOCK_LOG:?MOCK_LOG не задан}"
prefix="${WINEPREFIX:?WINEPREFIX не задан}"

{
  printf 'wine'
  printf ' [%s]' "$@"
  printf '\n'
} >>"$log"

# Z:\a\b → /a/b
to_unix() {
  local p=$1
  p="${p#[Zz]:}"
  printf '%s' "${p//\\//}"
}

# Эмуляция установки продукта: каталог Program Files/<продукт>/Program.
install_product() {
  local src=$1 product code
  product="$(sed -n 's/^MOCK-PRODUCT=//p' "$src" | head -n 1)"
  code="$(sed -n 's/^MOCK-EXIT=//p' "$src" | head -n 1)"
  if [ -n "$code" ] && [ "$code" != 0 ]; then
    exit $((code % 256))
  fi
  if [ -n "$product" ]; then
    mkdir -p "$prefix/drive_c/Program Files/$product/Program"
    printf 'MOCK-TFLEXCAD\n' >"$prefix/drive_c/Program Files/$product/Program/TFlexCad.exe"
    printf '\n[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\{MOCK-%s}] 1\n"DisplayName"="%s"\n"DisplayVersion"="17.0.0.0"\n' \
      "${#product}" "$product" >>"$prefix/system.reg"
    # Ключ продукта, который пишет установщик T-FLEX (по нему лаунчер
    # находит профиль пользователя).
    printf '\n[Software\\\\Top Systems\\\\T-FLEX CAD 3D 17\\\\Rus] 1\n' >>"$prefix/system.reg"
  fi
  exit 0
}

# Импорт .reg (ASCII): ключи — с удвоенными «\», как в system.reg Wine;
# 32-битный regedit пишет под Wow6432Node.
reg_import() {
  local view=$1 file=$2 line key
  [ -f "$file" ] || {
    echo "mock regedit: нет файла $file" >&2
    exit 1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "[HKEY_LOCAL_MACHINE\\"*"]")
        key="${line#\[HKEY_LOCAL_MACHINE\\}"
        key="${key%]}"
        if [ "$view" = 32 ]; then key="Software\\Wow6432Node\\${key#Software\\}"; fi
        printf '\n[%s] 1\n' "${key//\\/\\\\}" >>"$prefix/system.reg"
        ;;
      "[HKEY_CLASSES_ROOT\\"*"]")
        key="${line#\[HKEY_CLASSES_ROOT\\}"
        key="${key%]}"
        if [ "$view" = 32 ]; then key="Wow6432Node\\$key"; fi
        printf '\n[Software\\\\Classes\\\\%s] 1\n' "${key//\\/\\\\}" >>"$prefix/system.reg"
        ;;
      \"* | @=*) printf '%s\n' "$line" >>"$prefix/system.reg" ;;
    esac
  done <"$file"
  printf 'regedit-import view=%s file=%s\n' "$view" "${file##*/}" >>"$log"
}

case "${1:-}" in
  --version)
    echo "wine-11.19 (Staging) (mock)"
    ;;
  wineboot)
    printf 'wineboot env WINEARCH=%s WINEDLLOVERRIDES=%s\n' "${WINEARCH:-}" "${WINEDLLOVERRIDES:-}" >>"$log"
    [ "${MOCK_WINEBOOT_FAIL:-0}" != 1 ] || exit 1
    mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64" \
      "$prefix/drive_c/Program Files/Common Files" "$prefix/drive_c/Program Files (x86)/Common Files" \
      "$prefix/dosdevices"
    if [ ! -f "$prefix/system.reg" ]; then
      printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n\n#arch=%s\n' \
        "${MOCK_WINEBOOT_ARCH:-win64}" >"$prefix/system.reg"
    fi
    touch "$prefix/user.reg" "$prefix/userdef.reg"
    ;;
  winepath)
    case "${2:-}" in
      -w) printf 'Z:%s\n' "${3//\//\\}" ;;
      -u) to_unix "$3" ;;
      *) exit 1 ;;
    esac
    ;;
  msiexec)
    [ "${2:-}" = /i ] || exit 1
    install_product "$(to_unix "$3")"
    ;;
  regedit)
    [ "${2:-}" = /S ] || exit 1
    reg_import 64 "$(to_unix "$3")"
    ;;
  'C:\windows\syswow64\regedit.exe')
    [ "${2:-}" = /S ] || exit 1
    reg_import 32 "$(to_unix "$3")"
    ;;
  reg)
    printf '%s\n' "$*" >>"$prefix/user.reg"
    ;;
  start)
    [ "${MOCK_NO_PROGID:-0}" != 1 ] || exit 1
    ;;
  explorer | winecfg | uninstaller) ;;
  *)
    exe=$1
    case "$exe" in
      *[Tt][Ff]lex[Cc]ad.exe)
        archive=missing
        if [ -f "${LOCALE_ARCHIVE_2_27:-}" ] && [ "$LOCALE_ARCHIVE_2_27" = "${LOCALE_ARCHIVE:-}" ]; then archive=ok; fi
        printf 'run TFlexCad.exe PWD=%s MESA_GL=%s MESA_GLSL=%s COMPAT=%s CTYPE=%s ALL=%s ARCHIVE=%s\n' "$PWD" \
          "${MESA_GL_VERSION_OVERRIDE:-<unset>}" "${MESA_GLSL_VERSION_OVERRIDE:-<unset>}" "${force_compat_shaders:-<unset>}" "${LC_CTYPE:-<unset>}" "${LC_ALL:-<unset>}" "$archive" >>"$log"
        ;;
      /*.exe | /*.EXE)
        [ -f "$exe" ] || {
          echo "mock wine: нет файла $exe" >&2
          exit 1
        }
        install_product "$exe"
        ;;
    esac
    ;;
esac
