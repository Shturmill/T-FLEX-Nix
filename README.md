# T-FLEX-Nix

**T-FLEX CAD 17** («Топ Системы») на NixOS через Wine. Флейк даёт команды
установки и запуска, отдельный Wine-префикс, ярлык в меню, диагностику и
NixOS-модули, включая службу лицензий Sentinel HASP.

> [!IMPORTANT]
> Дистрибутива T-FLEX здесь нет. Установщик и архив компонентов поддержки
> скачайте сами с [tflex.ru/downloads](https://www.tflex.ru/downloads/).
> Флейк их не скачивает и не кладёт в `/nix/store`.

> [!WARNING]
> T-FLEX CAD в Wine работает не идеально. Если что-то не так, запустите
> `tflex17-doctor` и откройте issue.

## Как это работает

Пакет ставит в систему только неизменяемые команды `tflex17*`. Сама
программа ставится официальным установщиком в Wine-префикс в домашнем
каталоге (`~/.local/share/tflex17/prefix`). Порядок установки повторяет
официальную инструкцию «Топ Системы» для Linux и скрипты из
`Prerequisites_T-FLEX_Linux.zip`.

## Что скачать

С [tflex.ru/downloads](https://www.tflex.ru/downloads/), раздел
«T-FLEX CAD 17»:

- **«T-FLEX CAD 17.zip»** — коммерческая и ознакомительная версии. Учебная
  («T-FLEX CAD Учебная Версия 17.msi») выдаётся после регистрации на
  [tflexcad.ru](https://www.tflexcad.ru/download/t-flex-cad-free/);
- **«Компоненты поддержки T-FLEX PLM 17 (Linux)»** —
  `Prerequisites_T-FLEX_Linux.zip` (≈ 500 МБ).

## Попробовать без установки

```sh
nix run github:Shturmill/T-FLEX-Nix#install -- \
  --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip ~/Downloads/"T-FLEX CAD 17.zip"
nix run github:Shturmill/T-FLEX-Nix#tflex17
```

## Установка

### NixOS (flake)

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

| Опция `programs.tflex17` | По умолчанию | Назначение |
| --- | --- | --- |
| `enable` | `false` | команды `tflex17*`, ярлык, тип файлов `.grb`, `hardware.graphics.enable` |
| `winePackage` | `wineWow64Packages.stagingFull` (при 11.7–11.13 — `stableFull`) | сборка Wine |
| `dpi` | `null` | DPI интерфейса Wine (96 = 100 %, 144 = 150 %) |
| `package` | из опций выше | итоговый пакет |

### nix profile / Home Manager

```sh
nix profile install github:Shturmill/T-FLEX-Nix#tflex17
```

```nix
home.packages = [ inputs.tflex.packages.x86_64-linux.default ];
# с параметрами:
home.packages = [ (inputs.tflex.lib.mkTflex17 pkgs { dpi = 144; }) ];
```

Есть оверлей: `nixpkgs.overlays = [ tflex.overlays.default ];` даёт
`pkgs.tflex17`. Без модуля включите `hardware.graphics.enable`. Вне NixOS
OpenGL для Wine из Nix подключайте сами (например, через nixGL).

## Первый запуск

`nixos-rebuild switch` ничего не ставит в Wine. Программу устанавливает сам
пользователь, не root:

```sh
tflex17-install --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip \
  ~/Downloads/"T-FLEX CAD 17.zip"
tflex17                       # или «T-FLEX CAD 17» в меню приложений
tflex17 ~/Чертежи/Вал.grb     # открыть документ
```

Откроется обычное окно Windows Installer: пройдите его до конца. Остальные
шаги идут без вопросов, 10–30 минут. Нужны интернет (winetricks) и около
6 ГБ на диске.

Учебная версия, модули и обновления ставятся той же командой:

```sh
tflex17-install ~/Downloads/"T-FLEX CAD Учебная Версия 17.msi"
tflex17-install ~/Downloads/TFCAD_ST_17x64_PACK.zip
tflex17-install ~/Downloads/"T-FLEX Зубчатые передачи 17.msi"
```

## Решение проблем

```sh
tflex17-doctor                # только читает и показывает, что не так
tflex17-deps --list           # шаги установки и их состояние
tflex17-deps --only tahoma    # повторить один шаг
tflex17-winecfg               # winecfg этого префикса
tflex17-wine regedit          # любая программа Wine в префиксе
```

| Проблема | Что делать |
| --- | --- |
| 3D-окно залито синим | лаунчер задаёт `force_compat_shaders=true`; проверьте, что T-FLEX запущен через `tflex17` |
| Кракозябры («Òåêóùàÿ» вместо «Текущая») | закройте все программы префикса (`tflex17-wine wineserver -k`) и запустите `tflex17` заново |
| Полужирная кириллица наполовину обычная | `tflex17-deps --only tahoma` (нужна сеть) |
| Не видно витков резьбы | нужно устройство 3D GL3: `TFLEX_RENDER=gl3 tflex17` |
| Падение при запуске с Wine 11.7–11.13 | ошибка msxml3 в Wine, используйте другую версию (`programs.tflex17.winePackage`) |
| Окна размыты при дробном масштабе | см. «Hyprland» |
| Меню и диалоги ведут себя странно | `TFLEX_VIRTUAL_DESKTOP=2560x1440 tflex17` |
| Нужно начать заново | `tflex17-install --reset-prefix …`: старый префикс переименуется в `prefix.bak-*`, ничего не удаляется |

Журналы лежат в `~/.local/state/tflex17/logs/`.

### Hyprland

Окна T-FLEX — X11-окна Wine, в Wayland они работают через XWayland. При
дробном масштабе отключите масштабирование XWayland-окон
(`xwayland:force_zero_scaling = true`) и увеличьте интерфейс Wine:
`programs.tflex17.dpi = 144;` или `TFLEX_DPI=144 tflex17`. Класс окон —
`tflexcad.exe`, его можно использовать в правилах окон.

<details>
<summary>Переменные окружения</summary>

| Переменная | Назначение |
| --- | --- |
| `TFLEX_WINEPREFIX` | путь к префиксу (по умолчанию `${XDG_DATA_HOME:-~/.local/share}/tflex17/prefix`) |
| `TFLEX_PREREQS` | путь к `Prerequisites_T-FLEX_Linux.zip` или каталогу |
| `TFLEX_EXE` | явный путь к `TFlexCad.exe`, если продуктов несколько |
| `TFLEX_DPI` | DPI интерфейса Wine (48–480) на этот запуск |
| `TFLEX_VIRTUAL_DESKTOP` | виртуальный рабочий стол Wine, например `1920x1080` |
| `TFLEX_RENDER` | устройство 3D: `gl3` (обычное), `gl1` (совместимое, без шейдеров), `keep` — не менять (по умолчанию) |
| `force_compat_shaders` | параметр Mesa, по умолчанию `true`; `false` — отключить |
| `TFLEX_LC_CTYPE` | `LC_CTYPE` для Wine (по умолчанию `ru_RU.UTF-8`, задаёт кодировку CP1251); пустое значение — не менять |
| `TFLEX_MESA_OVERRIDE` | `1` — задать `MESA_GL_VERSION_OVERRIDE=3.2`, как официальный скрипт (с современным Mesa ломает 3D) |
| `TFLEX_WINEDEBUG` | значение `WINEDEBUG` (по умолчанию `fixme-all`) |

</details>

<details>
<summary>Что делает установщик</summary>

```sh
tflex17-install [--prereqs ПУТЬ] [--skip-deps] [--quiet] [--main-only] [--reset-prefix [--yes]] УСТАНОВЩИК
```

`УСТАНОВЩИК` — архив с сайта (`.zip`), `.msi` или `Setup.exe`. Формат
определяется по содержимому. Из архива ставится главный `.msi`, затем
остальные продукты пакета (`--main-only` — только главный). Если `Setup.exe`
запущен напрямую, снимите в нём флажок «Компоненты поддержки». `--quiet`
ставит MSI без окон и означает согласие с лицензией T-FLEX. Если `--prereqs`
не указан, архив ищется в `TFLEX_PREREQS`, `~/Downloads` и `~/Загрузки`.

1. Проверяются входные файлы и префикс, до любых изменений.
2. Создаётся 64-битный префикс (без Wine Mono, как в официальном скрипте).
3. Ставятся компоненты поддержки:

   | Шаг | Содержимое |
   | --- | --- |
   | `winetricks` | `dotnet48`, `vcrun2019`, `d3dcompiler_47`, `fontsmooth=rgb` |
   | `tahoma` | шрифт Tahoma от Microsoft с полужирным начертанием (нет в официальном скрипте; без сети шаг пропускается и повторяется позже) |
   | `vcredist` | `vc_redist.x86.exe`, `vc_redist.x64.exe` |
   | `accessdb` | Microsoft Access Database Engine 2007 |
   | `tsc2` | TechSmith Screen Codec 2 (видео в справке) |
   | `hasp-driver-reg` | `fake_hasp.reg`: сведения о драйвере HASP в реестре |

4. Запускается официальный установщик T-FLEX CAD.
5. После каждой установки повторяются `system-files` (библиотеки ADO/OLE DB)
   и `ado-reg` (`ado-32.reg`, `ado-64.reg`).
6. Ищется `TFlexCad.exe`, из него извлекается иконка.

Выполненные шаги отмечаются, и повторный запуск их пропускает. Существующий
префикс никогда не пересоздаётся. Чужой каталог, 32-битный или повреждённый
префикс дают ошибку. Одновременные установки запрещены блокировкой.

</details>

<details>
<summary>Запуск: чем отличается от официального скрипта</summary>

Как и `start-t-flex-cad-17.sh`, лаунчер запускает программу из её каталога
и отключает многопроцессный импорт 3D (`USED_COMMON_3D_IMPORT_MULTIPROCESS=0`,
в ключе установленного продукта). Файлы открываются через тип документа
`TFLEX.Document`.

Отличия:

- `MESA_GL_VERSION_OVERRIDE=3.2` не задаётся: с Mesa 26 при нём не
  инициализируется `RenderDeviceGL3`.
- Задаётся `force_compat_shaders=true`. Шейдеры T-FLEX объявлены как
  `#version 460` (core-профиль), но вызывают `texture2D()`, которой в
  core-профиле нет. Драйверы Windows это прощают, Mesa нет, и без
  параметра 3D-окно остаётся синим.
- Задаётся `LC_CTYPE=ru_RU.UTF-8` с архивом локалей из пакета. Иначе Wine
  выбирает кодировку CP1252, и часть надписей T-FLEX превращается в
  кракозябры.
- Ярлыки и ассоциации Wine (winemenubuilder) отключены: пакет ставит свой
  ярлык и тип файлов `*.grb`.

</details>

## Лицензирование

| Вариант | Поддержка |
| --- | --- |
| Учебная версия | ключ не нужен, работает |
| Ознакомительная | 30-дневный пробный режим включается в самой программе |
| Ключ Sentinel HASP (USB, программный, сетевой) | модуль `services.tflex17-licensing.hasp`, **экспериментально** |
| Ключ Guardant | **не реализовано** |

T-FLEX в Wine обращается к службе лицензий **хоста**
(`http://localhost:1947`), поэтому служба HASP ставится в систему. Проект не
обходит и не изменяет проверки лицензий.

<details>
<summary>Sentinel HASP</summary>

Служба (`aksusbd`, `hasplmd`, udev-правила) собирается из **вашего** архива
компонентов:

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

Admin Control Center открывается по адресу `http://localhost:1947`. Там
активируется программный ключ (C2V → письмо на ActivateLicense@TopSystems.ru
→ Apply V2C) и задаётся сетевой сервер (Configuration → Access to Remote
License Managers). В T-FLEX параметры поиска ключа задаются через «? →
Активировать лицензию… → Параметры поиска ключа». Связку проверяли только на
фальшивых демонах, с настоящим ключом её не проверяли.

Guardant не сделан: неизвестно, где `grdcontrold` хранит активированные
ключи. Обходные пути: сетевой ключ Guardant на другом компьютере или
Sentinel HASP.

</details>

## Известные проблемы

- Wine 11.7–11.13: T-FLEX падает при запуске из-за msxml3 (исправлено в
  11.14). На этих версиях модуль сам берёт стабильный Wine.
- Официальная инструкция проверена на Wine Staging 10.9, которого нет в
  nixpkgs. Здесь используется Wine 11.
- Первая установка скачивает `vcrun2019` и `d3dcompiler_47`, потому что
  офлайн-кэш в архиве «Топ Системы» устарел.
- Поддерживается только T-FLEX CAD 17. T-FLEX DOCs и CAD 18 не
  поддерживаются.
- В сеансе XRDP отключите XRandR вручную:
  `tflex17-wine reg add 'HKCU\Software\Wine\X11 Driver' /v UseXRandR /d N /f`.

## Удаление

Уберите модуль или выполните `nix profile remove tflex17`. Данные
пользователя остаются, удалите их вручную, **проверив пути**:

```sh
rm -rf ~/.local/share/tflex17                  # префикс и резервные копии prefix.bak-*
rm -rf ~/.local/state/tflex17 ~/.cache/tflex17
rm -f ~/.local/share/icons/hicolor/*/apps/tflex17.png
```

`/etc/hasplm` и `/var/hasplm` (активированные ключи HASP) тоже удаляются
только вручную.

## Разработка

```sh
nix flake check -L                              # все проверки (VM-тест нужен KVM)
nix build .#checks.x86_64-linux.scenarios -L    # сценарии на фальшивом Wine
nix develop                                     # shellcheck, shfmt, nixfmt
```

Фальшивый Wine (`tests/mocks`) проверяет только логику обёрток, а не сам
T-FLEX CAD.

### Проверка на настоящем дистрибутиве

```sh
export TFLEX_WINEPREFIX=/tmp/tflex-test/prefix  # рабочий префикс не затрагивается
nix run .#install -- --prereqs ~/Downloads/Prerequisites_T-FLEX_Linux.zip \
  ~/Downloads/"T-FLEX CAD 17.zip"
nix run .#doctor
nix run .#tflex17
```

## Источники

- [tflex.ru/downloads](https://www.tflex.ru/downloads/): «Порядок установки
  T-FLEX CAD 17 на ОС Linux в среде Wine», «Активация и обновление ключей
  T-FLEX PLM на ОС Linux», архив `Prerequisites_T-FLEX_Linux.zip`;
- [tflexcad.ru](https://www.tflexcad.ru/download/t-flex-cad-free/):
  «T-FLEX CAD 17. Инструкция по установке в среде Wine в ОС Linux»;
- [1C-Nix](https://github.com/Shturmill/1C-Nix) — архитектурный образец.

## Лицензия

Код — MIT (`LICENSE`). T-FLEX CAD, компоненты поддержки и Sentinel LDK
принадлежат своим правообладателям. Не публикуйте их и собранные из них
пакеты в публичных бинарных кэшах.
