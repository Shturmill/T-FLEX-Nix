# shellcheck shell=bash
#
# Общая часть команд tflex17*. При сборке пакета (pkgs/tflex17/default.nix)
# файл вставляется в начало каждой команды; отдельно он не запускается.
# writeShellApplication уже включил errexit, nounset и pipefail, а PATH
# собран из пакетов nixpkgs (wine, winetricks, coreutils…).
#
# Порядок установки и все параметры Wine взяты из официальных материалов
# «Топ Системы» (tflex.ru/downloads):
#   * «Порядок установки T-FLEX CAD 17 на ОС Linux в среде Wine»;
#   * скрипт менеджера установки t-flex-install-rus.sh и скрипт запуска
#     start-t-flex-cad-17.sh из архива Prerequisites_T-FLEX_Linux.zip.

# ------------------------------------------------------------------ вывод

tflex_log() { printf 'tflex17: %s\n' "$*" >&2; }
tflex_warn() { printf 'tflex17: внимание: %s\n' "$*" >&2; }

# tflex_die <сообщение> [код]. Коды: 1 — ошибка выполнения, 2 — неверный вызов.
tflex_die() {
  printf 'tflex17: ошибка: %s\n' "$1" >&2
  if [ -n "${TFLEX_LOG_FILE:-}" ]; then
    printf 'tflex17: журнал: %s\n' "$TFLEX_LOG_FILE" >&2
  fi
  exit "${2:-1}"
}

# Ошибка при запуске из меню приложений: терминала нет, поэтому сообщение
# дублируется окном zenity. Ярлык tflex17.desktop задаёт TFLEX_GUI_ERRORS=1;
# из терминала и скриптов окна не появляются.
tflex_die_gui() {
  if [ "${TFLEX_GUI_ERRORS:-0}" = 1 ] &&
    { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } &&
    command -v zenity >/dev/null; then
    if ! zenity --error --no-markup --width=520 --title="T-FLEX CAD 17" --text="$1" 2>/dev/null; then
      tflex_warn "не удалось показать окно с ошибкой (zenity)"
    fi
  fi
  tflex_die "$@"
}

# tflex_stamp <файл> [текст] — отметка времени выполнения шага.
tflex_stamp() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${2:-}" >"$1"
}

# ------------------------------------------------------------------ пути

