# shellcheck shell=bash
#
# Сценарии команд tflex17* на фальшивом Wine (tests/mocks). Проверяется
# логика установщика: входные файлы, префикс, порядок шагов, повторные
# запуски, блокировки, обработка ошибок, пробелы в путях. Работу самого
# T-FLEX CAD и настоящего Wine эти проверки НЕ подтверждают.
#
# Запуск: bash tests/scenarios.sh (PATH: tflex17 с фальшивым Wine, zip,
# coreutils, findutils, gnugrep, gnused, util-linux).

set -euo pipefail

T="$(mktemp -d)"
FX="$T/fixtures with spaces"
passed=0
failed=()

# ------------------------------------------------------------ помощники

fresh() {
  HOME="$(mktemp -d "$T/home.XXXXXX")"
  export HOME
  unset XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME TFLEX_WINEPREFIX TFLEX_PREREQS \
    TFLEX_EXE TFLEX_DPI TFLEX_VIRTUAL_DESKTOP DISPLAY WAYLAND_DISPLAY \
    MESA_GL_VERSION_OVERRIDE MESA_GLSL_VERSION_OVERRIDE TFLEX_MESA_OVERRIDE TFLEX_RENDER TFLEX_GUI_ERRORS \
    LC_ALL LC_CTYPE TFLEX_LC_CTYPE force_compat_shaders
  export MOCK_LOG="$HOME/mock.log"
  : >"$MOCK_LOG"
  PFX="$HOME/.local/share/tflex17/prefix"
}

fail() {
  echo "    $*"
  return 1
}

# expect_fail <регулярное выражение в выводе> <команда…>
expect_fail() {
  local re=$1 out rc=0
  shift
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "ожидалась ошибка: $* — вывод: $out"
  grep -qE -- "$re" <<<"$out" || fail "в выводе нет «$re»: $out"
}

# count <строка> — сколько раз строка встречается в журнале mock.
count() {
  local n
  n="$(grep -cF -- "$1" "$MOCK_LOG")" || n=0
  echo "$n"
}

line_of() {
  local n
  n="$(grep -nF -m1 -- "$1" "$MOCK_LOG" | cut -d: -f1)" || n=""
  [ -n "$n" ] || fail "в журнале mock нет «$1»"
  echo "$n"
}

assert_count() {
  local got
  got="$(count "$2")"
  [ "$got" = "$1" ] || fail "ожидалось $1 вызовов «$2», найдено $got"
}

# Снимок дерева для проверки «ничего не изменилось».
snapshot() { (cd "$1" && find . -printf '%p %s %T@\n' | LC_ALL=C sort | sha256sum); }

run() {
  local name=$1 out
  out="$T/$name.out"
  if ("$name") >"$out" 2>&1; then
    passed=$((passed + 1))
    echo "ok   $name"
  else
    failed+=("$name")
    echo "FAIL $name"
    sed 's/^/    | /' "$out"
  fi
}

# ------------------------------------------------------------ фикстуры

msi() { # msi <путь> <каталог продукта> [код завершения]
  mkdir -p "$(dirname "$1")"
  printf '\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1\nMOCK-PRODUCT=%s\nMOCK-EXIT=%s\n' "$2" "${3:-0}" >"$1"
}

exe() { # exe <путь>
  mkdir -p "$(dirname "$1")"
  printf 'MZ\nmock\n' >"$1"
}

