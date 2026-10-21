# Команды tflex17* — обёртки над Wine для установки и запуска T-FLEX CAD 17.
#
# В /nix/store лежат только неизменяемые части: скрипты, Wine, winetricks,
# ярлык. Wine-префикс с установленным T-FLEX CAD — изменяемые данные
# пользователя, он создаётся при первой установке в
# ${XDG_DATA_HOME:-~/.local/share}/tflex17/prefix (или TFLEX_WINEPREFIX).
# Дистрибутив T-FLEX при сборке не нужен и не скачивается.
#
# Использование:
#   pkgs.callPackage ./pkgs/tflex17 { }
#   pkgs.callPackage ./pkgs/tflex17 { winePackage = pkgs.wineWowPackages.stagingFull; dpi = 144; }
{
  lib,
  callPackage,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  wineWow64Packages,
  winetricks,

  # Wine для префикса. По умолчанию — Wine Staging (как в официальной
  # инструкции) в режиме WoW64: 64-битная сборка, которая запускает и
  # 32-битные установщики компонентов без 32-битных библиотек хоста.
  # Классическая сборка (wineWowPackages) в nixpkgs объявлена устаревшей.
  # Аргумент не называется «wine»: callPackage подставил бы pkgs.wine.
  winePackage ? wineWow64Packages.stagingFull,
  # DPI интерфейса Wine по умолчанию (переменная TFLEX_DPI при запуске
  # главнее); null — не менять настройку префикса.
  dpi ? null,
}:

assert lib.assertMsg (
  dpi == null || (lib.isInt dpi && dpi >= 48 && dpi <= 480)
) "tflex17: dpi должен быть целым числом от 48 до 480";

let
  version = "0.1.0";

  wine = winePackage;
  deps = callPackage ./runtime-deps.nix { inherit wine winetricks; };

  libText = builtins.readFile ../../scripts/lib.sh;

  mkCommand =
    name:
    writeShellApplication {
      inherit name;
      runtimeInputs = deps.${name};
      # Хостовый PATH дописывается только к запуску самого T-FLEX и к
      # tflex17-wine: через него Wine открывает ссылки в браузере хоста
      # (winebrowser → xdg-open). Свои программы в PATH стоят первыми.
      inheritPath = lib.elem name [
        "tflex17"
        "tflex17-wine"
      ];
      runtimeEnv = {
        TFLEX_NIX_VERSION = version;
        TFLEX_WINE_PACKAGE = "${wine}";
        TFLEX_DEFAULT_DPI = if dpi == null then "" else toString dpi;
      };
      text = libText + "\n" + builtins.readFile (../../scripts + "/${name}.sh");
    };

  commandNames = [
    "tflex17"
    "tflex17-install"
    "tflex17-deps"
    "tflex17-winecfg"
    "tflex17-wine"
    "tflex17-doctor"
  ];
  commands = map mkCommand commandNames;

  desktopItem = makeDesktopItem {
    name = "tflex17";
    desktopName = "T-FLEX CAD 17";
    genericName = "Система автоматизированного проектирования";
    comment = "T-FLEX CAD 17 в Wine (T-FLEX-Nix)";
    exec = "env TFLEX_GUI_ERRORS=1 tflex17 %F";
    icon = "tflex17";
    categories = [
      "Graphics"
      "Engineering"
    ];
    keywords = [
      "CAD"
      "САПР"
      "T-FLEX"
    ];
    mimeTypes = [ "application/x-tflex-grb" ];
    # Класс окна Wine — имя exe (как StartupWMClass в официальном ярлыке).
    startupWMClass = "tflexcad.exe";
  };
in
symlinkJoin {
  pname = "tflex17";
  inherit version;
  paths = commands ++ [ desktopItem ];
  postBuild = ''
    install -Dm644 ${./tflex17-mime.xml} "$out/share/mime/packages/tflex17.xml"
  '';

  passthru = {
    inherit wine winetricks dpi;
    commands = commandNames;
  };

  meta = {
    description = "T-FLEX CAD 17 через Wine: установщик в изолированный префикс, запуск, диагностика (дистрибутив приносит пользователь)";
    homepage = "https://github.com/Shturmill/T-FLEX-Nix";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "tflex17";
  };
}