# Каталоги по XDG и Wine-префикс. Префикс — только вне /nix/store: в нём
# изменяемые данные пользователя (реестр, установленные программы).
tflex_init() {
  [ -n "${HOME:-}" ] || tflex_die "не задана переменная HOME"
  TFLEX_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
  TFLEX_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/tflex17"
  TFLEX_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tflex17"

  PREFIX="${TFLEX_WINEPREFIX:-$TFLEX_DATA/tflex17/prefix}"
  while [ "$PREFIX" != / ] && [ "${PREFIX%/}" != "$PREFIX" ]; do
    PREFIX="${PREFIX%/}"
  done
  case "$PREFIX" in
    /) tflex_die "TFLEX_WINEPREFIX не может указывать на корень «/»" 2 ;;
    /nix/store/*) tflex_die "Wine-префикс не может лежать в /nix/store: «$PREFIX»" 2 ;;
    /*) ;;
    *) tflex_die "TFLEX_WINEPREFIX должен быть абсолютным путём, сейчас «$PREFIX»" 2 ;;
  esac
  # Служебные файлы T-FLEX-Nix (отметки шагов, блокировка, копия
  # компонентов) лежат внутри префикса и переезжают вместе с ним.
  META="$PREFIX/.tflex17"

  export WINEPREFIX="$PREFIX" WINEARCH=win64
  export WINEDEBUG="${TFLEX_WINEDEBUG:-${WINEDEBUG:-fixme-all}}"
  # winemenubuilder отключён: иначе Wine создаёт в домашнем каталоге
  # собственные .desktop-файлы и ассоциации со ссылками на /nix/store,
  # которые ломаются после сборки мусора. Ярлык даёт сам пакет.
  export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
}

# Журнал команды: весь вывод дублируется в $XDG_STATE_HOME/tflex17/logs.
tflex_start_log() {
  mkdir -p -- "$TFLEX_STATE/logs"
  TFLEX_LOG_FILE="$TFLEX_STATE/logs/$1-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a -- "$TFLEX_LOG_FILE") 2>&1
  tflex_log "журнал: $TFLEX_LOG_FILE"
}

# Временный каталог — в кэше, а не в /tmp: распакованный дистрибутив
# занимает около 1 ГБ, а /tmp часто в оперативной памяти.
TFLEX_TMP=""
tflex_tmpdir() {
  [ -z "$TFLEX_TMP" ] || return 0
  mkdir -p -- "$TFLEX_CACHE"
  TFLEX_TMP="$(mktemp -d -p "$TFLEX_CACHE" tmp.XXXXXXXX)"
  trap tflex_cleanup EXIT
}

# Единственное удаление каталога во всём проекте: только временный
# каталог, созданный mktemp в этом же запуске.
tflex_cleanup() {
  case "$TFLEX_TMP" in
    "$TFLEX_CACHE"/tmp.????????) rm -rf -- "$TFLEX_TMP" ;;
  esac
}

# Сигнатура файла: msi | exe | zip | unknown.
tflex_file_kind() {
  local magic
  magic="$(od -An -tx1 -N8 -- "$1" | tr -d ' \n')"
  case "$magic" in
    d0cf11e0a1b11ae1) echo msi ;; # OLE Compound File (Windows Installer)
    4d5a*) echo exe ;;
    504b0304* | 504b0506*) echo zip ;;
    *) echo unknown ;;
  esac
}

# ------------------------------------------------------------------ префикс

# Состояние каталога префикса (одно слово):
#   missing   — каталога нет;
#   empty     — каталог пуст или в нём только служебный .tflex17;
#   win64     — 64-битный Wine-префикс;
#   win32     — 32-битный Wine-префикс (T-FLEX CAD 17 в нём не работает);
#   broken    — есть system.reg, но нет drive_c или признака разрядности;
#   foreign   — каталог с посторонними файлами, не Wine-префикс;
#   not-a-dir — по этому пути лежит не каталог.
tflex_prefix_state() {
  if [ ! -e "$PREFIX" ] && [ ! -L "$PREFIX" ]; then
    echo missing
  elif [ ! -d "$PREFIX" ]; then
    echo not-a-dir
  elif [ ! -f "$PREFIX/system.reg" ]; then
    if [ -z "$(find "$PREFIX" -mindepth 1 -maxdepth 1 ! -name .tflex17 -print -quit)" ]; then
      echo empty
    else
      echo foreign
    fi
  elif [ ! -d "$PREFIX/drive_c" ]; then
    echo broken
  elif grep -q '^#arch=win64' "$PREFIX/system.reg"; then
    echo win64
  elif grep -q '^#arch=win32' "$PREFIX/system.reg"; then
    echo win32
  else
    echo broken
  fi
}

tflex_reset_hint() {
  printf '%s' "Чтобы начать с чистого префикса, выполните «tflex17-install --reset-prefix …» (старый каталог будет переименован, а не удалён) или укажите другой путь в TFLEX_WINEPREFIX."
}

# Проверка без изменений: подходит ли каталог для работы.
tflex_prefix_guard() {
  local state
  state="$(tflex_prefix_state)"
  case "$state" in
    missing | empty | win64) ;;
    win32) tflex_die "«$PREFIX» — 32-битный Wine-префикс, а T-FLEX CAD 17 — 64-битное приложение. $(tflex_reset_hint)" ;;
    broken) tflex_die "Wine-префикс «$PREFIX» повреждён: нет drive_c или признака разрядности в system.reg. $(tflex_reset_hint)" ;;
    foreign | not-a-dir) tflex_die "«$PREFIX» существует, но это не Wine-префикс; ничего в нём не меняю. Укажите другой путь в TFLEX_WINEPREFIX." ;;
    *) tflex_die "неизвестное состояние префикса: $state" ;;
  esac
}

# Одновременная установка в один префикс его ломает (это отмечено и в
# официальной инструкции), поэтому изменяющие команды берут блокировку.
# Дескриптор наследуют процессы Wine этого запуска: пока они живы,
# повторная установка в тот же префикс не начнётся.
tflex_lock() {
  mkdir -p -- "$META"
  exec {TFLEX_LOCK_FD}>>"$META/lock"
  if ! flock -n "$TFLEX_LOCK_FD"; then
    tflex_die "с префиксом «$PREFIX» уже работает другая команда tflex17 или её процессы Wine; дождитесь завершения"
  fi
}

# 0 — если сейчас в префиксе идёт установка (блокировка занята).
tflex_busy() {
  [ -f "$META/lock" ] || return 1
  local fd busy=0
  exec {fd}>>"$META/lock"
  if flock -n "$fd"; then busy=1; fi
  exec {fd}>&-
  [ "$busy" = 0 ]
}

# Создать префикс или убедиться, что существующий годится. Идемпотентно:
# готовый префикс не пересоздаётся и не перезаписывается.
tflex_prefix_ensure() {
  tflex_prefix_guard
  tflex_lock
  case "$(tflex_prefix_state)" in
    missing | empty)
      tflex_prefix_create
      ;;
    win64)
      if [ -f "$META/prefix.creating" ]; then
        tflex_warn "прошлая инициализация префикса не завершилась — повторяю wineboot"
        tflex_prefix_create
      elif [ ! -f "$META/prefix.ok" ]; then
        tflex_warn "префикс «$PREFIX» создан не T-FLEX-Nix — использую его как есть, существующие файлы не трогаю"
        tflex_stamp "$META/prefix.ok" adopted
      fi
      ;;
  esac
}

tflex_prefix_create() {
  mkdir -p -- "$META"
  tflex_stamp "$META/prefix.creating" "$(wine --version)"
  tflex_log "создаю 64-битный Wine-префикс: $PREFIX"
  # mscoree= — не ставить Wine Mono: .NET Framework 4.8 ставит winetricks
  # (официальный скрипт делает так же). Gecko ставится из пакета Wine.
  if ! WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree=" wine wineboot --init; then
    tflex_die "wineboot не смог создать префикс «$PREFIX»"
  fi
  # winemenubuilder отключается и в реестре префикса: winetricks запускает
  # установщики со своим WINEDLLOVERRIDES, и переменная из tflex_init там
  # не действует (проверено на настоящей установке: без этого появлялись
  # ~/.local/share/applications/wine-extension-*.desktop).
  if ! wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v winemenubuilder.exe /t REG_SZ /d '' /f >/dev/null; then
    tflex_die "не удалось отключить winemenubuilder в реестре префикса"
  fi
  wineserver -w
  if [ "$(tflex_prefix_state)" != win64 ]; then
    tflex_die "после wineboot «$PREFIX» не стал 64-битным Wine-префиксом"
  fi
  mv -f -- "$META/prefix.creating" "$META/prefix.ok"
}

# Сброс по явному запросу: префикс переименовывается, ничего не удаляется.
tflex_prefix_reset() {
  local assume_yes=$1 backup answer
  case "$(tflex_prefix_state)" in
    missing)
      tflex_log "префикса «$PREFIX» нет — сбрасывать нечего"
      return 0
      ;;
    foreign | not-a-dir)
      # Защита от ошибки в TFLEX_WINEPREFIX (например, указан $HOME).
      tflex_die "«$PREFIX» — не Wine-префикс; переименовывать его не буду. Проверьте TFLEX_WINEPREFIX."
      ;;
  esac
  backup="$PREFIX.bak-$(date +%Y%m%d-%H%M%S)"
  [ ! -e "$backup" ] || tflex_die "«$backup» уже существует; повторите через секунду"
  if [ "$assume_yes" != 1 ]; then
    [ -t 0 ] || tflex_die "--reset-prefix требует подтверждения: запустите команду в терминале или добавьте --yes" 2
    printf 'Префикс «%s» будет переименован в «%s» (ничего не удаляется).\nПродолжить? Введите yes: ' "$PREFIX" "$backup" >&2
    read -r answer || answer=""
    [ "$answer" = yes ] || tflex_die "сброс префикса отменён"
  fi
  if [ -d "$PREFIX" ] && tflex_busy; then
    tflex_die "в префиксе идёт установка — сброс невозможен"
  fi
  if [ -f "$PREFIX/system.reg" ] && wineserver -k 2>/dev/null; then
    tflex_log "остановлены процессы Wine этого префикса"
  fi
  mv -- "$PREFIX" "$backup"
  tflex_log "старый префикс сохранён как «$backup»; удалите его вручную, когда убедитесь, что он не нужен"
}

# ------------------------------------------------------------------ Wine

# Путь Unix → Windows. Нужен для msiexec и regedit: путь вида /home/…
# они приняли бы за ключ командной строки.
tflex_winpath() {
  local p
  p="$(wine winepath -w "$1")" || tflex_die "winepath не смог преобразовать «$1»"
  [ -n "$p" ] || tflex_die "winepath вернул пустой путь для «$1»"
  printf '%s' "$p"
}

# Коды завершения Windows-установщиков. Unix передаёт только младший байт,
# поэтому сравнение идёт по модулю 256.
tflex_msi_code_text() {
  case "$1" in
    1602) echo "установка отменена пользователем" ;;
    1603) echo "неустранимая ошибка установки" ;;
    1618) echo "уже идёт другая установка" ;;
    1619) echo "не удалось открыть пакет установки" ;;
    1620) echo "файл не является корректным пакетом Windows Installer" ;;
    1638) echo "уже установлена другая версия продукта" ;;
    3010) echo "требуется перезагрузка (в Wine не нужна)" ;;
    *) echo "код $1" ;;
  esac
}

# tflex_try_installer <название> "<допустимые коды Windows>" <команда…>
# Код 0 — успех; иначе причина в TFLEX_INSTALLER_ERROR и код 1.
tflex_try_installer() {
  local what=$1 ok=$2 rc=0 code
  shift 2
  TFLEX_INSTALLER_ERROR=""
  "$@" || rc=$?
  # Установщики запускают дочерние процессы и выходят раньше них.
  wineserver -w
  for code in $ok; do
    if [ "$rc" = $((code % 256)) ]; then
      tflex_log "$what: готово"
      return 0
    fi
  done
  TFLEX_INSTALLER_ERROR="$what: установщик завершился с кодом $rc"
  for code in 1602 1603 1618 1619 1620 1638 3010; do
    if [ "$rc" = $((code % 256)) ]; then
      TFLEX_INSTALLER_ERROR="$what: $(tflex_msi_code_text "$code") (код завершения $rc)"
    fi
  done
  return 1
}

# То же, но ошибка завершает команду.
tflex_run_installer() {
  tflex_try_installer "$@" || tflex_die "$TFLEX_INSTALLER_ERROR"
}

# Установщики из ZIP-архива дистрибутива («T-FLEX CAD 17.zip»,
# «TFCAD_ST_17x64_PACK.zip»). Задаёт TFLEX_MAIN_INSTALLER и массив
# TFLEX_EXTRA_INSTALLERS — пути к распакованным файлам.
#
# Имена в архивах «Топ Системы» записаны в кодировке OEM русской Windows
# (CP866) без признака UTF-8. unzip из nixpkgs заменяет такие буквы на «?»,
# а «?» недопустим в путях Windows — msiexec не нашёл бы файл. 7-Zip
# перекодирует их (-mcp=866), а имена с признаком UTF-8 оставляет как есть.
#
# Продукты — .msi в корне архива или в каталоге первого уровня
# («T-FLEX CAD Учебная Версия 17/T-FLEX CAD Учебная Версия 17.msi»).
# «Компоненты поддержки…» — Windows-версии VC++, .NET, драйверов HASP и
# Guardant — не ставятся: в Wine их заменяют шаги tflex17-deps, а
# официальная инструкция требует их отключить. Главный продукт —
# «T-FLEX…CAD….msi»; остальные (библиотеки, учебное пособие) ставятся после
# него. Setup.exe берётся, только если .msi нет.
tflex_unpack_installers() {
  local zip=$1 dir e base entries=() main=() extra=() setups=() selected=()
  tflex_tmpdir
  dir="$TFLEX_TMP/installer"
  mapfile -t entries < <(7zz l -ba -slt -mcp=866 -- "$zip" | sed -n 's/^Path = //p')
  [ "${#entries[@]}" -gt 0 ] || tflex_die "не удалось прочитать ZIP-архив «$zip»"
  for e in "${entries[@]}"; do
    case "$e" in
      Компоненты\ поддержки* | */*/*) continue ;;
    esac
    base="${e##*/}"
    case "${base,,}" in
      t-flex*cad*.msi) main+=("$e") ;;
      *.msi) extra+=("$e") ;;
      setup.exe) setups+=("$e") ;;
    esac
  done
  # Архив модуля или библиотеки: единственный .msi и есть установщик.
  if [ "${#main[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 1 ]; then
    main=("${extra[@]}")
    extra=()
  fi
  if [ "${#main[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ] && [ "${#setups[@]}" -eq 1 ]; then
    main=("${setups[@]}")
  fi
  if [ "${#main[@]}" -ne 1 ]; then
    if [ "${#main[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ]; then
      tflex_die "в архиве «$zip» нет установщика T-FLEX (.msi или Setup.exe)"
    fi
    printf '  %s\n' "${main[@]}" "${extra[@]}" >&2
    tflex_die "в архиве «$zip» не удалось выбрать главный установщик (см. список выше); распакуйте архив и укажите нужный файл"
  fi
  selected=("${main[@]}" "${extra[@]}")
  tflex_log "распаковываю из «${zip##*/}»: ${selected[*]}"
  if ! 7zz x -mcp=866 -spd -y -bso0 -bsp0 -o"$dir" -- "$zip" "${selected[@]}"; then
    tflex_die "не удалось распаковать «$zip» (7-Zip)"
  fi
  TFLEX_MAIN_INSTALLER="$dir/${main[0]}"
  TFLEX_EXTRA_INSTALLERS=()
  for e in "${extra[@]}"; do
    TFLEX_EXTRA_INSTALLERS+=("$dir/$e")
  done
  for e in "$TFLEX_MAIN_INSTALLER" "${TFLEX_EXTRA_INSTALLERS[@]}"; do
    [ -f "$e" ] || tflex_die "после распаковки нет файла «$e»"
  done
}

# Содержит ли реестр префикса строку (system.reg записывается на диск,
# когда wineserver завершается, поэтому сначала wineserver -w).
tflex_registry_has() {
  wineserver -w
  grep -qF -- "$1" "$PREFIX/system.reg"
}

# regedit не сообщает об ошибках кодом завершения, поэтому результат
# импорта проверяется по самому реестру.
# tflex_reg_import <32|64> <файл.reg> <строка-признак>
tflex_reg_import() {
  local view=$1 file=$2 marker=$3 regedit
  [ -f "$file" ] || tflex_die "нет файла реестра «$file»"
  if [ "$view" = 32 ]; then
    # 32-битный regedit пишет в 32-битное представление реестра (Wow6432Node).
    regedit='C:\windows\syswow64\regedit.exe'
  else
    regedit=regedit
  fi
  wine "$regedit" /S "$(tflex_winpath "$file")"
  tflex_registry_has "$marker" ||
    tflex_die "после импорта «$file» ($view-бит) в реестре нет «$marker»"
}

# ------------------------------------------------------------------ компоненты

# Состав Prerequisites_T-FLEX_Linux.zip, который использует официальный
# скрипт t-flex-install-rus.sh при установке T-FLEX CAD 17.
TFLEX_PREREQ_FILES=(
  Components/vc_redist.x86.exe
  Components/vc_redist.x64.exe
  Components/AccessDatabaseEngine.exe
  Components/Setup_TSC2.msi
  Components/fake_hasp.reg
  Components/ado-32.reg
  Components/ado-64.reg
)
TFLEX_PREREQ_DIRS=(
  "Components/Program Files/Common Files/System"
  "Components/Program Files (x86)/Common Files/System"
  Components/Windows/System32
)

# Шаги до установки T-FLEX CAD и после неё (как в t-flex-install-rus.sh).
# Нужны не всем командам, отсюда отключённая проверка SC2034.
# shellcheck disable=SC2034
TFLEX_PRE_STEPS=(winetricks vcredist accessdb tsc2 hasp-driver-reg)
# shellcheck disable=SC2034
TFLEX_POST_STEPS=(system-files ado-reg)
# Шаги, которым нужен архив компонентов (winetricks без него скачивает
# пакеты Microsoft сам; шаги «после» берут сохранённую копию).
TFLEX_PREREQ_STEPS=" vcredist accessdb tsc2 hasp-driver-reg "

tflex_step_title() {
  case "$1" in
    winetricks) echo ".NET Framework 4.8, Visual C++ 2019, d3dcompiler_47, сглаживание шрифтов (winetricks)" ;;
    vcredist) echo "Microsoft Visual C++ Redistributable x86 и x64 из архива" ;;
    accessdb) echo "Microsoft Access Database Engine 2007" ;;
    tsc2) echo "TechSmith Screen Codec 2 (видео в справке)" ;;
    hasp-driver-reg) echo "сведения о драйвере Sentinel HASP в реестре Wine (fake_hasp.reg)" ;;
    system-files) echo "библиотеки ADO/OLE DB и системные DLL из архива" ;;
    ado-reg) echo "регистрация ADO в 32- и 64-битном реестре" ;;
    *) return 1 ;;
  esac
}