make_fixtures() {
  local c="$FX/prereqs/Components"
  exe "$c/vc_redist.x86.exe"
  exe "$c/vc_redist.x64.exe"
  exe "$c/AccessDatabaseEngine.exe"
  msi "$c/Setup_TSC2.msi" ""
  printf '%s\r\n' 'Windows Registry Editor Version 5.00' '' \
    '[HKEY_LOCAL_MACHINE\Software\Aladdin Knowledge Systems\HASP\Driver\Installer]' \
    '"DrvPkgVersion"="8.23"' >"$c/fake_hasp.reg"
  printf '%s\r\n' 'Windows Registry Editor Version 5.00' '' \
    '[HKEY_CLASSES_ROOT\CLSID\{00000602-0000-0010-8000-00AA006D2EA4}\InprocServer32]' \
    '@="C:\\Program Files (x86)\\Common Files\\System\\ADO\\msadox.dll"' >"$c/ado-32.reg"
  printf '%s\r\n' 'Windows Registry Editor Version 5.00' '' \
    '[HKEY_CLASSES_ROOT\CLSID\{00000602-0000-0010-8000-00AA006D2EA4}\InprocServer32]' \
    '@="C:\\Program Files\\Common Files\\System\\ADO\\msadox.dll"' >"$c/ado-64.reg"
  mkdir -p "$c/Program Files/Common Files/System/ado" "$c/Program Files (x86)/Common Files/System/ado" \
    "$c/Windows/System32" "$FX/prereqs/winetricks/dotnet48"
  echo native64 >"$c/Program Files/Common Files/System/ado/msadox.dll"
  echo native32 >"$c/Program Files (x86)/Common Files/System/ado/msadox.dll"
  echo msxml >"$c/Windows/System32/msxml6.dll"
  echo cached >"$FX/prereqs/winetricks/dotnet48/ndp48-x86-x64-allos-enu.exe"
  # Лишнее содержимое настоящего архива, которое распаковывать не нужно.
  mkdir -p "$c/Program Files/Common Files/Microsoft Shared/ink"
  echo big >"$c/Program Files/Common Files/Microsoft Shared/ink/big.dat"

  mkdir -p "$FX/downloads dir"
  (cd "$FX/prereqs" && zip -qr "$FX/downloads dir/Prerequisites_T-FLEX_Linux.zip" .)

  msi "$FX/downloads dir/T-FLEX CAD 17.msi" "T-FLEX CAD 17"
  msi "$FX/downloads dir/T-FLEX CAD Учебная Версия 17.msi" "T-FLEX CAD Учебная Версия 17"
  msi "$FX/downloads dir/broken.msi" "T-FLEX CAD 17" 1603
  msi "$FX/zip src/T-FLEX CAD 17/T-FLEX CAD 17.msi" "T-FLEX CAD 17"
  (cd "$FX/zip src" && zip -qr "$FX/downloads dir/T-FLEX CAD 17.zip" "T-FLEX CAD 17")
  echo "not an installer" >"$FX/downloads dir/readme.txt"

  # Пакеты как TFCAD_ST_17x64_PACK.zip: имена в CP866 без признака UTF-8,
  # главный продукт, библиотека, Setup.exe и Windows-компоненты, которые
  # ставить нельзя.
  local main="T-FLEX CAD Учебная Версия 17" lib="Стандартные элементы 17" comp="Компоненты поддержки T-FLEX 17"
  local pk cp_main cp_lib cp_comp
  cp_main="$(printf '%s' "$main" | iconv -f UTF-8 -t CP866)"
  cp_lib="$(printf '%s' "$lib" | iconv -f UTF-8 -t CP866)"
  cp_comp="$(printf '%s' "$comp" | iconv -f UTF-8 -t CP866)"
  for pk in pack badlib; do
    msi "$FX/$pk/$cp_main/$cp_main.msi" "$main"
    msi "$FX/$pk/$cp_lib/$cp_lib.msi" "" "$([ "$pk" = badlib ] && echo 1603 || echo 0)"
    msi "$FX/$pk/$cp_comp/Guardant Control Center/grdcontrol-4.5.3.msi" "GUARDANT-MUST-NOT-INSTALL"
    exe "$FX/$pk/Setup.exe"
  done
  (cd "$FX/pack" && LC_ALL=C zip -qr "$FX/downloads dir/TFCAD_ST_17x64_PACK.zip" .)
  (cd "$FX/badlib" && LC_ALL=C zip -qr "$FX/downloads dir/pack-badlib.zip" .)
  mkdir -p "$FX/docs dir"
  echo grb >"$FX/docs dir/My Drawing.grb"
}

MSI="$FX/downloads dir/T-FLEX CAD 17.msi"
ZIP_PRE="$FX/downloads dir/Prerequisites_T-FLEX_Linux.zip"

# Полная установка в свежий HOME.
install_ok() {
  tflex17-install --prereqs "$ZIP_PRE" "$MSI" >"$HOME/install.out" 2>&1 ||
    fail "установка не удалась: $(cat "$HOME/install.out")"
}

# ------------------------------------------------------------ сценарии

t_help() {
  fresh
  tflex17 --help | grep -q TFLEX_WINEPREFIX
  tflex17-install --help | grep -q -- --prereqs
  tflex17-deps --help | grep -q -- --only
  tflex17-winecfg --help >/dev/null
  tflex17-wine --help >/dev/null
  tflex17-doctor --help >/dev/null
}

t_missing_installer() {
  fresh
  expect_fail 'нет файла установщика' tflex17-install --prereqs "$ZIP_PRE" "$FX/нет такого файла.msi"
  expect_fail 'не указан установщик' tflex17-install
  [ ! -e "$HOME/.local/share/tflex17" ] || fail "при ошибке входных данных создан префикс"
  [ "$(count wine)" = 0 ] || fail "wine вызывался до проверки входных файлов"
}

t_bad_installer_format() {
  fresh
  expect_fail 'не MSI, не EXE и не ZIP' tflex17-install --prereqs "$ZIP_PRE" "$FX/downloads dir/readme.txt"
  [ ! -e "$HOME/.local/share/tflex17" ] || fail "создан префикс"
}

