# Установка T-FLEX CAD 17 в Wine-префикс: tflex17-install [ПАРАМЕТРЫ] УСТАНОВЩИК

tflex_usage() {
  cat <<'EOF'
Использование: tflex17-install [ПАРАМЕТРЫ] УСТАНОВЩИК

УСТАНОВЩИК — официальный дистрибутив, скачанный самостоятельно:
  «T-FLEX CAD 17.msi», «T-FLEX CAD Учебная Версия 17.msi», архив с сайта
  («T-FLEX CAD 17.zip», «TFCAD_ST_17x64_PACK.zip») или Setup.exe.
  Из архива-пакета сначала ставится T-FLEX CAD, затем остальные продукты
  пакета (библиотеки, учебное пособие); Windows-компоненты из него не
  ставятся — их заменяют шаги tflex17-deps. Той же командой ставятся
  модули, библиотеки T-FLEX CAD 17 и обновления.

Перед первой установкой нужны «Компоненты поддержки T-FLEX PLM 17 (Linux)»
(Prerequisites_T-FLEX_Linux.zip, tflex.ru/downloads). Выполненные шаги
повторно не запускаются; файлы для шагов после установки сохраняются в
префиксе, поэтому для обновлений архив больше не нужен.

Параметры:
  --prereqs ПУТЬ   Prerequisites_T-FLEX_Linux.zip или распакованный каталог
                   (иначе TFLEX_PREREQS, затем ~/Downloads и ~/Загрузки)
  --skip-deps      не устанавливать компоненты поддержки
  --quiet          тихая установка MSI (msiexec /qn): без окон установщика;
                   означает согласие с лицензионным соглашением T-FLEX
  --main-only      из архива-пакета ставить только T-FLEX CAD
  --reset-prefix   переименовать существующий префикс и начать с чистого
                   (ничего не удаляется; спрашивает подтверждение)
  --yes            подтвердить --reset-prefix без вопроса
  -h, --help       эта справка

Префикс: TFLEX_WINEPREFIX (по умолчанию ~/.local/share/tflex17/prefix).
EOF
}

installer=""
prereqs_arg=""
skip_deps=0
quiet=0
main_only=0
reset=0
assume_yes=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help)
      tflex_usage
      exit 0
      ;;
    --prereqs)
      [ "$#" -ge 2 ] || tflex_die "--prereqs: не указан путь" 2
      prereqs_arg="$2"
      shift
      ;;
    --prereqs=*) prereqs_arg="${1#--prereqs=}" ;;
    --skip-deps) skip_deps=1 ;;
    --quiet) quiet=1 ;;
    --main-only) main_only=1 ;;
    --reset-prefix) reset=1 ;;
    --yes) assume_yes=1 ;;
    --)
      shift
      break
      ;;
    -*) tflex_die "неизвестный параметр «$1» (справка: tflex17-install --help)" 2 ;;
    *)
      [ -z "$installer" ] || tflex_die "указано больше одного установщика: «$installer» и «$1»" 2
      installer="$1"
      ;;
  esac
  shift
done
if [ "$#" -gt 0 ]; then
  if [ -n "$installer" ] || [ "$#" -gt 1 ]; then
    tflex_die "указано больше одного установщика" 2
  fi
  installer="$1"
fi
[ -n "$installer" ] || {
  tflex_usage >&2
  tflex_die "не указан установщик T-FLEX CAD 17" 2
}

tflex_init

# 1. Входные файлы — до любых изменений.
[ -e "$installer" ] || tflex_die "нет файла установщика «$installer»"
[ -f "$installer" ] || tflex_die "«$installer» — не файл"
[ -r "$installer" ] || tflex_die "нет прав на чтение «$installer»"
installer="$(realpath -- "$installer")"
kind="$(tflex_file_kind "$installer")"
case "$kind" in
  msi | exe | zip) ;;
  *) tflex_die "«$installer» — не MSI, не EXE и не ZIP; укажите официальный дистрибутив T-FLEX CAD 17" ;;
esac
if [ "$quiet" = 1 ] && [ "$kind" = exe ]; then
  tflex_die "--quiet поддерживается только для .msi" 2
fi

tflex_prefix_guard
tflex_ensure_not_running

prereqs_src=""
if [ "$skip_deps" = 0 ]; then
  if prereqs_src="$(tflex_prereqs_locate "$prereqs_arg")"; then
    # Ошибка в пути — до журнала и любых изменений.
    [ -e "$prereqs_src" ] || tflex_die "нет файла или каталога компонентов «$prereqs_src». $(tflex_prereqs_hint)"
  elif tflex_steps_need_prereqs 0 "${TFLEX_PRE_STEPS[@]}" "${TFLEX_POST_STEPS[@]}"; then
    tflex_die "нужны компоненты поддержки T-FLEX. $(tflex_prereqs_hint)"
  fi
fi

if [ "$reset" = 1 ]; then
  tflex_prefix_reset "$assume_yes"