tflex_step_done() { [ -f "$META/steps/$1.done" ]; }

# Найти архив компонентов, если путь не указан: переменная TFLEX_PREREQS,
# затем каталог загрузок (так ищет и официальный менеджер установки).
tflex_prereqs_locate() {
  local given=$1 c
  if [ -n "$given" ]; then
    printf '%s' "$given"
    return 0
  fi
  if [ -n "${TFLEX_PREREQS:-}" ]; then
    printf '%s' "$TFLEX_PREREQS"
    return 0
  fi
  for c in "$HOME/Downloads/Prerequisites_T-FLEX_Linux.zip" "$HOME/Загрузки/Prerequisites_T-FLEX_Linux.zip"; do
    if [ -f "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

tflex_prereqs_hint() {
  printf '%s' "Скачайте «Компоненты поддержки T-FLEX PLM 17 (Linux)» — Prerequisites_T-FLEX_Linux.zip — с https://www.tflex.ru/downloads/ и укажите путь: --prereqs /путь/к/Prerequisites_T-FLEX_Linux.zip (или переменная TFLEX_PREREQS)."
}

# tflex_prereqs_open <zip|каталог> — задаёт PREREQS (каталог с Components/).
tflex_prereqs_open() {
  local src=$1 rc=0 f missing=()
  [ -e "$src" ] || tflex_die "нет файла или каталога компонентов «$src». $(tflex_prereqs_hint)"
  if [ -d "$src" ]; then
    PREREQS="$(cd -- "$src" && pwd -P)"
    # Допускается указать сам каталог Components.
    if [ ! -d "$PREREQS/Components" ] && [ "${PREREQS##*/}" = Components ]; then
      PREREQS="${PREREQS%/*}"
    fi
  else
    [ "$(tflex_file_kind "$src")" = zip ] ||
      tflex_die "«$src» — не ZIP-архив и не каталог. $(tflex_prereqs_hint)"
    tflex_tmpdir
    PREREQS="$TFLEX_TMP/prereqs"
    tflex_log "распаковываю нужные части «$src»…"
    # Код 11 — «нет файлов по одному из шаблонов» (например, в архиве нет
    # офлайн-кэша winetricks); состав проверяется ниже.
    unzip -q -o "$src" -d "$PREREQS" \
      'Components/*.exe' 'Components/*.msi' 'Components/*.reg' \
      'Components/Program Files/Common Files/System/*' \
      'Components/Program Files (x86)/Common Files/System/*' \
      'Components/Windows/System32/*' 'winetricks/*' || rc=$?
    case "$rc" in
      0 | 11) ;;
      *) tflex_die "не удалось распаковать «$src» (unzip, код $rc)" ;;
    esac
  fi
  for f in "${TFLEX_PREREQ_FILES[@]}"; do
    [ -f "$PREREQS/$f" ] || missing+=("$f")
  done
  for f in "${TFLEX_PREREQ_DIRS[@]}"; do
    [ -d "$PREREQS/$f" ] || missing+=("$f/")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    tflex_die "в «$src» нет нужных файлов: ${missing[*]}. Нужен официальный архив Prerequisites_T-FLEX_Linux.zip. $(tflex_prereqs_hint)"
  fi
  tflex_log "компоненты поддержки: $src"
}

