# services.tflex17-licensing — системные компоненты лицензирования T-FLEX.
#
# Ключи T-FLEX CAD (коммерческая и ознакомительная лицензии) бывают двух
# технологий: Sentinel HASP и Guardant. T-FLEX CAD внутри Wine обращается
# к службе лицензий хоста (HASP — http://localhost:1947), поэтому служба
# ставится в систему, а не в Wine-префикс.
#
# Здесь реализован только Sentinel HASP — по схеме официальной инструкции
# «Активация и обновление ключей T-FLEX PLM на ОС Linux»: aksusbd +
# hasplmd + библиотека поставщика в /var/hasplm + udev-правила.
# Guardant Control Center не реализован: где служба хранит активированные
# программные ключи, по документации установить не удалось (см. README).
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
    types
    literalExpression
    ;

  cfg = config.services.tflex17-licensing.hasp;
  pkg = cfg.package;

  # Номер поставщика Top Systems в Sentinel LDK (из официальной инструкции).
  vendorLib = "haspvlib_x86_64_46113.so";
in
{
  options.services.tflex17-licensing.hasp = {
    enable = mkEnableOption ''
      Sentinel HASP License Manager (aksusbd, hasplmd) для аппаратных,
      программных и сетевых ключей HASP T-FLEX. Учебной версии не нужен.
      Экспериментально: пакет собирается из официального архива, но с
      настоящим ключом в T-FLEX-Nix не проверялся'';

    prerequisites = mkOption {
      type = types.nullOr (types.either types.package types.path);
      default = null;
      example = literalExpression ''
        inputs.tflex.lib.requirePrerequisites pkgs {
          hash = "sha256-…"; # nix hash file Prerequisites_T-FLEX_Linux.zip
        }
      '';
      description = ''
        Официальный архив Prerequisites_T-FLEX_Linux.zip
        (tflex.ru/downloads, «Компоненты поддержки T-FLEX PLM 17 (Linux)»),
        из которого берутся aksusbd и hasplmd. Архив проприетарный: его
        скачивает и добавляет в стор сам пользователь
        (`nix store add --mode flat …`).
      '';
    };

    package = mkOption {
      type = types.nullOr types.package;
      default =
        if cfg.prerequisites == null then
          null
        else
          pkgs.callPackage ../pkgs/sentinel-hasplm { src = cfg.prerequisites; };
      defaultText = literalExpression "pkgs.callPackage ./pkgs/sentinel-hasplm { src = config.services.tflex17-licensing.hasp.prerequisites; }";
      description = "Пакет Sentinel LDK Runtime (по умолчанию собирается из prerequisites).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Открыть порт 1947 (TCP и UDP). Нужно, только если этот компьютер
        раздаёт сетевую лицензию другим или к его Sentinel Admin Control
        Center подключаются по сети. Клиенту сетевой лицензии порт
        открывать не нужно.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "services.tflex17-licensing.hasp: укажите prerequisites — архив Prerequisites_T-FLEX_Linux.zip";
      }
    ];

    services.udev.packages = [ pkg ];

    # hasplmd ищет библиотеки поставщиков в /var/hasplm, шаблоны
    # интерфейса — в /etc/hasplm/templates. Настройки (/etc/hasplm/hasplm.ini)
    # служба пишет сама из Admin Control Center, поэтому файл не
    # управляется модулем и переживает пересборку системы.
    systemd.tmpfiles.rules = [
      "d /var/hasplm 0755 root root -"
      "d /etc/hasplm 0755 root root -"
      "L+ /etc/hasplm/templates - - - - ${pkg}/share/hasplm/templates"
      "L+ /var/hasplm/${vendorLib} - - - - ${pkg}/lib/hasplm/${vendorLib}"
    ];

    # Юниты повторяют aksusbd_x86_64.service и hasplmd_x86_64.service из
    # архива (Type=forking, те же связи между службами).
    systemd.services.aksusbd = {
      description = "Sentinel LDK Runtime Environment (aksusbd daemon)";
      before = [ "hasplmd.service" ];
      requires = [ "hasplmd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkg}/bin/aksusbd_x86_64";
      };
    };

    systemd.services.hasplmd = {
      description = "Sentinel LDK Runtime Environment (hasplmd daemon)";
      requires = [ "aksusbd.service" ];
      after = [ "aksusbd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkg}/bin/hasplmd_x86_64 -s";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ 1947 ];
      allowedUDPPorts = [ 1947 ];
    };
  };
}
