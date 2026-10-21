# Компоненты поддержки T-FLEX CAD 17 в Wine-префиксе:
# tflex17-deps [ПАРАМЕТРЫ] [Prerequisites_T-FLEX_Linux.zip | КАТАЛОГ]

tflex_usage() {
  cat <<'EOF'
Использование: tflex17-deps [ПАРАМЕТРЫ] [Prerequisites_T-FLEX_Linux.zip | КАТАЛОГ]

Создаёт 64-битный Wine-префикс (если его нет) и ставит в него компоненты
поддержки T-FLEX CAD 17 в порядке официального скрипта «Топ Системы».
Выполненные шаги пропускаются, существующий префикс не пересоздаётся.
Обычно отдельный запуск не нужен: tflex17-install вызывает эти шаги сам.
Команда полезна, чтобы доустановить или повторить отдельный шаг.

Параметры:
  --prereqs ПУТЬ   то же, что путь позиционным аргументом
  --only ШАГИ      только указанные шаги, через запятую
  --force          повторить шаги, даже если они уже выполнены
  --list           показать шаги и их состояние
  --prefix-only    только создать или проверить префикс
  -h, --help       эта справка

Шаги до установки T-FLEX CAD:  winetricks vcredist accessdb tsc2 hasp-driver-reg
Шаги после установки:          system-files ado-reg
EOF
}

prereqs_arg=""
only=""
force=0
list=0
prefix_only=0
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
    --only)
      [ "$#" -ge 2 ] || tflex_die "--only: не указаны шаги" 2
      only="$2"
      shift
      ;;
    --only=*) only="${1#--only=}" ;;
    --force) force=1 ;;
    --list) list=1 ;;
    --prefix-only) prefix_only=1 ;;
    -*) tflex_die "неизвестный параметр «$1» (справка: tflex17-deps --help)" 2 ;;
    *)
      [ -z "$prereqs_arg" ] || tflex_die "архив компонентов указан дважды" 2
      prereqs_arg="$1"
      ;;
  esac
  shift
done

tflex_init

all_steps=("${TFLEX_PRE_STEPS[@]}" "${TFLEX_POST_STEPS[@]}")

if [ "$list" = 1 ]; then
  printf 'Префикс: %s (%s)\n' "$PREFIX" "$(tflex_prefix_state)"
  for step in "${all_steps[@]}"; do
    if tflex_step_done "$step"; then
      when="$(cut -d' ' -f1 "$META/steps/$step.done")"
    else
      when="не выполнен"
    fi
    printf '  %-16s %-21s %s\n' "$step" "$when" "$(tflex_step_title "$step")"
  done
  exit 0
fi

steps=()
if [ -n "$only" ]; then
  IFS=, read -r -a requested <<<"$only"
  for step in "${requested[@]}"; do
    tflex_step_title "$step" >/dev/null || tflex_die "неизвестный шаг «$step» (список: tflex17-deps --list)" 2
    steps+=("$step")
  done
else
  steps=("${all_steps[@]}")
fi
[ "$prefix_only" = 0 ] || steps=()

tflex_prefix_guard
tflex_ensure_not_running

prereqs_src=""
if prereqs_src="$(tflex_prereqs_locate "$prereqs_arg")"; then
  # Ошибка в пути — до журнала и любых изменений.
  [ -e "$prereqs_src" ] || tflex_die "нет файла или каталога компонентов «$prereqs_src». $(tflex_prereqs_hint)"
elif [ "${#steps[@]}" -gt 0 ] && tflex_steps_need_prereqs "$force" "${steps[@]}"; then
  tflex_die "нужны компоненты поддержки T-FLEX. $(tflex_prereqs_hint)"
fi

tflex_start_log deps
PREREQS=""
if [ -n "$prereqs_src" ] && [ "${#steps[@]}" -gt 0 ]; then
  tflex_prereqs_open "$prereqs_src"
fi

tflex_prefix_ensure
if [ -n "$PREREQS" ]; then
  tflex_components_save
fi

for step in "${steps[@]}"; do
  tflex_run_step "$step" "$force"
done

wineserver -w
tflex_log "готово: префикс $PREFIX"