# Файлы для шагов «после установки» сохраняются в префиксе: их нужно
# применять заново после каждой установки или обновления T-FLEX CAD, а
# архив к тому времени может быть уже удалён (копия — около 15 МБ).
tflex_components_save() {
  local dst="$META/components" d
  for d in "Program Files/Common Files/System" "Program Files (x86)/Common Files/System" Windows/System32; do
    mkdir -p -- "$dst/$d"
    cp -rf --no-preserve=mode,ownership -- "$PREREQS/Components/$d/." "$dst/$d/"
  done
  cp -f --no-preserve=mode,ownership -- "$PREREQS/Components/ado-32.reg" "$PREREQS/Components/ado-64.reg" "$dst/"
  tflex_stamp "$META/components.ok"
}

tflex_components_saved() { [ -f "$META/components.ok" ]; }

# ------------------------------------------------------------------ шаги

tflex_step_winetricks() {
  local verb cache="${W_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/winetricks}"
  export W_CACHE="$cache"
  # bin/wine в nixpkgs — shell-обёртка над bin/.wine. По ней winetricks не
  # определяет разрядность Wine («Unknown file arch»), не распознаёт режим
  # WoW64 и не находит 64-битный загрузчик. Для обёрток winetricks
  # предусматривает переменную WINE_BIN с путём к настоящему бинарнику.
  if [ -z "${WINE_BIN:-}" ] && [ -x "$TFLEX_WINE_PACKAGE/bin/.wine" ]; then
    export WINE_BIN="$TFLEX_WINE_PACKAGE/bin/.wine"
  fi
  if [ -n "${PREREQS:-}" ] && [ -d "$PREREQS/winetricks" ]; then
    # Офлайн-кэш из официального архива; winetricks сверяет SHA-256
    # каждого файла и при несовпадении скачивает его заново.
    mkdir -p -- "$cache"
    cp -r --update=none --no-preserve=mode,ownership -- "$PREREQS/winetricks/." "$cache/"
    tflex_log "офлайн-кэш winetricks из архива скопирован в $cache"
  fi
  # Набор и порядок — как в install_tricks() из t-flex-install-rus.sh.
  for verb in dotnet48 vcrun2019 d3dcompiler_47 fontsmooth=rgb; do
    tflex_log "winetricks $verb"
    if ! winetricks --unattended "$verb"; then
      tflex_die "winetricks $verb завершился с ошибкой; повторить: tflex17-deps --only winetricks"
    fi
  done
  wineserver -w
}