t_missing_prereqs() {
  fresh
  expect_fail 'нужны компоненты поддержки' tflex17-install "$MSI"
  expect_fail 'нет файла или каталога компонентов' tflex17-install --prereqs "$FX/нет.zip" "$MSI"
  [ ! -e "$PFX/system.reg" ] || fail "создан префикс без компонентов"
}

t_incomplete_prereqs() {
  fresh
  mkdir -p "$HOME/partial/Components"
  cp "$FX/prereqs/Components/vc_redist.x86.exe" "$HOME/partial/Components/"
  expect_fail 'нет нужных файлов: .*AccessDatabaseEngine.exe' tflex17-install --prereqs "$HOME/partial" "$MSI"
}

t_full_install() {
  fresh
  install_ok
  grep -q '#arch=win64' "$PFX/system.reg" || fail "префикс не 64-битный"
  # Префикс создаётся без Wine Mono и без winemenubuilder.
  grep -q 'wineboot env WINEARCH=win64 WINEDLLOVERRIDES=winemenubuilder.exe=d;mscoree=' "$MOCK_LOG" ||
    fail "wineboot без нужных WINEARCH/WINEDLLOVERRIDES"
  grep -qF 'Wine\DllOverrides /v winemenubuilder.exe /t REG_SZ /d  /f' "$PFX/user.reg" ||
    fail "winemenubuilder не отключён в реестре префикса"
  # Порядок шагов как в официальном скрипте.
  local prev=0 n s
  for s in '[wineboot]' '[dotnet48]' '[vcrun2019]' '[d3dcompiler_47]' '[fontsmooth=rgb]' '[tahoma]' \
    'vc_redist.x86.exe] [/install] [/quiet] [/norestart]' 'vc_redist.x64.exe] [/install] [/quiet] [/norestart]' \
    'AccessDatabaseEngine.exe] [/quiet]' 'Setup_TSC2.msi] [/qn]' \
    'regedit-import view=64 file=fake_hasp.reg' 'regedit-import view=32 file=fake_hasp.reg' \
    'T-FLEX CAD 17.msi] [/l*v]' \
    'regedit-import view=32 file=ado-32.reg' 'regedit-import view=64 file=ado-64.reg'; do
    n="$(line_of "$s")"
    [ "$n" -gt "$prev" ] || fail "шаг «$s» не на своём месте (строка $n, предыдущий $prev)"
    prev=$n
  done
  # msiexec получил Windows-путь с пробелами одним аргументом.
  grep -qF "[msiexec] [/i] [Z:\\" "$MOCK_LOG" || fail "msiexec получил не Windows-путь"
  grep -qF 'downloads dir\T-FLEX CAD 17.msi]' "$MOCK_LOG" || fail "путь с пробелами разбит"
  # Офлайн-кэш winetricks из архива.
  [ -f "$HOME/.cache/winetricks/dotnet48/ndp48-x86-x64-allos-enu.exe" ] || fail "кэш winetricks не скопирован"
  # winetricks получает настоящий загрузчик Wine, а не обёртку bin/wine.
  grep -qE 'winetricks .*WINE_BIN=/nix/store/[^ ]*/bin/\.wine$' "$MOCK_LOG" || fail "winetricks без WINE_BIN"
  # Файлы «после установки» и отметки шагов.
  [ "$(cat "$PFX/drive_c/Program Files/Common Files/System/ado/msadox.dll")" = native64 ] || fail "ADO x64 не скопирован"
  [ "$(cat "$PFX/drive_c/Program Files (x86)/Common Files/System/ado/msadox.dll")" = native32 ] || fail "ADO x86 не скопирован"
  [ -f "$PFX/drive_c/windows/system32/msxml6.dll" ] || fail "System32 DLL не скопированы"
  for s in winetricks tahoma vcredist accessdb tsc2 hasp-driver-reg system-files ado-reg; do
    [ -f "$PFX/.tflex17/steps/$s.done" ] || fail "нет отметки шага $s"
  done
  [ -f "$PFX/.tflex17/components/ado-64.reg" ] || fail "компоненты не сохранены в префиксе"
  grep -q 'найден T-FLEX CAD: .*/Program Files/T-FLEX CAD 17/Program/TFlexCad.exe' "$HOME/install.out" ||
    fail "установленная программа не обнаружена"
  ls "$HOME/.local/state/tflex17/logs"/install-*.log >/dev/null || fail "нет журнала установки"
  # Временные каталоги удалены, лишнее из архива не распаковывалось.
  [ -z "$(find "$HOME/.cache/tflex17" -mindepth 1 -maxdepth 1 -name 'tmp.*')" ] || fail "временный каталог не удалён"
  # Вне XDG-каталогов в HOME ничего не создано.
  [ "$(cd "$HOME" && find . -mindepth 1 -maxdepth 1 | LC_ALL=C sort | tr '\n' ' ')" = "./.cache ./.local ./install.out ./mock.log " ] ||
    fail "лишние файлы в HOME: $(cd "$HOME" && ls -A)"
}

