# programs.tflex17 — команды T-FLEX CAD 17 и ярлык в системе.
#
# Модуль только кладёт неизменяемые обёртки в environment.systemPackages.
# Никаких действий при активации: nixos-rebuild switch не создаёт
# Wine-префикс и не запускает установщик T-FLEX — это делает сам
# пользователь командой tflex17-install в своём сеансе.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkDefault
    types
    literalExpression
    ;

  cfg = config.programs.tflex17;
in
{
  options.programs.tflex17 = {
    enable = mkEnableOption "T-FLEX CAD 17 через Wine: команды tflex17, tflex17-install, tflex17-doctor и ярлык в меню приложений";

    winePackage = mkOption {
      type = types.package;
      default = pkgs.wineWow64Packages.stagingFull;
      defaultText = literalExpression "pkgs.wineWow64Packages.stagingFull";
      example = literalExpression "pkgs.wineWowPackages.stagingFull";
      description = ''
        Сборка Wine для префикса T-FLEX CAD. По умолчанию — Wine Staging
        в режиме WoW64. Префикс, созданный одной версией Wine, Wine
        другой версии обновляет сам при первом запуске.
      '';
    };

    dpi = mkOption {
      type = types.nullOr (types.ints.between 48 480);
      default = null;
      example = 144;
      description = ''
        DPI интерфейса Wine для T-FLEX CAD (96 = 100 %, 144 = 150 %).
        Задаётся при каждом запуске; на один запуск переопределяется
        переменной `TFLEX_DPI`. Полезно под XWayland, когда композитор
        не масштабирует X11-окна (в Hyprland — `xwayland:force_zero_scaling`).
        null — не менять настройку префикса.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../pkgs/tflex17 { inherit (cfg) winePackage dpi; };
      defaultText = literalExpression "pkgs.callPackage ./pkgs/tflex17 { inherit (config.programs.tflex17) winePackage dpi; }";
      description = "Пакет с командами tflex17*. Обычно задавать не нужно.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Аппаратный OpenGL для Wine (/run/opengl-driver). Сам T-FLEX CAD 17
    # 64-битный, поэтому 32-битные драйверы (enable32Bit) не нужны.
    hardware.graphics.enable = mkDefault true;
  };
}