tflex_step_vcredist() {
  local arch
  for arch in x86 x64; do
    tflex_run_installer "Visual C++ Redistributable ($arch)" "0 1638 3010" \
      wine "$PREREQS/Components/vc_redist.$arch.exe" /install /quiet /norestart
  done
}

tflex_step_accessdb() {
  tflex_run_installer "Access Database Engine 2007" "0 3010" \
    wine "$PREREQS/Components/AccessDatabaseEngine.exe" /quiet
}

tflex_step_tsc2() {
  tflex_run_installer "TechSmith Screen Codec 2" "0 1638 3010" \
    wine msiexec /i "$(tflex_winpath "$PREREQS/Components/Setup_TSC2.msi")" /qn
}

# fake_hasp.reg из официального архива записывает в реестр Wine только
# сведения об установленном драйвере Sentinel HASP 8.23. Ключ при этом
# по-прежнему обслуживает служба HASP License Manager на хосте; проверки
# лицензии этот шаг не меняет. Импорт в оба представления реестра:
# официальный скрипт вызывает «wine regedit», разрядность которого
# зависит от сборки Wine.
tflex_step_hasp_driver_reg() {
  local file="$PREREQS/Components/fake_hasp.reg"
  tflex_reg_import 64 "$file" '[Software\\Aladdin Knowledge Systems\\HASP\\Driver\\Installer]'
  tflex_reg_import 32 "$file" '[Software\\Wow6432Node\\Aladdin Knowledge Systems\\HASP\\Driver\\Installer]'
}