t_reinstall_idempotent() {
  fresh
  install_ok
  : >"$MOCK_LOG"
  # Повторно: без архива компонентов — шаги «до» выполнены, копия «после» сохранена.
  tflex17-install "$MSI" >"$HOME/re.out" 2>&1 || fail "повторная установка не удалась: $(cat "$HOME/re.out")"
  assert_count 0 '[wineboot]'
  assert_count 0 'winetricks ['
  assert_count 0 'vc_redist'
  assert_count 0 'Setup_TSC2.msi'
  assert_count 1 'T-FLEX CAD 17.msi] [/l*v]'
  assert_count 1 'file=ado-32.reg'
  assert_count 1 'file=ado-64.reg'
  grep -q 'уже выполнен — пропускаю' "$HOME/re.out" || fail "нет сообщения о пропуске шагов"
}

t_deps_commands() {
  fresh
  expect_fail 'нужны компоненты поддержки' tflex17-deps
  tflex17-deps --prefix-only >/dev/null 2>&1 || fail "--prefix-only не создал префикс"
  grep -q '#arch=win64' "$PFX/system.reg" || fail "нет префикса после --prefix-only"
  assert_count 0 'winetricks ['
  # Только winetricks — архив не нужен.
  tflex17-deps --only winetricks >/dev/null 2>&1 || fail "--only winetricks не сработал"
  assert_count 1 '[dotnet48]'
  tflex17-deps --only winetricks >/dev/null 2>&1
  assert_count 1 '[dotnet48]'
  tflex17-deps --only winetricks --force >/dev/null 2>&1
  assert_count 2 '[dotnet48]'
  expect_fail 'неизвестный шаг' tflex17-deps --only nosuchstep
  # Все шаги из каталога компонентов (не ZIP) с пробелами в пути.
  TFLEX_PREREQS="$FX/prereqs" tflex17-deps >/dev/null 2>&1 || fail "tflex17-deps с каталогом не сработал"
  tflex17-deps --list | grep -q 'ado-reg' || fail "--list без шагов"
  if tflex17-deps --list | grep -q 'не выполнен'; then fail "после deps остались невыполненные шаги"; fi
  assert_count 1 '[wineboot]'
}

