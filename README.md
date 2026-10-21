# T-FLEX-Nix — T-FLEX CAD 17 для NixOS через Wine

T-FLEX-Nix — Nix-флейк, который ставит и запускает **T-FLEX CAD 17**
(Windows-приложение «Топ Системы») на NixOS в Wine: команды установки и
запуска, изолированный Wine-префикс, ярлык в меню приложений, диагностика и
NixOS-модули, включая опциональную службу лицензий Sentinel HASP.

> **Дистрибутива T-FLEX здесь нет и не будет.** Установщик T-FLEX CAD и
> архив компонентов поддержки каждый пользователь скачивает сам с
> [tflex.ru/downloads](https://www.tflex.ru/downloads/). Флейк их не
> скачивает и не кладёт в `/nix/store`: установщик запускается из вашего
> каталога загрузок прямо в Wine-префикс в домашнем каталоге. Подробнее —
> в разделе «Лицензирование».

Порядок установки повторяет официальные материалы «Топ Системы» для Linux:
инструкцию «Порядок установки T-FLEX CAD 17 на ОС Linux в среде Wine» и
скрипты из архива `Prerequisites_T-FLEX_Linux.zip` (менеджер установки
`t-flex-install-rus.sh`, скрипт запуска `start-t-flex-cad-17.sh`). Ниже
везде отмечено, что проверено, а что нет.

## Что проверено, а что нет

| Что | Состояние |
| --- | --- |
| Сборка пакета, shellcheck всех команд | проверено (`nix flake check`) |
| Логика установщика: проверки входных файлов, порядок шагов, повторный запуск, блокировка, пробелы в путях, повреждённый/32-битный/чужой префикс, сброс без удаления | проверено на **фальшивом** Wine (`checks.scenarios`) |
| Создание 64-битного префикса **настоящим** Wine 11 (Staging, WoW64) | проверено в VM (`checks.vm`) |
| NixOS-модули, ярлык, тип файлов `.grb` | проверено (`checks.module-eval`, `checks.desktop`, `checks.vm`) |
| Служба Sentinel HASP: сборка из архива, юниты, udev, файлы в `/var/hasplm` | проверено на **фальшивых** демонах; с настоящим `hasplmd` и ключом — **нет** |
| Полная установка настоящим Wine 11.19 Staging: официальный `Prerequisites_T-FLEX_Linux.zip` (апрель 2026) и `T-FLEX CAD 17.zip` (T-FLEX CAD 17.1.50.0) — все шаги, обнаружение программы, иконка | проверено вручную 17.10.2026 (`--quiet`, под Xvfb): с нуля — 9 мин, повторный запуск — 1 мин без пересоздания префикса, ярлыков Wine в `~/.local/share/applications` не появляется; в CI не повторяется — нужен дистрибутив |
| Запуск T-FLEX CAD 17: главное окно, открытие `.grb` из пути с пробелами и кириллицей, диалог лицензии | проверено вручную тогда же (Xvfb, программный OpenGL llvmpipe) |
| 3D-моделирование, аппаратный OpenGL, работа с ключом, печать, реальный сеанс Hyprland/XWayland, интерактивный (не `--quiet`) установщик | **не проверено** |
| Ключи Guardant | **не реализовано**, см. «Лицензирование» |

## Требования

- `x86_64-linux`;
- Nix с flakes (`experimental-features = nix-command flakes`);
- NixOS — для модулей (`nixosModules`). На другом дистрибутиве команды
  работают через `nix run`/`nix profile`, но OpenGL для Wine из Nix нужно
  подключать самостоятельно (например, nixGL);
- графический сеанс X11 или Wayland с XWayland (Wine-окна T-FLEX — X11);
- видеодрайвер с OpenGL (`hardware.graphics.enable`; модуль включает его сам);
- около 6 ГБ на диске: Wine из nixpkgs (~2,3 ГБ в `/nix/store`), префикс
  с .NET и T-FLEX CAD, временная распаковка дистрибутива (~1 ГБ);
- доступ в интернет при первой установке — для winetricks (официальный шаг
  инструкции; SHA-256 каждого файла зашит в winetricks из nixpkgs). На
  проверочной установке 17.10.2026 офлайн-кэш из архива компонентов покрыл
  .NET Framework 4.0/4.8, а скачаны были `vc_redist.x86/x64.exe` для
  `vcrun2019` (aka.ms, Microsoft) и `d3dcompiler_47.dll`
  (raw.githubusercontent.com/mozilla/fxc2 — так эту DLL Microsoft получает
  сам winetricks; в старом кэше «Топ Системы» она извлекалась из установщика
  Firefox). Другие файлы T-FLEX-Nix из сети не берёт.

## Совместимость

| | |
| --- | --- |
| nixpkgs | `nixos-unstable` (зафиксирован в `flake.lock`; при подключении к своей системе — `inputs.nixpkgs.follows`) |
| Wine по умолчанию | `wineWow64Packages.stagingFull` — Wine Staging 11.x в режиме WoW64 |
| Wine в официальной инструкции | Wine Staging **10.9** (WineHQ, Debian/Ubuntu); на Astra Linux — Wine Staging 9.7 |
| Классический WoW64 | `wineWowPackages.stagingFull` — работает, но в nixpkgs объявлен устаревшим (предупреждение при вычислении) |
| T-FLEX | T-FLEX CAD 17 (коммерческая, ознакомительная, учебная версии); модули и библиотеки 17-й версии ставятся той же командой |
| Окружения | X11; Wayland через XWayland (Hyprland, Sway, GNOME, KDE) |

**Почему не Wine 10.9.** В nixpkgs есть только актуальные версии Wine
(stable 11.0, staging 11.x); точной версии из инструкции нет. Wine Staging
выбран, как и в инструкции. Новый режим WoW64 (одна 64-битная сборка,
32-битные программы — через трансляцию) выбран потому, что классическая
сборка `wineWowPackages` в nixpkgs устарела. Сам T-FLEX CAD 17 64-битный
(`Program Files\T-FLEX CAD 17\Program\TFlexCad.exe`); 32-битные в наборе —
только установщики компонентов (VC++ x86, Access Database Engine) и
32-битная регистрация ADO, им OpenGL не нужен. Если в WoW64 что-то не
работает, переключите Wine (`programs.tflex17.winePackage`, см. ниже) —
префикс обновится сам.

**Почему нет FHS-окружения.** В 1C-Nix FHS-окружение нужно нативным
Linux-бинарникам платформы. У T-FLEX нативных Linux-бинарников нет: Wine из
nixpkgs сам находит свои библиотеки и драйверы OpenGL через
`/run/opengl-driver`, поэтому `buildFHSEnv` здесь был бы лишним.

## Быстрый старт (из локального каталога)

1. Скачайте с [tflex.ru/downloads](https://www.tflex.ru/downloads/) в
   раздел «T-FLEX CAD 17»:
   - **«T-FLEX CAD 17.zip»** (внутри `T-FLEX CAD 17/T-FLEX CAD 17.msi`) —
     коммерческая и ознакомительная версии; учебная версия
     («T-FLEX CAD Учебная Версия 17.msi») выдаётся после регистрации на
     [tflexcad.ru](https://www.tflexcad.ru/download/t-flex-cad-free/);
   - **«Компоненты поддержки T-FLEX PLM 17 (Linux)»** —
     `Prerequisites_T-FLEX_Linux.zip` (≈ 500 МБ).

2. Установите и запустите:

   ```sh
   git clone https://github.com/Shturmill/T-FLEX-Nix && cd T-FLEX-Nix

   nix run .#install -- --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip \
     ~/Downloads/"T-FLEX CAD 17.zip"

   nix run .#tflex17
   nix run .#doctor      # если что-то не так
   ```

   Установщик T-FLEX откроет обычное окно Windows Installer — пройдите его
   до конца (лицензионное соглашение, каталог по умолчанию). Остальные шаги
   идут без вопросов и занимают 10–30 минут (дольше всего — .NET Framework).

Чтобы команды были в PATH без `nix run`:

```sh
nix profile install .#tflex17   # tflex17, tflex17-install, tflex17-doctor, …
```

## Подключение к системному flake

`/etc/nixos/flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tflex.url = "github:Shturmill/T-FLEX-Nix";
    tflex.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, tflex, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        tflex.nixosModules.default
        {
          programs.tflex17.enable = true;
          # programs.tflex17.dpi = 144;   # 150 %, см. «Hyprland»
        }
      ];
    };
  };
}
```

После `sudo nixos-rebuild switch` в системе появятся команды `tflex17*` и
ярлык «T-FLEX CAD 17». Дальше — установка программы от своего пользователя
(не от root):

```sh
tflex17-install --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip \
  ~/Downloads/"T-FLEX CAD 17.zip"
```

> **`nixos-rebuild switch` ничего не устанавливает в Wine.** Модуль кладёт
> в систему только неизменяемые обёртки; у него нет скриптов активации и
> служб, которые создавали бы префикс или запускали установщик. Windows-
> установщик интерактивный, требует графического сеанса пользователя и
> пишет в его домашний каталог — поэтому его запускает сам пользователь
> командой `tflex17-install`. Пересборка системы установленный префикс не
> трогает.

### Опции модуля `programs.tflex17`

| Опция | По умолчанию | Назначение |
| --- | --- | --- |
| `enable` | `false` | команды `tflex17*`, ярлык, тип файлов `.grb`, `hardware.graphics.enable` |
| `winePackage` | `pkgs.wineWow64Packages.stagingFull` | сборка Wine |
| `dpi` | `null` | DPI интерфейса Wine (96 = 100 %, 144 = 150 %) при каждом запуске |
| `package` | собирается из опций выше | итоговый пакет |

### Без NixOS-модуля и без root

Home Manager не обязателен; если он есть:

```nix
home.packages = [ inputs.tflex.packages.x86_64-linux.default ];
# или с параметрами:
home.packages = [ (inputs.tflex.lib.mkTflex17 pkgs { dpi = 144; }) ];
```

На NixOS без модуля проверьте, что включён `hardware.graphics.enable`.
Есть и оверлей: `nixpkgs.overlays = [ tflex.overlays.default ];` → `pkgs.tflex17`.

## Установка T-FLEX CAD 17

```sh
tflex17-install [--prereqs ПУТЬ] [--skip-deps] [--quiet] [--main-only] [--reset-prefix [--yes]] УСТАНОВЩИК
```

`--quiet` — установка MSI без окон (`msiexec /qn`), например для учебных
классов; означает согласие с лицензионным соглашением T-FLEX.

`УСТАНОВЩИК` — локальный путь к одному из официальных форматов:

| Файл | Что делается |
| --- | --- |
| `T-FLEX CAD 17.zip`, `TFCAD_ST_17x64_PACK.zip` и другие архивы с сайта | из архива распаковываются только установщики продуктов: главный `T-FLEX…CAD….msi` ставится первым, остальные `.msi` пакета (например, «Стандартные элементы 17») — после него; `--main-only` — только главный. Каталог «Компоненты поддержки…» (Windows-версии VC++, .NET, драйверов HASP и Guardant) пропускается — в Wine его заменяют шаги ниже. `Setup.exe` берётся, только если `.msi` нет |
| `T-FLEX CAD 17.msi`, `T-FLEX CAD Учебная Версия 17.msi` | `wine msiexec /i …` с подробным журналом Windows Installer |
| `Setup.exe` стандартного установщика | запускается как есть; в нём **снимите флажок «Компоненты поддержки»** (требование официальной инструкции) |

Формат определяется по содержимому файла, а не по расширению. Имена
файлов в архивах «Топ Системы» записаны в кодировке CP866 без признака
UTF-8: `unzip` превратил бы кириллицу в `?`, недопустимый в путях Windows,
поэтому архив дистрибутива распаковывается 7-Zip (`7zz -mcp=866`). Если
дополнительный продукт пакета не установился, T-FLEX CAD остаётся
установленным, шаги после установки выполняются, а команда завершается с
ошибкой и списком неустановленного.

`--prereqs` — архив `Prerequisites_T-FLEX_Linux.zip` или распакованный
каталог. Если не указан: переменная `TFLEX_PREREQS`, затем
`~/Downloads/Prerequisites_T-FLEX_Linux.zip` и `~/Загрузки/…` (так ищет и
официальный менеджер установки).

### Что происходит

1. Проверяются входные файлы и состояние префикса — **до любых изменений**.
   Нет файла, не тот формат, нет архива компонентов, чужой или 32-битный
   каталог — понятная ошибка, ничего не создано.
2. Создаётся 64-битный Wine-префикс (или проверяется существующий).
   Wine Mono не ставится (`mscoree=`, как в официальном скрипте), Wine
   Gecko ставится из пакета Wine.
3. Компоненты поддержки — в порядке `t-flex-install-rus.sh`:

   | Шаг | Содержимое |
   | --- | --- |
   | `winetricks` | `dotnet48`, `vcrun2019`, `d3dcompiler_47`, `fontsmooth=rgb`; офлайн-кэш из архива копируется в `~/.cache/winetricks` |
   | `vcredist` | `vc_redist.x86.exe` и `vc_redist.x64.exe` из архива (`/install /quiet /norestart`) |
   | `accessdb` | Microsoft Access Database Engine 2007 (`/quiet`) |
   | `tsc2` | TechSmith Screen Codec 2 — видео в справке (`msiexec /qn`) |
   | `hasp-driver-reg` | `fake_hasp.reg` из архива: сведения о драйвере Sentinel HASP 8.23 в реестре Wine (ключ обслуживает служба хоста; проверки лицензии не меняются) |

4. Запускается официальный установщик T-FLEX CAD.
5. Шаги после установки (выполняются заново после каждой установки и
   обновления, как в официальном скрипте):

   | Шаг | Содержимое |
   | --- | --- |
   | `system-files` | библиотеки ADO/OLE DB в `Program Files*/Common Files/System` и DLL в `system32` из архива (копируются поверх, ничего не удаляя) |
   | `ado-reg` | `ado-32.reg` — в 32-битный реестр, `ado-64.reg` — в 64-битный |

6. Установленная программа ищется по реальным файлам префикса
   (`Program Files*/<продукт>/Program/TFlexCad.exe`), путь не зашит.
7. Из `TFlexCad.exe` извлекается иконка (icoutils) в
   `~/.local/share/icons/hicolor/*/apps/tflex17.png` — только локально.

Каждый выполненный шаг отмечается в префиксе, повторный запуск его
пропускает. Файлы для шагов после установки сохраняются в префиксе
(`.tflex17/components`, ≈ 15 МБ), поэтому для обновлений и модулей архив
компонентов больше не нужен. Импорт `.reg` проверяется по самому реестру
(`regedit` не сообщает об ошибках кодом завершения). Коды Windows Installer
расшифровываются: 1602 — отменено пользователем, 1603 — ошибка установки и т.д.

### Учебная версия, модули, обновления

```sh
# учебная версия — так же: отдельный MSI или пакет с сайта (с библиотекой
# «Стандартные элементы 17»)
tflex17-install ~/Downloads/"T-FLEX CAD Учебная Версия 17.msi"
tflex17-install ~/Downloads/TFCAD_ST_17x64_PACK.zip

# модули и библиотеки T-FLEX CAD 17, обновление до новой сборки 17-й версии
tflex17-install ~/Downloads/"T-FLEX Зубчатые передачи 17.msi"
tflex17-install ~/Downloads/"T-FLEX CAD 17.zip"
```

Если в префиксе несколько продуктов, запускается первый найденный, а
`tflex17` выводит список; нужный выбирается переменной `TFLEX_EXE`.

### Компоненты отдельно

```sh
tflex17-deps --list                                  # шаги и их состояние
tflex17-deps ~/Downloads/Prerequisites_T-FLEX_Linux.zip   # недостающие шаги
tflex17-deps --only winetricks --force               # повторить шаг
tflex17-deps --prefix-only                           # только создать префикс
```

Доустановка зависимостей не пересоздаёт префикс и не трогает
установленные программы.

## Wine-префикс

| | |
| --- | --- |
| Путь по умолчанию | `${XDG_DATA_HOME:-~/.local/share}/tflex17/prefix` |
| Другой путь | `TFLEX_WINEPREFIX=/путь` (абсолютный; не в `/nix/store`) |
| Разрядность | только `win64` |
| Служебные файлы | `<префикс>/.tflex17/` — отметки шагов, блокировка, копия компонентов |
| Журналы | `${XDG_STATE_HOME:-~/.local/state}/tflex17/logs/` (`install-*.log`, `deps-*.log`, `msi-*.log`) |
| Временные файлы | `${XDG_CACHE_HOME:-~/.cache}/tflex17/tmp.*` — удаляются по завершении |

Префикс — изменяемые данные пользователя, в `/nix/store` его нет.
Существующий префикс никогда не пересоздаётся и не перезаписывается:

- **чужой каталог** (не Wine-префикс, например по ошибке указан `$HOME`) —
  команды отказываются работать и ничего в нём не создают;
- **32-битный или повреждённый** префикс — ошибка с подсказкой;
- **префикс, созданный не T-FLEX-Nix** (например, официальным скриптом в
  `~/.wine`: `TFLEX_WINEPREFIX=~/.wine`) — используется как есть, с
  предупреждением;
- **прерванное создание** — повторный запуск продолжает инициализацию;
- **одновременные установки** в один префикс (по официальной инструкции они
  его ломают) запрещены блокировкой; `tflex17` не запускается, пока идёт
  установка;
- **T-FLEX CAD запущен** — установка отказывается начинаться.

Начать с чистого префикса:

```sh
tflex17-install --reset-prefix ~/Downloads/"T-FLEX CAD 17.zip"
```

Старый префикс **переименовывается** в `prefix.bak-ГГГГММДД-ЧЧММСС`, ничего
не удаляется; команда спрашивает подтверждение (`yes`), без терминала —
только с `--yes`. Удалить резервную копию — вручную, когда она не нужна.

Настройка и утилиты Wine в этом префиксе:

```sh
tflex17-winecfg                      # winecfg
tflex17-wine regedit                 # любая программа Wine
tflex17-wine uninstaller             # удаление Windows-программ из префикса
```

### Переменные окружения

| Переменная | Назначение |
| --- | --- |
| `TFLEX_WINEPREFIX` | путь к префиксу |
| `TFLEX_PREREQS` | путь к `Prerequisites_T-FLEX_Linux.zip` или каталогу |
| `TFLEX_EXE` | явный путь к `TFlexCad.exe`, если установлено несколько продуктов |
| `TFLEX_DPI` | DPI интерфейса Wine (48–480) на этот запуск |
| `TFLEX_VIRTUAL_DESKTOP` | запуск в виртуальном рабочем столе Wine, например `1920x1080` |
| `TFLEX_NO_MESA_OVERRIDE` | `1` — не задавать `MESA_GL_VERSION_OVERRIDE=3.2` и `MESA_GLSL_VERSION_OVERRIDE=330` (их задаёт официальный скрипт запуска) |
| `TFLEX_WINEDEBUG` | значение `WINEDEBUG` (по умолчанию `fixme-all`) |

## Запуск и рабочий стол

```sh
tflex17                       # или «T-FLEX CAD 17» в меню приложений
tflex17 ~/Чертежи/Вал.grb     # открыть документ
```

Как в официальном `start-t-flex-cad-17.sh`: программа запускается из своего
каталога, задаются `MESA_GL_VERSION_OVERRIDE=3.2` и
`MESA_GLSL_VERSION_OVERRIDE=330` (влияют только на драйверы Mesa), в
реестре отключается многопроцессный импорт 3D-моделей
(`USED_COMMON_3D_IMPORT_MULTIPROCESS=0`). Файлы из аргументов открываются
через тип документа `TFLEX.Document` (`wine start /ProgIDOpen`), а если он
не зарегистрирован — передаются `TFlexCad.exe`.

Пакет ставит ярлык `tflex17.desktop` (класс окна `tflexcad.exe`, как в
официальном ярлыке) и тип файлов `application/x-tflex-grb` для `*.grb`,
поэтому документы открываются из файлового менеджера. Ошибки при запуске из
меню показываются окном. Собственные ярлыки и ассоциации Wine
(winemenubuilder) отключены — переменной `WINEDLLOVERRIDES` и в реестре
созданного префикса (установщики под winetricks подменяют переменную): они ссылались бы на пути `/nix/store`, которые
пропадают после сборки мусора, и засоряли бы меню.

## Графика, Wayland и Hyprland

Окна T-FLEX — X11-окна Wine. В Wayland-сеансе они работают через
**XWayland** (нужна переменная `DISPLAY`; `tflex17-doctor` это проверяет).
Модуль не меняет настройки XWayland, OpenGL сверх `hardware.graphics.enable`
и конфигурацию оконного менеджера.

Аппаратное ускорение: `tflex17-doctor` показывает рендерер OpenGL и
предупреждает о программной отрисовке (llvmpipe). Для 3D-окна T-FLEX нужен
нормальный драйвер (`hardware.graphics.enable`; для NVIDIA — проприетарный
драйвер, как требует и официальная инструкция). На старой видеокарте или в
удалённом сеансе включите в T-FLEX «Совместимый графический режим»
(«Установки системы» → «3D» → «Параметры графики») — рекомендация
официальной инструкции.

**Hyprland** (проверялось только окружение, не сам T-FLEX):

- **Дробный масштаб.** XWayland-окна при дробном масштабе размываются.
  Обычное решение — отключить масштабирование XWayland-окон композитором
  (`xwayland:force_zero_scaling = true`) и увеличить интерфейс самого Wine:
  `programs.tflex17.dpi = 144;` (150 %) или `TFLEX_DPI=144 tflex17`.
  Синтаксис конфигурации Hyprland зависит от версии (в 0.55 появилась
  Lua-конфигурация) — сверяйтесь с вики Hyprland своей версии.
- **Правила окон.** Класс окон T-FLEX — `tflexcad.exe` (проверьте:
  `hyprctl clients`). По нему можно задавать правила (плавающие диалоги,
  рабочий стол и т.п.) в синтаксисе вашей версии Hyprland.
- **Всплывающие меню и диалоги** ведут себя неправильно? Попробуйте
  виртуальный рабочий стол Wine: `TFLEX_VIRTUAL_DESKTOP=2560x1440 tflex17` —
  все окна T-FLEX окажутся внутри одного X11-окна.
- Встроенный Wayland-драйвер Wine не используется: при наличии `DISPLAY`
  Wine выбирает X11.

## Лицензирование

| Вариант | Что нужно | Поддержка в T-FLEX-Nix |
| --- | --- | --- |
| **Учебная версия** | бесплатна, ключ не нужен | полностью: `tflex17-install "T-FLEX CAD Учебная Версия 17.msi"` |
| **Ознакомительная** | тот же установщик, что у коммерческой; без ключа T-FLEX CAD 17 предлагает «Начать пробное использование» — 30 дней с первого запуска, продление по запросу в «Топ Системы» (видно в диалоге лицензии; сам пробный режим в T-FLEX-Nix не включался) | установка — полностью; пробный режим включается в самой программе |
| **Коммерческая, ключ Sentinel HASP** (USB или программный) | служба HASP License Manager (aksusbd, hasplmd) на хосте | модуль `services.tflex17-licensing.hasp` — **экспериментально** |
| **Сетевая лицензия HASP** | ключ на сервере в локальной сети; на клиенте — та же служба | тот же модуль; адрес сервера — в Admin Control Center |
| **Ключ Guardant** | Guardant Control Center (`grdcontrol`) и T-FLEX Licensing | **не реализовано** |

T-FLEX CAD в Wine не видит USB-ключи напрямую: Windows-библиотека защиты
внутри Wine обращается к службе лицензий **хоста** (Sentinel HASP —
`http://localhost:1947`). Поэтому служба ставится в систему, а не в
префикс. Проект не обходит и не изменяет проверки лицензий и не
распространяет файлы защиты.

### Sentinel HASP (`services.tflex17-licensing.hasp`)

Схема — из официальной инструкции «Активация и обновление ключей T-FLEX PLM
на ОС Linux»: `aksusbd` + `hasplmd` из `HASP_Linux/aksusbd`, библиотека
поставщика `haspvlib_x86_64_46113.so` в `/var/hasplm`, udev-правила для
USB-ключей. Пакет собирается из **вашего** архива компонентов:

```sh
nix store add --mode flat ~/Downloads/Prerequisites_T-FLEX_Linux.zip
nix hash file ~/Downloads/Prerequisites_T-FLEX_Linux.zip
```

```nix
{ pkgs, inputs, ... }:
{
  nixpkgs.config.allowUnfree = true; # Sentinel LDK — проприетарный
  services.tflex17-licensing.hasp = {
    enable = true;
    prerequisites = inputs.tflex.lib.requirePrerequisites pkgs {
      hash = "sha256-…"; # вывод nix hash file
    };
    # openFirewall = true; # только если этот компьютер раздаёт сетевую лицензию
  };
}
```

После `nixos-rebuild switch` работают службы `aksusbd` и `hasplmd`, Admin
Control Center — `http://localhost:1947`. Активация программного ключа и
обновление — по официальной инструкции через Admin Control Center
(Fingerprint/C2V → письмо на ActivateLicense@TopSystems.ru → Apply V2C).
Сетевой лицензионный сервер указывается там же: Configuration → Access to
Remote License Managers. Файл `/etc/hasplm/hasplm.ini` служба пишет сама,
модуль им не управляет, поэтому настройки переживают пересборку системы.

В T-FLEX CAD параметры поиска ключа задаются командой «? → Активировать
лицензию… → Параметры поиска ключа» (тип ключа, адрес сервера, ID ключа).

**Ограничения.** Пакет собран и проверен на фальшивых демонах (юниты,
udev, файлы); настоящий `hasplmd` в T-FLEX-Nix запускался только с `-h`, с
настоящим ключом связка не проверялась. Сообщите о результате, если
проверите. Если архив компонентов обновится, `nix hash file` даст новый хеш.

### Guardant

Официально для Guardant ставятся `grdcontrol_amd64.deb` (Guardant Control
Center, `/opt/guardant/grdcontrol`) и утилита T-FLEX Licensing. Демон
`grdcontrold` рассчитан на запуск из `/opt/guardant/grdcontrol` с
относительными путями к данным и журналам, а где он хранит активированные
программные ключи, по документации установить не удалось. Без этого
NixOS-служба была бы ненадёжной, поэтому она не сделана. Обходные пути:
сетевой ключ Guardant на другом компьютере или ключ Sentinel HASP.

## Диагностика

```sh
tflex17-doctor
```

Только читает: версии Wine и winetricks, путь и разрядность префикса,
выполненные шаги, найденные `TFlexCad.exe` и записи реестра об установке,
X-сервер (XWayland), рендерер OpenGL, доступность HASP License Manager,
запущенные `wineserver`, последний журнал. Код выхода 1 — найдены ошибки.

| Проблема | Что делать |
| --- | --- |
| `нужны компоненты поддержки` | укажите `--prereqs …/Prerequisites_T-FLEX_Linux.zip` |
| `не Wine-префикс`, `32-битный`, `повреждён` | другой `TFLEX_WINEPREFIX` или `tflex17-install --reset-prefix …` |
| `уже работает другая команда` | дождитесь конца установки; если её нет — остались процессы Wine этого префикса: `tflex17-wine wineserver -k` (завершает их) |
| `winetricks dotnet48 завершился с ошибкой` | журнал из сообщения; нет сети — положите архив компонентов (в нём офлайн-кэш); повтор: `tflex17-deps --only winetricks` |
| Windows Installer: код 1603 | подробный журнал `~/.local/state/tflex17/logs/msi-*.log` |
| Окно чёрное, 3D медленное | `tflex17-doctor` (рендерер), «Совместимый графический режим» в T-FLEX, `TFLEX_NO_MESA_OVERRIDE=1 tflex17` |
| Мелкий или размытый интерфейс | `TFLEX_DPI=144 tflex17`, см. «Hyprland» |
| Меню и диалоги не на месте | `TFLEX_VIRTUAL_DESKTOP=1920x1080 tflex17` |
| Нужен подробный вывод Wine | `TFLEX_WINEDEBUG=+loaddll,err tflex17 2>wine.log` |

## Удаление

Программу — из NixOS-конфигурации (`programs.tflex17.enable = false`) или
`nix profile remove tflex17`. Данные пользователя этим не удаляются; удалите
их вручную, **проверив пути** (особенно если менялся `TFLEX_WINEPREFIX`):

```sh
# префикс: T-FLEX CAD, его настройки и документы внутри префикса,
# а также резервные копии prefix.bak-* после --reset-prefix
rm -rf ~/.local/share/tflex17
# журналы, временные файлы, иконка
rm -rf ~/.local/state/tflex17 ~/.cache/tflex17
rm -f ~/.local/share/icons/hicolor/*/apps/tflex17.png
# кэш winetricks (общий для всех префиксов — удаляйте, если он больше не нужен)
rm -rf ~/.cache/winetricks
```

Удалить из префикса только T-FLEX CAD (оставив компоненты):
`tflex17-wine uninstaller`. Служба HASP удаляется отключением модуля;
`/etc/hasplm` и `/var/hasplm` (активированные ключи!) остаются — удалите
их вручную, если ключи на этом компьютере больше не нужны.

## Ограничения и известные проблемы

- Официально проверен Wine Staging 10.9, которого нет в nixpkgs. На Wine 11.19
  проверены установка и запуск (главное окно, открытие документа, диалог
  лицензии), но не 3D-моделирование, аппаратный OpenGL и работа с ключом.
- Во время установки .NET Framework Wine печатает много строк
  `err:ole:…` — это обычный шум Wine, на результат не влияет.
- В префиксе, созданном не T-FLEX-Nix, winemenubuilder в реестре не
  отключается (префикс используется как есть): установщики под winetricks
  могут создать ярлыки Wine в `~/.local/share/applications`.
- Первая установка требует интернета: с winetricks 20260125 офлайн-кэш из
  архива «Топ Системы» устарел для `vcrun2019` и `d3dcompiler_47`, их
  winetricks скачивает (см. «Требования»). Для установки без сети заранее
  заполните `~/.cache/winetricks` на компьютере с доступом в интернет.
- `fake_hasp.reg` импортируется в оба представления реестра: официальный
  скрипт вызывает `wine regedit`, разрядность которого в разных сборках Wine
  разная.
- Официальный скрипт удаляет `Program Files*/Common Files/System` перед
  копированием; здесь файлы копируются поверх, без удаления.
- Распознаётся только T-FLEX CAD 17 (и продукты с `TFlexCad.exe`); T-FLEX
  DOCs, T-FLEX CAD 18 не поддерживаются.
- Guardant не поддерживается; Sentinel HASP — экспериментально.
- Вне NixOS OpenGL для Wine из Nix не настраивается автоматически.
- Сеанс XRDP: официальный скрипт отключает в нём `UseXRandR` и
  `UseXVidMode`; здесь это не делается автоматически, при необходимости:
  `tflex17-wine reg add 'HKCU\Software\Wine\X11 Driver' /v UseXRandR /d N /f`.

## Как это устроено

```text
flake.nix                      outputs: packages, apps, nixosModules, lib, checks
pkgs/tflex17/default.nix       команды tflex17* (writeShellApplication), ярлык, MIME
pkgs/tflex17/runtime-deps.nix  PATH каждой команды (только пакеты nixpkgs)
pkgs/sentinel-hasplm/          служба HASP из Prerequisites_T-FLEX_Linux.zip
modules/default.nix            programs.tflex17
modules/licensing.nix          services.tflex17-licensing.hasp
scripts/lib.sh                 общая логика: пути, префикс, шаги, поиск программы
scripts/tflex17*.sh            команды
tests/                         проверки, фальшивый Wine, VM-тест
```

- Неизменяемое (скрипты, Wine, winetricks, ярлык) — в `/nix/store`;
  изменяемое (префикс, кэш, журналы) — в XDG-каталогах пользователя.
- Каждая команда — `writeShellApplication`: shellcheck при сборке,
  `errexit`/`nounset`/`pipefail`, PATH только из пакетов nixpkgs. Хостовый
  PATH дописывается в конец лишь у `tflex17` и `tflex17-wine`, чтобы Wine
  мог открыть ссылку в браузере хоста (`winebrowser` → `xdg-open`).
- Аргумент пакета называется `winePackage`, а не `wine`: иначе
  `callPackage` подставил бы `pkgs.wine`.
- Единственное удаление в скриптах — временный каталог, созданный `mktemp`
  в том же запуске (это проверяет `checks.safety`).

## Разработка

```sh
nix flake check -L     # все проверки (VM-тест нужен KVM)
nix build .#checks.x86_64-linux.scenarios -L   # только сценарии
nix develop            # shellcheck, shfmt, nixfmt
nix fmt -- $(git ls-files '*.nix')
```

| Проверка | Что делает |
| --- | --- |
| `package` | сборка пакета с настоящим Wine (shellcheck всех команд) |
| `scenarios` | 30 сценариев команд на фальшивом Wine (`tests/mocks`): отсутствующий дистрибутив, пробелы в путях, ZIP, пакет с именами в CP866 и сбоем дополнительного продукта, порядок шагов, повторная установка, блокировка, ошибки установщика и winetricks, чужой/32-битный/повреждённый префикс, сброс без удаления, открытие файлов, DPI, doctor |
| `shellcheck`, `safety`, `format` | скрипты; нет опасных удалений, `sudo`, записи в системные каталоги, `\|\| true`; nixfmt |
| `desktop` | `desktop-file-validate`, MIME-база для `*.grb` |
| `module-eval` | опции модулей, отсутствие действий при активации, юниты HASP |
| `sentinel-hasplm` | сборка службы HASP из фальшивого архива, autoPatchelf, udev |
| `vm` | NixOS в QEMU: службы HASP (фальшивые демоны), ярлык и MIME в системе, создание префикса **настоящим** Wine, `tflex17-doctor` |

Фальшивый Wine проверяет только логику обёрток. Не выдавайте его за
проверку T-FLEX CAD.

### Проверка на настоящем дистрибутиве

Вручную, в отдельном префиксе (рабочий не затрагивается):

```sh
export TFLEX_WINEPREFIX=/tmp/tflex-test/prefix
nix run .#install -- --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip \
  ~/Downloads/"T-FLEX CAD 17.zip"
nix run .#doctor
nix run .#tflex17
```

Ожидается: все шаги без ошибок, `tflex17-doctor` без `[FAIL]`, окно
T-FLEX CAD с диалогом лицензии (без ключа) или рабочим 3D-окном (учебная
версия). Результаты (версия Wine, видеокарта, окружение) приветствуются в
issues.

## Источники

- [tflex.ru/downloads](https://www.tflex.ru/downloads/): «Порядок установки
  T-FLEX CAD 17 на ОС Linux в среде Wine» (`Installation_Guide_Linux.pdf`,
  ред. 2026), «Активация и обновление ключей T-FLEX PLM на ОС Linux»
  (`Activation_Guide_Linux.pdf`), «Установка и удаление … T-FLEX PLM 17 в
  среде Wine 9.7 (staging) в ОС Astra Linux», архив
  `Prerequisites_T-FLEX_Linux.zip` (скрипты `t-flex-install-rus.sh`,
  `start-t-flex-cad-17.sh`).
- [tflexcad.ru](https://www.tflexcad.ru/download/t-flex-cad-free/):
  «T-FLEX CAD 17. Инструкция по установке в среде Wine в ОС Linux» (2023).
- Англоязычная инструкция с tflex.com при подготовке проекта была
  недоступна (сайт не отвечал); использованы русские документы, они новее.
- [1C-Nix](https://github.com/Shturmill/1C-Nix) — архитектурный образец.

## Лицензирование проекта

Код T-FLEX-Nix — MIT (см. `LICENSE`). T-FLEX CAD, компоненты поддержки и
Sentinel LDK — проприетарные продукты своих правообладателей: не
публикуйте их и собранные из них пакеты (в том числе службу HASP) в
публичных бинарных кэшах. Для использования T-FLEX CAD нужна лицензия
«Топ Системы» (кроме учебной версии на её условиях).
