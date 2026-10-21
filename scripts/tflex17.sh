# Запуск T-FLEX CAD 17: tflex17 [файл.grb …]
#
# Повторяет официальный start-t-flex-cad-17.sh (Prerequisites_T-FLEX_Linux.zip),
# но без зашитых путей: префикс — TFLEX_WINEPREFIX, программа ищется в нём.

tflex_usage() {
  cat <<'EOF'
Использование: tflex17 [ФАЙЛ…]

Запускает T-FLEX CAD 17 из Wine-префикса. Файлы (.grb и др.) открываются
через зарегистрированный тип документа T-FLEX, как в официальном скрипте.

Переменные окружения:
  TFLEX_WINEPREFIX        префикс (по умолчанию ~/.local/share/tflex17/prefix)
  TFLEX_EXE               явный путь к TFlexCad.exe, если установлено несколько
  TFLEX_DPI               DPI интерфейса Wine (48–480), например 144 = 150 %
  TFLEX_VIRTUAL_DESKTOP   запуск в виртуальном рабочем столе Wine, например 1920x1080
  TFLEX_NO_MESA_OVERRIDE  1 — не задавать MESA_GL_VERSION_OVERRIDE=3.2
  TFLEX_WINEDEBUG         значение WINEDEBUG (по умолчанию fixme-all)
EOF
}

case "${1:-}" in
  -h | --help)
    tflex_usage
    exit 0
    ;;
esac

tflex_init

state="$(tflex_prefix_state)"
if [ "$state" != win64 ]; then
  tflex_die_gui "T-FLEX CAD 17 не установлен: нет готового Wine-префикса «$PREFIX» (состояние: $state). Установите программу: tflex17-install «/путь/к/T-FLEX CAD 17.msi»"
fi
if tflex_busy; then
  tflex_die_gui "В префиксе «$PREFIX» идёт установка (tflex17-install или tflex17-deps). Дождитесь её завершения."
fi
if ! tflex_select_exe; then
  tflex_die_gui "В префиксе «$PREFIX» не найден TFlexCad.exe. Установите T-FLEX CAD 17: tflex17-install «/путь/к/T-FLEX CAD 17.msi»"
fi
exe="$TFLEX_EXE_FOUND"
product="$(tflex_product_of "$exe")"

# Как в официальном скрипте запуска.
if [ "${TFLEX_NO_MESA_OVERRIDE:-0}" != 1 ]; then
  export MESA_GL_VERSION_OVERRIDE="${MESA_GL_VERSION_OVERRIDE:-3.2}"
  export MESA_GLSL_VERSION_OVERRIDE="${MESA_GLSL_VERSION_OVERRIDE:-330}"
fi

# Отключение многопроцессного импорта 3D-моделей — тоже из официального
# скрипта. Профиль английской версии (Parametric CAD) лежит в «Eng».
case "$product" in
  *Parametric*) lang=Eng ;;
  *) lang=Rus ;;
esac
options_key="HKEY_CURRENT_USER\\Software\\Top Systems\\T-FLEX CAD 3D 17\\$lang\\Profiles\\[Current]\\Options"
if ! wine reg add "$options_key" /v USED_COMMON_3D_IMPORT_MULTIPROCESS /t REG_DWORD /d 0 /f >/dev/null; then
  tflex_warn "не удалось записать USED_COMMON_3D_IMPORT_MULTIPROCESS в реестр"
fi

# Масштаб интерфейса. Под XWayland с отключённым масштабированием
# композитора (Hyprland: xwayland:force_zero_scaling) это единственный
# способ сделать окна Wine крупнее без размытия.
dpi="${TFLEX_DPI:-$TFLEX_DEFAULT_DPI}"
if [ -n "$dpi" ]; then
  case "$dpi" in
    *[!0-9]*) tflex_die_gui "TFLEX_DPI должен быть числом от 48 до 480, сейчас «$dpi»" ;;
  esac
  if [ "$dpi" -lt 48 ] || [ "$dpi" -gt 480 ]; then
    tflex_die_gui "TFLEX_DPI должен быть числом от 48 до 480, сейчас «$dpi»"
  fi
  if ! wine reg add 'HKEY_CURRENT_USER\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null; then
    tflex_warn "не удалось задать DPI $dpi"
  fi
fi

cd -- "${exe%/*}" || tflex_die_gui "нет доступа к каталогу «${exe%/*}»"

# Открытие файлов: если все аргументы — существующие файлы, они
# передаются через тип документа TFLEX.Document (как в официальном
# скрипте), иначе аргументы передаются TFlexCad.exe как есть.
files=()
for arg in "$@"; do
  if [ -f "$arg" ]; then
    files+=("$(realpath -- "$arg")")
  else
    files=()
    break
  fi
done

if [ "$#" -gt 0 ] && [ "${#files[@]}" -eq "$#" ]; then
  winfiles=()
  for f in "${files[@]}"; do
    winfiles+=("$(tflex_winpath "$f")")
  done
  opened=1
  for w in "${winfiles[@]}"; do
    if ! wine start /ProgIDOpen TFLEX.Document "$w"; then
      opened=0
      break
    fi
  done
  if [ "$opened" = 1 ]; then
    exit 0
  fi
  tflex_warn "тип документа TFLEX.Document не зарегистрирован — передаю файлы TFlexCad.exe напрямую"
  set -- "${winfiles[@]}"
fi

if [ -n "${TFLEX_VIRTUAL_DESKTOP:-}" ]; then
  if ! [[ "$TFLEX_VIRTUAL_DESKTOP" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
    tflex_die_gui "TFLEX_VIRTUAL_DESKTOP задаётся как ШИРИНАxВЫСОТА, например 1920x1080"
  fi
  # explorer запускает программу по Windows-пути.
  exec wine explorer "/desktop=TFLEX17,$TFLEX_VIRTUAL_DESKTOP" "$(tflex_winpath "$exe")" "$@"
fi
exec wine "$exe" "$@"