# Официальный скрипт удаляет «Common Files/System» и копирует его заново.
# Здесь файлы копируются поверх, без удаления: результат для файлов из
# архива тот же, а посторонние файлы префикса не пропадают.
tflex_step_system_files() {
  local src="$META/components" dst="$PREFIX/drive_c" d
  for d in "Program Files/Common Files/System" "Program Files (x86)/Common Files/System"; do
    mkdir -p -- "$dst/$d"
    cp -rf --no-preserve=mode,ownership -- "$src/$d/." "$dst/$d/"
  done
  mkdir -p -- "$dst/windows/system32"
  cp -f --no-preserve=mode,ownership -- "$src/Windows/System32/"*.dll "$dst/windows/system32/"
}

# Признак — путь к msadox.dll: в собственном реестре Wine его нет.
tflex_step_ado_reg() {
  local src="$META/components"
  tflex_reg_import 32 "$src/ado-32.reg" 'C:\\Program Files (x86)\\Common Files\\System\\ADO\\msadox.dll'
  tflex_reg_import 64 "$src/ado-64.reg" 'C:\\Program Files\\Common Files\\System\\ADO\\msadox.dll'
}

# Установка поверх работающего T-FLEX CAD ломает файлы в префиксе, а
# «wineserver -w» ждал бы закрытия программы.
tflex_ensure_not_running() {
  if pgrep -u "$(id -u)" -f -i 'tflexcad\.exe' >/dev/null; then
    tflex_die "T-FLEX CAD запущен — закройте его и повторите команду"
  fi
}