t_launcher() {
  fresh
  expect_fail 'не установлен' tflex17
  install_ok
  : >"$MOCK_LOG"
  tflex17 || fail "запуск не удался"
  grep -qF "run TFlexCad.exe PWD=$PFX/drive_c/Program Files/T-FLEX CAD 17/Program MESA_GL=<unset> MESA_GLSL=<unset> COMPAT=true CTYPE=ru_RU.UTF-8 ALL=<unset> ARCHIVE=ok" "$MOCK_LOG" ||
    fail "TFlexCad.exe запущен не из каталога программы, с MESA_*, без force_compat_shaders или русской LC_CTYPE: $(cat "$MOCK_LOG")"
  grep -qF 'T-FLEX CAD 3D 17\Rus\Profiles\[Current]\Options /v USED_COMMON_3D_IMPORT_MULTIPROCESS' "$PFX/user.reg" ||
    fail "не записан USED_COMMON_3D_IMPORT_MULTIPROCESS"
  : >"$MOCK_LOG"
  LC_ALL=C.UTF-8 tflex17
  grep -qF 'CTYPE=ru_RU.UTF-8 ALL=<unset>' "$MOCK_LOG" || fail "LC_ALL не снят: $(cat "$MOCK_LOG")"
  : >"$MOCK_LOG"
  TFLEX_LC_CTYPE='' tflex17
  grep -qF 'CTYPE=<unset> ALL=<unset> ARCHIVE=missing' "$MOCK_LOG" || fail "пустая TFLEX_LC_CTYPE не отключила локаль: $(cat "$MOCK_LOG")"
  : >"$MOCK_LOG"
  TFLEX_MESA_OVERRIDE=1 tflex17
  grep -q 'MESA_GL=3.2 MESA_GLSL=330' "$MOCK_LOG" || fail "TFLEX_MESA_OVERRIDE не сработал: $(cat "$MOCK_LOG")"
  cfg=("$PFX"/drive_c/users/*/AppData/Local/'Top Systems/T-FLEX CAD 3D 17/Rus/Profiles/[Current]/Configuration/configuration.xml')
  [ ! -e "${cfg[0]}" ] || fail "без TFLEX_RENDER создан configuration.xml"
  TFLEX_RENDER=gl1 tflex17
  cfg=("$PFX"/drive_c/users/*/AppData/Local/'Top Systems/T-FLEX CAD 3D 17/Rus/Profiles/[Current]/Configuration/configuration.xml')
  grep -q '<RenderOptions ActiveDevice="0"/>' "${cfg[0]}" || fail "TFLEX_RENDER=gl1: не создан configuration.xml с GL1"
  printf '<Settings><RenderOptions><RenderOptions ActiveDevice="0" MSAA="8"/></RenderOptions></Settings>\n' >"${cfg[0]}"
  TFLEX_RENDER=gl3 tflex17
  grep -qF '<RenderOptions ActiveDevice="1" MSAA="8"/>' "${cfg[0]}" || fail "TFLEX_RENDER=gl3 не сработал"
  TFLEX_RENDER=keep tflex17
  tflex17
  grep -qF 'ActiveDevice="1"' "${cfg[0]}" || fail "TFLEX_RENDER=keep или запуск без него изменил настройку"
  expect_fail 'TFLEX_RENDER: gl1' env TFLEX_RENDER=dx tflex17
  TFLEX_DPI=144 tflex17
  grep -qF 'Control Panel\Desktop /v LogPixels /t REG_DWORD /d 144' "$PFX/user.reg" || fail "TFLEX_DPI не записан"
  expect_fail 'TFLEX_DPI должен быть' env TFLEX_DPI=huge tflex17
  expect_fail 'TFLEX_DPI должен быть' env TFLEX_DPI=1000 tflex17
  # Учебная версия: настройки — под ключом «T-FLEX CAD ST 17», а не «3D 17».
  sed -i 's/T-FLEX CAD 3D 17/T-FLEX CAD ST 17/' "$PFX/system.reg"
  TFLEX_RENDER=gl1 tflex17
  grep -qF 'T-FLEX CAD ST 17\Rus\Profiles\[Current]\Options /v USED_COMMON_3D_IMPORT_MULTIPROCESS' "$PFX/user.reg" ||
    fail "USED_COMMON_3D_IMPORT_MULTIPROCESS не записан в ключ учебной версии"
  cfg=("$PFX"/drive_c/users/*/AppData/Local/'Top Systems/T-FLEX CAD ST 17/Rus/Profiles/[Current]/Configuration/configuration.xml')
  [ -f "${cfg[0]}" ] || fail "TFLEX_RENDER: не создан профиль учебной версии"
}

t_launcher_files() {
  fresh
  install_ok
  : >"$MOCK_LOG"
  (cd "$FX/docs dir" && tflex17 "My Drawing.grb") || fail "открытие файла не удалось"
  grep -qF "[start] [/ProgIDOpen] [TFLEX.Document] [Z:\\" "$MOCK_LOG" || fail "файл не открыт через TFLEX.Document"
  grep -qF 'docs dir\My Drawing.grb]' "$MOCK_LOG" || fail "путь к файлу с пробелами искажён"
  assert_count 0 'run TFlexCad.exe'
  # Тип документа не зарегистрирован — файл передаётся программе.
  : >"$MOCK_LOG"
  MOCK_NO_PROGID=1 tflex17 "$FX/docs dir/My Drawing.grb"
  grep -qF "TFlexCad.exe] [Z:\\" "$MOCK_LOG" || fail "нет запасного пути открытия файла"
  # Аргумент, не являющийся файлом, передаётся как есть.
  : >"$MOCK_LOG"
  tflex17 /SomeOption
  grep -qF 'TFlexCad.exe] [/SomeOption]' "$MOCK_LOG" || fail "аргумент не передан программе"
}

t_virtual_desktop() {
  fresh
  install_ok
  : >"$MOCK_LOG"
  TFLEX_VIRTUAL_DESKTOP=1920x1080 tflex17
  grep -qF "[explorer] [/desktop=TFLEX17,1920x1080] [Z:\\" "$MOCK_LOG" || fail "виртуальный рабочий стол не задан"
  expect_fail 'ШИРИНАxВЫСОТА' env TFLEX_VIRTUAL_DESKTOP='1920x1080; rm -rf ~' tflex17
}

t_quiet() {
  fresh
  tflex17-install --quiet --prereqs "$ZIP_PRE" "$MSI" >"$HOME/out" 2>&1 || fail "тихая установка не удалась: $(cat "$HOME/out")"
  grep -qF 'T-FLEX CAD 17.msi] [/l*v]' "$MOCK_LOG" || fail "нет вызова msiexec"
  grep -qE 'T-FLEX CAD 17\.msi\] \[/l\*v\] \[[^]]*\] \[/qn\]' "$MOCK_LOG" || fail "нет /qn"
  expect_fail 'только для .msi' tflex17-install --quiet "$FX/prereqs/Components/vc_redist.x64.exe"
}

t_zip_installer() {
  fresh
  tflex17-install --prereqs "$ZIP_PRE" "$FX/downloads dir/T-FLEX CAD 17.zip" >"$HOME/out" 2>&1 ||
    fail "установка из ZIP не удалась: $(cat "$HOME/out")"
  [ -f "$PFX/drive_c/Program Files/T-FLEX CAD 17/Program/TFlexCad.exe" ] || fail "программа не установлена"
  [ -z "$(find "$HOME/.cache/tflex17" -mindepth 1 -maxdepth 1 -name 'tmp.*')" ] || fail "распакованный дистрибутив не удалён"
  # Архив без установщика — ошибка до создания префикса и установки компонентов.
  fresh
  (cd "$FX/downloads dir" && zip -q "$HOME/empty.zip" readme.txt)
  expect_fail 'нет установщика' tflex17-install --prereqs "$ZIP_PRE" "$HOME/empty.zip"
  [ ! -e "$PFX/system.reg" ] || fail "префикс создан до проверки архива"
  [ -z "$(find "$HOME/.cache/tflex17" -mindepth 1 -maxdepth 1 -name 'tmp.*')" ] || fail "временный каталог не удалён после ошибки"
}

t_pack_installer() {
  fresh
  local pack="$FX/downloads dir/TFCAD_ST_17x64_PACK.zip"
  tflex17-install --prereqs "$ZIP_PRE" "$pack" >"$HOME/out" 2>&1 ||
    fail "установка пакета не удалась: $(cat "$HOME/out")"
  # Имена из CP866 дошли до msiexec в UTF-8, без «?».
  local m l a
  m="$(line_of 'T-FLEX CAD Учебная Версия 17.msi] [/l*v]')"
  l="$(line_of 'Стандартные элементы 17.msi] [/l*v]')"
  a="$(line_of 'file=ado-32.reg')"
  [ "$m" -lt "$l" ] || fail "библиотека поставлена раньше T-FLEX CAD"
  [ "$l" -lt "$a" ] || fail "шаги после установки выполнены раньше библиотеки"
  assert_count 0 'grdcontrol'
  assert_count 0 'Setup.exe'
  assert_count 0 '?'
  [ -f "$PFX/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program/TFlexCad.exe" ] || fail "программа не установлена"
  # Из пакета распаковано только нужное, временный каталог удалён.
  [ -z "$(find "$HOME/.cache/tflex17" -mindepth 1 -maxdepth 1 -name 'tmp.*')" ] || fail "временный каталог не удалён"

  fresh
  tflex17-install --main-only --prereqs "$ZIP_PRE" "$pack" >"$HOME/out" 2>&1 ||
    fail "--main-only не сработал: $(cat "$HOME/out")"
  assert_count 1 'T-FLEX CAD Учебная Версия 17.msi] [/l*v]'
  assert_count 0 'Стандартные элементы'
}

t_pack_extra_failure() {
  fresh
  expect_fail 'T-FLEX CAD установлен, но не установились: Стандартные элементы 17.msi' \
    tflex17-install --prereqs "$ZIP_PRE" "$FX/downloads dir/pack-badlib.zip"
  # Главная программа на месте, шаги после установки выполнены.
  [ -f "$PFX/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program/TFlexCad.exe" ] || fail "программа не установлена"
  assert_count 1 'file=ado-32.reg'
}

t_foreign_dir() {
  fresh
  export TFLEX_WINEPREFIX="$HOME/Мои документы"
  mkdir -p "$TFLEX_WINEPREFIX"
  echo important >"$TFLEX_WINEPREFIX/diploma.grb"
  local before
  before="$(snapshot "$TFLEX_WINEPREFIX")"
  expect_fail 'не Wine-префикс' tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  expect_fail 'не Wine-префикс' tflex17-deps --prereqs "$ZIP_PRE"
  expect_fail 'не Wine-префикс; переименовывать' tflex17-install --reset-prefix --yes --prereqs "$ZIP_PRE" "$MSI"
  [ "$(snapshot "$TFLEX_WINEPREFIX")" = "$before" ] || fail "чужой каталог изменён"
  [ ! -e "$TFLEX_WINEPREFIX/.tflex17" ] || fail "в чужом каталоге создан .tflex17"
}

t_win32_prefix() {
  fresh
  export TFLEX_WINEPREFIX="$HOME/old prefix"
  mkdir -p "$TFLEX_WINEPREFIX/drive_c"
  printf 'WINE REGISTRY Version 2\n#arch=win32\n' >"$TFLEX_WINEPREFIX/system.reg"
  local before
  before="$(snapshot "$TFLEX_WINEPREFIX")"
  expect_fail '32-битный' tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  expect_fail '32-битный' tflex17-doctor
  [ "$(snapshot "$TFLEX_WINEPREFIX")" = "$before" ] || fail "32-битный префикс изменён"
}

t_broken_prefix() {
  fresh
  mkdir -p "$PFX"
  printf 'WINE REGISTRY Version 2\n' >"$PFX/system.reg"
  expect_fail 'повреждён' tflex17-install --prereqs "$ZIP_PRE" "$MSI"
}

t_reset_prefix() {
  fresh
  install_ok
  mkdir -p "$PFX/drive_c/users"
  echo "user data" >"$PFX/drive_c/users/notes.txt"
  # Без терминала и без --yes — отказ, префикс цел.
  expect_fail 'требует подтверждения' tflex17-install --reset-prefix --prereqs "$ZIP_PRE" "$MSI" </dev/null
  [ -f "$PFX/drive_c/users/notes.txt" ] || fail "префикс изменён без подтверждения"
  tflex17-install --reset-prefix --yes --prereqs "$ZIP_PRE" "$MSI" >"$HOME/out" 2>&1 ||
    fail "сброс не удался: $(cat "$HOME/out")"
  local backups=("$PFX".bak-*)
  [ "${#backups[@]}" = 1 ] || fail "резервных копий: ${#backups[@]}"
  [ -d "${backups[0]}" ] || fail "нет резервной копии префикса"
  [ "$(cat "${backups[0]}/drive_c/users/notes.txt")" = "user data" ] || fail "данные старого префикса потеряны"
  [ ! -e "$PFX/drive_c/users/notes.txt" ] || fail "новый префикс не чистый"
  assert_count 2 '[wineboot]'
}

t_interrupted_init() {
  fresh
  mkdir -p "$PFX/.tflex17" "$PFX/drive_c"
  printf 'WINE REGISTRY Version 2\n#arch=win64\n' >"$PFX/system.reg"
  : >"$PFX/.tflex17/prefix.creating"
  install_ok
  grep -q 'прошлая инициализация префикса не завершилась' "$HOME/install.out" || fail "нет предупреждения"
  [ -f "$PFX/.tflex17/prefix.ok" ] || fail "нет отметки prefix.ok"
  [ ! -e "$PFX/.tflex17/prefix.creating" ] || fail "осталась отметка prefix.creating"
}

t_adopted_prefix() {
  fresh
  mkdir -p "$PFX/drive_c"
  printf 'WINE REGISTRY Version 2\n#arch=win64\n' >"$PFX/system.reg"
  install_ok
  grep -q 'создан не T-FLEX-Nix' "$HOME/install.out" || fail "нет предупреждения о чужом префиксе"
  assert_count 0 '[wineboot]'
}

t_wineboot_failure() {
  fresh
  MOCK_WINEBOOT_FAIL=1 expect_fail 'wineboot не смог создать префикс' tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  [ -f "$PFX/.tflex17/prefix.creating" ] || fail "нет отметки незавершённой инициализации"
  MOCK_WINEBOOT_ARCH=win32 expect_fail 'не стал 64-битным' tflex17-deps --prefix-only
}

t_lock() {
  fresh
  install_ok
  # Блокировку держит процесс, который сам завершится через 5 секунд
  # (дочерний sleep наследует дескриптор, поэтому kill flock её не снял бы).
  flock "$PFX/.tflex17/lock" sleep 5 &
  local holder=$!
  sleep 0.5
  expect_fail 'уже работает другая команда' tflex17-install "$MSI"
  expect_fail 'идёт установка' tflex17
  wait "$holder"
  tflex17 || fail "запуск после снятия блокировки не удался"
}

t_installer_failure() {
  fresh
  expect_fail 'неустранимая ошибка установки' tflex17-install --prereqs "$ZIP_PRE" "$FX/downloads dir/broken.msi"
  assert_count 0 'file=ado-32.reg'
  [ ! -e "$PFX/.tflex17/steps/ado-reg.done" ] || fail "шаги после установки выполнены после ошибки"
}

t_winetricks_failure() {
  fresh
  MOCK_WINETRICKS_FAIL=vcrun2019 expect_fail 'winetricks vcrun2019 завершился с ошибкой' \
    tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  [ ! -e "$PFX/.tflex17/steps/winetricks.done" ] || fail "неудачный шаг отмечен выполненным"
  install_ok
  [ -f "$PFX/.tflex17/steps/winetricks.done" ] || fail "шаг не выполнен после исправления"
}

# Без сети шрифт Tahoma не ставится, но установка не прерывается, а шаг
# повторяется при следующем tflex17-deps.
t_tahoma_failure() {
  fresh
  MOCK_WINETRICKS_FAIL=tahoma tflex17-install --prereqs "$ZIP_PRE" "$MSI" >"$HOME/install.out" 2>&1 ||
    fail "установка прервана из-за шрифта: $(tail -n 5 "$HOME/install.out")"
  grep -q 'winetricks tahoma завершился с ошибкой' "$HOME/install.out" || fail "нет предупреждения о шрифте"
  [ ! -e "$PFX/.tflex17/steps/tahoma.done" ] || fail "неудачный шаг tahoma отмечен выполненным"
  [ -f "$PFX/.tflex17/steps/vcredist.done" ] || fail "шаги после tahoma не выполнены"
  tflex17-deps --list | grep -qE 'tahoma +не выполнен' || fail "tahoma не в списке невыполненных"
  tflex17-deps >/dev/null 2>&1 || fail "повтор tflex17-deps не удался"
  [ -f "$PFX/.tflex17/steps/tahoma.done" ] || fail "tahoma не выполнен при повторе"
}

t_module_installer() {
  # Модули и библиотеки ставятся той же командой; без T-FLEX CAD — понятная ошибка.
  fresh
  msi "$HOME/T-FLEX Gears 17.msi" ""
  expect_fail 'TFlexCad.exe .* не найден' tflex17-install --prereqs "$ZIP_PRE" "$HOME/T-FLEX Gears 17.msi"
  install_ok
  tflex17-install "$HOME/T-FLEX Gears 17.msi" >/dev/null 2>&1 || fail "модуль не установился поверх T-FLEX CAD"
}

t_several_products() {
  fresh
  install_ok
  tflex17-install "$FX/downloads dir/T-FLEX CAD Учебная Версия 17.msi" >/dev/null 2>&1
  : >"$MOCK_LOG"
  tflex17 2>"$HOME/err" || fail "запуск не удался"
  grep -q 'найдено несколько установок' "$HOME/err" || fail "нет сообщения о нескольких установках"
  grep -q 'Program Files/T-FLEX CAD 17/Program' "$MOCK_LOG" || fail "выбрана не первая установка"
  : >"$MOCK_LOG"
  TFLEX_EXE="$PFX/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program/TFlexCad.exe" tflex17
  grep -q 'Учебная Версия 17/Program' "$MOCK_LOG" || fail "TFLEX_EXE не учтён"
}

t_prefix_paths() {
  fresh
  expect_fail 'абсолютным путём' env TFLEX_WINEPREFIX=relative/prefix tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  expect_fail '/nix/store' env TFLEX_WINEPREFIX=/nix/store/abc-prefix tflex17-doctor
  expect_fail 'корень' env TFLEX_WINEPREFIX=/ tflex17
  echo file >"$HOME/a file"
  expect_fail 'не Wine-префикс' env TFLEX_WINEPREFIX="$HOME/a file" tflex17-install --prereqs "$ZIP_PRE" "$MSI"
  # XDG_DATA_HOME и пробелы в пути префикса.
  export XDG_DATA_HOME="$HOME/my data"
  install_ok
  [ -f "$HOME/my data/tflex17/prefix/system.reg" ] || fail "XDG_DATA_HOME не учтён"
}

t_wine_passthrough() {
  fresh
  expect_fail 'не готов' tflex17-winecfg
  expect_fail 'не готов' tflex17-wine regedit
  install_ok
  : >"$MOCK_LOG"
  tflex17-winecfg
  tflex17-wine uninstaller --list
  grep -qF 'wine [winecfg]' "$MOCK_LOG" || fail "winecfg не запущен"
  grep -qF 'wine [uninstaller] [--list]' "$MOCK_LOG" || fail "tflex17-wine не передал аргументы"
  tflex17-wine wineserver -w
  grep -qF 'wineserver [-w]' "$MOCK_LOG" || fail "tflex17-wine wineserver не вызвал wineserver напрямую"
}

t_doctor() {
  fresh
  expect_fail 'префикса нет' tflex17-doctor
  install_ok
  local out rc=0
  out="$(tflex17-doctor 2>&1)" || rc=$?
  grep -q '64-битный Wine-префикс' <<<"$out" || fail "doctor: $out"
  grep -q 'найден: .*TFlexCad.exe' <<<"$out" || fail "doctor не нашёл программу: $out"
  grep -q 'реестр: T-FLEX CAD 17 17.0.0.0' <<<"$out" || fail "doctor не прочитал реестр: $out"
  grep -q 'все компоненты поддержки установлены' <<<"$out" || fail "doctor: $out"
  # В песочнице нет дисплея — это ошибка графики, код 1.
  [ "$rc" = 1 ] || fail "doctor без дисплея: rc=$rc"
  grep -q 'DISPLAY не задан' <<<"$out" || fail "doctor не сообщил об отсутствии дисплея"
  # doctor ничего не меняет.
  local before
  before="$(snapshot "$HOME/.local")"
  tflex17-doctor >/dev/null 2>&1 || :
  [ "$(snapshot "$HOME/.local")" = "$before" ] || fail "doctor изменил файлы"
}

# ------------------------------------------------------------ запуск

make_fixtures
for t in $(declare -F | awk '{print $3}' | grep '^t_'); do
  run "$t"
done

echo
echo "пройдено: $passed, не пройдено: ${#failed[@]}"
[ "${#failed[@]}" -eq 0 ] || {
  echo "не пройдены: ${failed[*]}"
  exit 1
}
