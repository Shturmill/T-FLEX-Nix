# Диагностика окружения T-FLEX CAD 17: tflex17-doctor
#
# Только чтение: ничего не создаёт и не меняет, Wine в префиксе не
# запускает (иначе Wine мог бы обновить префикс). Код выхода 1 — найдены
# ошибки, 0 — ошибок нет (предупреждения не считаются).

case "${1:-}" in
  -h | --help)
    printf '%s\n' "Использование: tflex17-doctor" \
      "Проверяет Wine, префикс, установленный T-FLEX CAD, графику и службу лицензий."
    exit 0
    ;;
esac

errors=0
ok() { printf '  [ OK ] %s\n' "$*"; }
note() { printf '  [ -- ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
fail() {
  printf '  [FAIL] %s\n' "$*"
  errors=$((errors + 1))
}
section() { printf '\n%s\n' "$*"; }

tflex_init

printf 'T-FLEX-Nix %s — диагностика\n' "$TFLEX_NIX_VERSION"

section "Wine"
wine_version=""
if wine_version="$(wine --version 2>/dev/null)"; then
  ok "Wine: $wine_version ($TFLEX_WINE_PACKAGE)"
else
  fail "wine --version не работает ($TFLEX_WINE_PACKAGE)"
fi
# В Wine 11.7–11.13 переписанный msxml3 возвращает из setNamedItem NULL,
# и ToolkitPro в T-FLEX CAD падает при запуске (пустое окно и предложение
# отправить отчёт об ошибке). Исправлено в 11.14.
case "$wine_version" in
  wine-11.[7-9] | wine-11.[7-9][!0-9]* | wine-11.1[0-3] | wine-11.1[0-3][!0-9]*)
    fail "$wine_version: с msxml3 Wine 11.7–11.13 T-FLEX CAD падает при запуске; нужен другой Wine, например programs.tflex17.winePackage = pkgs.wineWow64Packages.stableFull"
    ;;
esac
note "winetricks: $(winetricks --version 2>/dev/null | head -n 1)"
note "WINEDEBUG=$WINEDEBUG WINEDLLOVERRIDES=$WINEDLLOVERRIDES"

section "Wine-префикс"
note "путь: $PREFIX"
state="$(tflex_prefix_state)"
case "$state" in
  win64) ok "64-битный Wine-префикс" ;;
  missing | empty) fail "префикса нет — установите программу: tflex17-install «T-FLEX CAD 17.msi»" ;;
  win32) fail "32-битный префикс — T-FLEX CAD 17 в нём не работает. $(tflex_reset_hint)" ;;
  broken) fail "префикс повреждён (нет drive_c или признака разрядности). $(tflex_reset_hint)" ;;
  *) fail "по этому пути не Wine-префикс ($state); проверьте TFLEX_WINEPREFIX" ;;
esac

if [ "$state" = win64 ]; then
  if [ -f "$META/prefix.creating" ]; then
    fail "инициализация префикса не завершилась — повторите tflex17-install или tflex17-deps --prefix-only"
  elif [ -f "$META/prefix.ok" ]; then
    ok "создан: $(cat "$META/prefix.ok")"
  else
    warn "префикс создан не T-FLEX-Nix (нет $META/prefix.ok)"
  fi
  missing_steps=()
  for step in "${TFLEX_PRE_STEPS[@]}" "${TFLEX_POST_STEPS[@]}"; do
    tflex_step_done "$step" || missing_steps+=("$step")
  done
  if [ "${#missing_steps[@]}" -eq 0 ]; then
    ok "все компоненты поддержки установлены"
  else
    warn "не выполнены шаги: ${missing_steps[*]} (tflex17-deps --list)"
  fi
  if tflex_busy; then
    warn "сейчас идёт установка (блокировка $META/lock занята)"
  fi
  note "свободно на диске: $(df -h --output=avail -- "$PREFIX" | tail -n 1 | tr -d ' ')"
fi

