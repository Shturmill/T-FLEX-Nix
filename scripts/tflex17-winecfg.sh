# Настройка Wine в префиксе T-FLEX CAD 17: tflex17-winecfg [аргументы winecfg]

case "${1:-}" in
  -h | --help)
    printf '%s\n' "Использование: tflex17-winecfg [АРГУМЕНТЫ winecfg]" \
      "Открывает winecfg в префиксе T-FLEX CAD 17 (TFLEX_WINEPREFIX)."
    exit 0
    ;;
esac

tflex_init
state="$(tflex_prefix_state)"
[ "$state" = win64 ] ||
  tflex_die_gui "Wine-префикс «$PREFIX» не готов (состояние: $state). Сначала: tflex17-install … или tflex17-deps --prefix-only"
exec wine winecfg "$@"
