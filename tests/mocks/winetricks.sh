# Фальшивый winetricks для тестов: журнал вызовов и проверка, что wine
# доступен в PATH (настоящий winetricks ищет его там же).
# MOCK_WINETRICKS_FAIL=<глагол> — этот глагол завершается с ошибкой.
command -v wine >/dev/null || {
  echo "mock winetricks: wine не найден в PATH" >&2
  exit 1
}
case "${1:-}" in
  --version)
    echo "20260125 (mock)"
    exit 0
    ;;
esac
{
  printf 'winetricks'
  printf ' [%s]' "$@"
  printf ' W_CACHE=%s WINE_BIN=%s\n' "${W_CACHE:-<unset>}" "${WINE_BIN:-<unset>}"
} >>"${MOCK_LOG:?MOCK_LOG не задан}"
for arg in "$@"; do
  if [ "$arg" = "${MOCK_WINETRICKS_FAIL:-}" ]; then
    exit 1
  fi
done