# tflex_run_step <шаг> <повторить: 0|1>
tflex_run_step() {
  local step=$1 force=$2
  if [ "$force" != 1 ] && tflex_step_done "$step"; then
    tflex_log "шаг «$step» уже выполнен — пропускаю (повторить: --force)"
    return 0
  fi
  tflex_log "шаг «$step»: $(tflex_step_title "$step")"
  case " $TFLEX_PREREQ_STEPS " in
    *" $step "*)
      [ -n "${PREREQS:-}" ] || tflex_die "для шага «$step» нужен архив компонентов. $(tflex_prereqs_hint)"
      ;;
  esac
  case "$step" in
    system-files | ado-reg)
      tflex_components_saved || tflex_die "для шага «$step» нужен архив компонентов. $(tflex_prereqs_hint)"
      ;;
  esac
  "tflex_step_${step//-/_}"
  mkdir -p -- "$META/steps"
  tflex_stamp "$META/steps/$step.done"
}

# Нужен ли архив компонентов для этих шагов (с учётом выполненных).
# tflex_steps_need_prereqs <повторить: 0|1> <шаги…>
tflex_steps_need_prereqs() {
  local force=$1 step
  shift
  for step in "$@"; do
    if [ "$force" != 1 ] && tflex_step_done "$step"; then continue; fi
    case " $TFLEX_PREREQ_STEPS " in *" $step "*) return 0 ;; esac
    case "$step" in
      system-files | ado-reg) tflex_components_saved || return 0 ;;
    esac
  done
  return 1
}