section "T-FLEX CAD"
if [ "$state" = win64 ]; then
  mapfile -t exes < <(tflex_find_exes)
  if [ "${#exes[@]}" -eq 0 ]; then
    fail "TFlexCad.exe не найден в Program Files префикса — tflex17-install «T-FLEX CAD 17.msi»"
  else
    for e in "${exes[@]}"; do
      ok "найден: $e"
    done
  fi
  # Записи об установленных продуктах из реестра (Uninstall).
  awk '
    function flush() {
      if (uninstall && name ~ /T-FLEX/) printf "  [ -- ] реестр: %s %s\n", name, ver
      name = ""; ver = ""
    }
    /^\[/ { flush(); uninstall = ($0 ~ /\\\\Uninstall\\\\/); next }
    /^"DisplayName"="/ { name = $0; sub(/^"DisplayName"="/, "", name); sub(/"$/, "", name) }
    /^"DisplayVersion"="/ { ver = $0; sub(/^"DisplayVersion"="/, "", ver); sub(/"$/, "", ver) }
    END { flush() }
  ' "$PREFIX/system.reg" | LC_ALL=C sort -u
else
  note "пропущено: нет префикса"
fi

section "Графика"
note "сеанс: ${XDG_SESSION_TYPE:-неизвестно}; DISPLAY=${DISPLAY:-не задан}; WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-не задан}"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  note "Hyprland: T-FLEX работает через XWayland; при дробном масштабе см. TFLEX_DPI и раздел про Hyprland в README"
fi
if [ -z "${DISPLAY:-}" ]; then
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    fail "DISPLAY не задан: XWayland не запущен или отключён в композиторе — Wine-окна T-FLEX работают через X11"
  else
    fail "DISPLAY не задан: нет графического сеанса"
  fi
elif xdpyinfo >/dev/null 2>&1; then
  ok "X-сервер $DISPLAY доступен"
else
  fail "X-сервер $DISPLAY недоступен"
fi
if [ -d /run/opengl-driver/lib ]; then
  ok "/run/opengl-driver есть (NixOS: hardware.graphics.enable)"
else
  warn "нет /run/opengl-driver: на NixOS включите hardware.graphics.enable (модуль programs.tflex17 включает сам); вне NixOS нужен nixGL"
fi
if [ -n "${DISPLAY:-}" ]; then
  if glx="$(glxinfo -B 2>/dev/null)"; then
    renderer="$(printf '%s\n' "$glx" | sed -n 's/^OpenGL renderer string: //p')"
    gl_version="$(printf '%s\n' "$glx" | sed -n 's/^OpenGL version string: //p')"
    case "$glx" in
      *"direct rendering: Yes"*) ok "OpenGL: $renderer ($gl_version)" ;;
      *) warn "OpenGL без прямого рендеринга: $renderer — 3D-окно T-FLEX будет медленным" ;;
    esac
    case "$renderer" in
      *llvmpipe* | *softpipe*) warn "программная отрисовка ($renderer): аппаратное ускорение не работает" ;;
    esac
  else
    fail "glxinfo не смог получить контекст OpenGL"
  fi
fi
if [ "${TFLEX_MESA_OVERRIDE:-0}" = 1 ]; then
  note "MESA_GL_VERSION_OVERRIDE при запуске: ${MESA_GL_VERSION_OVERRIDE:-3.2} (TFLEX_MESA_OVERRIDE=1, как в официальном скрипте)"
else
  note "MESA_GL_VERSION_OVERRIDE при запуске: ${MESA_GL_VERSION_OVERRIDE:-не задаётся}"
fi
note "устройство 3D при запуске: ${TFLEX_RENDER:-из настроек T-FLEX} (TFLEX_RENDER), force_compat_shaders=${force_compat_shaders:-true}"
dpi="${TFLEX_DPI:-$TFLEX_DEFAULT_DPI}"
note "DPI Wine: ${dpi:-как в префиксе}"
note "LC_CTYPE Wine: ${TFLEX_LC_CTYPE-ru_RU.UTF-8} (TFLEX_LC_CTYPE; ANSI-кодировка CP1251)"

section "Лицензирование"
note "учебной версии ключ не нужен; коммерческой и ознакомительной — ключ Sentinel HASP или Guardant"
if (exec 3<>/dev/tcp/127.0.0.1/1947) 2>/dev/null; then
  ok "Sentinel HASP License Manager отвечает на 127.0.0.1:1947 (http://localhost:1947)"
else
  note "Sentinel HASP License Manager на 127.0.0.1:1947 не отвечает (нужен для ключей HASP: services.tflex17-licensing.hasp)"
fi

section "Процессы и журналы"
if pgrep -u "$(id -u)" -x wineserver >/dev/null; then
  note "запущены wineserver: $(pgrep -u "$(id -u)" -x wineserver | tr '\n' ' ')"
else
  note "wineserver не запущен"
fi
if [ -d "$TFLEX_STATE/logs" ]; then
  mapfile -t logs < <(find "$TFLEX_STATE/logs" -maxdepth 1 -type f -name '*.log' | LC_ALL=C sort)
  if [ "${#logs[@]}" -gt 0 ]; then
    note "последний журнал: ${logs[${#logs[@]} - 1]}"
  fi
fi

printf '\n'
if [ "$errors" -gt 0 ]; then
  printf 'Найдено ошибок: %s\n' "$errors"
  exit 1
fi
printf 'Ошибок не найдено.\n'
