# Любая команда Wine в префиксе T-FLEX CAD 17: tflex17-wine ПРОГРАММА [АРГУМЕНТЫ]
# Например: tflex17-wine regedit, tflex17-wine reg query 'HKCU\Software\Top Systems'.

case "${1:-}" in
  "" | -h | --help)
    printf '%s\n' "Использование: tflex17-wine ПРОГРАММА [АРГУМЕНТЫ]" \
      "Запускает wine с WINEPREFIX префикса T-FLEX CAD 17, например:" \
      "  tflex17-wine regedit" \
      "  tflex17-wine uninstaller"
    [ -n "${1:-}" ] || exit 2
    exit 0
    ;;
esac

tflex_init
state="$(tflex_prefix_state)"
[ "$state" = win64 ] ||
  tflex_die "Wine-префикс «$PREFIX» не готов (состояние: $state). Сначала: tflex17-install … или tflex17-deps --prefix-only"
# wineserver — не Windows-программа, его запускают напрямую
# (tflex17-wine wineserver -k завершает процессы Wine этого префикса).
if [ "$1" = wineserver ]; then
  shift
  exec wineserver "$@"
fi
exec wine "$@"