# ------------------------------------------------------------------ T-FLEX

# Установленный T-FLEX CAD ищется по реальным файлам префикса:
# «Program Files*/<продукт>/Program/TFlexCad.exe». Имя каталога продукта
# зависит от редакции и языка («T-FLEX CAD 17», «T-FLEX CAD Учебная
# Версия 17», «T-FLEX Parametric CAD 17»…), поэтому не задаётся заранее.
tflex_find_exes() {
  local pf
  for pf in "$PREFIX/drive_c/Program Files" "$PREFIX/drive_c/Program Files (x86)"; do
    [ -d "$pf" ] || continue
    find "$pf" -mindepth 3 -maxdepth 3 -type f -iname tflexcad.exe -ipath '*/program/tflexcad.exe'
  done | LC_ALL=C sort
}

tflex_product_of() {
  local d=${1%/*}
  d=${d%/*}
  printf '%s' "${d##*/}"
}

# Выбрать TFlexCad.exe: явный TFLEX_EXE, иначе продукт версии 17.
# Задаёт TFLEX_EXE_FOUND; код 1 — ничего не найдено.
tflex_select_exe() {
  local found=() preferred=() f
  TFLEX_EXE_FOUND=""
  if [ -n "${TFLEX_EXE:-}" ]; then
    [ -f "$TFLEX_EXE" ] || tflex_die "TFLEX_EXE: нет файла «$TFLEX_EXE»"
    TFLEX_EXE_FOUND="$TFLEX_EXE"
    return 0
  fi
  mapfile -t found < <(tflex_find_exes)
  [ "${#found[@]}" -gt 0 ] || return 1
  for f in "${found[@]}"; do
    case "$(tflex_product_of "$f")" in *17*) preferred+=("$f") ;; esac
  done
  if [ "${#preferred[@]}" -eq 0 ]; then
    tflex_warn "найден T-FLEX CAD не версии 17: ${found[0]}"
    preferred=("${found[@]}")
  fi
  TFLEX_EXE_FOUND="${preferred[0]}"
  if [ "${#preferred[@]}" -gt 1 ]; then
    tflex_log "найдено несколько установок, запускается «$(tflex_product_of "$TFLEX_EXE_FOUND")»; другую можно выбрать переменной TFLEX_EXE:"
    printf '  %s\n' "${preferred[@]}" >&2
  fi
}

# Иконка приложения извлекается из установленного TFlexCad.exe (icoutils)
# в ~/.local/share/icons — только локально, в репозитории иконки нет.
tflex_install_icon() {
  local exe=$1 work icos=() ico png size n=0
  tflex_tmpdir
  work="$TFLEX_TMP/icon"
  mkdir -p -- "$work/ico" "$work/png"
  if ! wrestool -x -t 14 -o "$work/ico" "$exe" 2>/dev/null; then
    tflex_warn "не удалось извлечь иконку из «$exe» — в меню будет значок по умолчанию"
    return 0
  fi
  # Первая группа иконок исполняемого файла — значок приложения.
  mapfile -t icos < <(find "$work/ico" -type f -name '*.ico' | LC_ALL=C sort)
  ico="${icos[0]:-}"
  if [ -z "$ico" ] || ! icotool -x -o "$work/png" "$ico" 2>/dev/null; then
    tflex_warn "в «$exe» не найдено иконок — в меню будет значок по умолчанию"
    return 0
  fi
  for png in "$work/png"/*.png; do
    [ -f "$png" ] || continue
    # Имена icotool: <файл>_<номер>_<ширина>x<высота>x<глубина>.png
    size="$(printf '%s' "${png##*/}" | sed -n 's/.*_\([0-9]*\)x\([0-9]*\)x[0-9]*\.png$/\1x\2/p')"
    case "$size" in
      16x16 | 24x24 | 32x32 | 48x48 | 64x64 | 128x128 | 256x256)
        mkdir -p -- "$TFLEX_DATA/icons/hicolor/$size/apps"
        cp -f -- "$png" "$TFLEX_DATA/icons/hicolor/$size/apps/tflex17.png"
        n=$((n + 1))
        ;;
    esac
  done
  if [ "$n" -gt 0 ]; then
    tflex_log "иконка установлена в $TFLEX_DATA/icons/hicolor"
  else
    tflex_warn "иконки стандартных размеров не найдены — в меню будет значок по умолчанию"
  fi
}