fi

tflex_start_log install
tflex_log "установщик: $installer"
PREREQS=""
if [ -n "$prereqs_src" ]; then
  tflex_prereqs_open "$prereqs_src"
fi

# Архив дистрибутива распаковывается до долгой установки компонентов,
# чтобы ошибка в нём обнаружилась сразу.
target="$installer"
extras=()
if [ "$kind" = zip ]; then
  tflex_log "распаковываю установщики из архива (нужно до 1,5 ГБ свободного места в $TFLEX_CACHE)…"
  tflex_unpack_installers "$installer"
  target="$TFLEX_MAIN_INSTALLER"
  if [ "$main_only" = 0 ]; then
    extras=("${TFLEX_EXTRA_INSTALLERS[@]}")
  elif [ "${#TFLEX_EXTRA_INSTALLERS[@]}" -gt 0 ]; then
    tflex_log "--main-only: пропускаю ${TFLEX_EXTRA_INSTALLERS[*]##*/}"
  fi
  kind="$(tflex_file_kind "$target")"
fi
if [ "$quiet" = 1 ] && [ "$kind" != msi ]; then
  tflex_die "--quiet поддерживается только для .msi, а в архиве — «${target##*/}»" 2
fi

# 2. Префикс: создать или проверить существующий.
tflex_prefix_ensure

# 3. Компоненты поддержки в порядке официального скрипта.
if [ -n "$PREREQS" ]; then
  tflex_components_save
fi
if [ "$skip_deps" = 0 ]; then
  for step in "${TFLEX_PRE_STEPS[@]}"; do
    tflex_run_step "$step" 0
  done
else
  for step in "${TFLEX_PRE_STEPS[@]}"; do
    tflex_step_done "$step" || tflex_warn "шаг «$step» не выполнен (--skip-deps); T-FLEX CAD может работать неправильно"
  done
fi

# 4. Официальный установщик, затем остальные продукты из пакета.
# tflex_install_msi <файл.msi> — код 0 или 1 (причина в TFLEX_INSTALLER_ERROR).
tflex_install_msi() {
  local msi=$1 msilog args
  msilog="$TFLEX_STATE/logs/msi-$(date +%Y%m%d-%H%M%S)-${msi##*/}.log"
  tflex_log "запускаю «${msi##*/}»; подробный журнал Windows Installer: $msilog"
  args=(/i "$(tflex_winpath "$msi")" /l*v "$(tflex_winpath "$msilog")")
  [ "$quiet" = 0 ] || args+=(/qn)
  tflex_try_installer "${msi##*/}" "0 3010" wine msiexec "${args[@]}"
}

case "$kind" in
  msi)
    tflex_install_msi "$target" || tflex_die "$TFLEX_INSTALLER_ERROR"
    ;;
  exe)
    tflex_warn "в стандартном установщике (Setup.exe) снимите флажок «Компоненты поддержки» — они уже установлены (требование официальной инструкции)"
    tflex_run_installer "${target##*/}" "0 3010" wine "$target"
    ;;
  *) tflex_die "«$target» — не MSI и не EXE" ;;
esac

# Ошибка дополнительного продукта не отменяет установленный T-FLEX CAD:
# шаги после установки всё равно выполняются, а код выхода сообщает о сбое.
failed_extras=()
for extra in "${extras[@]}"; do
  if ! tflex_install_msi "$extra"; then
    tflex_warn "$TFLEX_INSTALLER_ERROR"
    failed_extras+=("${extra##*/}")
  fi
done

# 5. Шаги после установки — заново после каждой установки или обновления,
# как в официальном скрипте.
if tflex_components_saved; then
  for step in "${TFLEX_POST_STEPS[@]}"; do
    tflex_run_step "$step" 1
  done
else
  tflex_warn "компоненты поддержки не установлены (--skip-deps без архива): пропускаю шаги ${TFLEX_POST_STEPS[*]}"
fi

# 6. Поиск установленной программы по файлам префикса.
if ! tflex_select_exe; then
  tflex_die "установщик завершился, но TFlexCad.exe в «$PREFIX/drive_c/Program Files*» не найден. Если ставился модуль или библиотека, сначала установите сам T-FLEX CAD 17."
fi
tflex_log "найден T-FLEX CAD: $TFLEX_EXE_FOUND"

# 7. Ярлык даёт пакет (tflex17.desktop); здесь — только иконка из exe.
tflex_install_icon "$TFLEX_EXE_FOUND"

wineserver -w
if [ "${#failed_extras[@]}" -gt 0 ]; then
  tflex_die "T-FLEX CAD установлен, но не установились: ${failed_extras[*]}. Повторить: tflex17-install «$installer»"
fi
tflex_log "готово. Запуск: tflex17 (или «T-FLEX CAD 17» в меню приложений)."
tflex_log "лицензия: учебной версии ключ не нужен; коммерческой и ознакомительной — см. раздел «Лицензирование» в README."
