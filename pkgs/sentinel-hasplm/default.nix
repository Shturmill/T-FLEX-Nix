# Sentinel LDK Runtime (aksusbd + hasplmd) из официального архива
# Prerequisites_T-FLEX_Linux.zip, каталог HASP_Linux.
#
# То же, что делают официальные инструкции «Топ Системы» («Активация и
# обновление ключей T-FLEX PLM на ОС Linux», раздел Sentinel HASP):
#   HASP_Linux/aksusbd/dinst   — ставит aksusbd, hasplmd, udev-правила;
#   haspvlib_*_46113.so        — библиотека поставщика (Top Systems, 46113)
#                                в /var/hasplm.
# dinst на системе без /lib/ld-linux.so.2 (как NixOS) выбирает 64-битные
# варианты *_x86_64 — здесь берутся они. Бинарники связаны только с glibc.
#
# Архив проприетарный: его приносит пользователь (pkgs.requireFile),
# пакет нельзя публиковать в бинарных кэшах.
{
  lib,
  stdenv,
  unzip,
  autoPatchelfHook,

  # Prerequisites_T-FLEX_Linux.zip (store-путь или pkgs.requireFile).
  src,
  # Только метка версии в имени пакета: aksusbd 8.31 — состав архива
  # на апрель 2026 года.
  version ? "8.31",
}:

stdenv.mkDerivation {
  pname = "tflex-sentinel-hasplm";
  inherit version src;

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src" \
      'HASP_Linux/aksusbd/bin/*_x86_64' \
      'HASP_Linux/aksusbd/bin/*.alp' \
      'HASP_Linux/aksusbd/bin/hasp_x86_64.rules' \
      'HASP_Linux/haspvlib_x86_64_46113.so'
    cd HASP_Linux
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    b=aksusbd/bin
    for f in aksusbd_x86_64 hasplmd_x86_64; do
      [ -f "$b/$f" ] || { echo "в архиве нет HASP_Linux/$b/$f" >&2; exit 1; }
      install -Dm755 "$b/$f" "$out/bin/$f"
    done

    # Шаблоны интерфейса Sentinel Admin Control Center (/etc/hasplm/templates).
    install -Dm644 -t "$out/share/hasplm/templates" "$b"/*.alp

    # Библиотека поставщика Top Systems (код 46113) для /var/hasplm.
    v=haspvlib_x86_64_46113.so
    [ -f "$v" ] || { echo "в архиве нет HASP_Linux/$v" >&2; exit 1; }
    install -Dm755 "$v" "$out/lib/hasplm/$v"

    # udev: USB-ключи HASP (0529:0001) и Sentinel HID (0529:0003).
    # Группы plugdev в NixOS нет; доступ даёт MODE="666" того же правила.
    install -Dm644 "$b/hasp_x86_64.rules" "$out/lib/udev/rules.d/80-hasp.rules"
    substituteInPlace "$out/lib/udev/rules.d/80-hasp.rules" \
      --replace-fail '/usr/sbin/aksusbd_x86_64' "$out/bin/aksusbd_x86_64" \
      --replace-quiet 'GROUP="plugdev", ' ""
    runHook postInstall
  '';

  meta = {
    description = "Sentinel LDK Runtime (aksusbd, hasplmd) для ключей T-FLEX CAD из Prerequisites_T-FLEX_Linux.zip";
    homepage = "https://www.tflex.ru/downloads/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    hydraPlatforms = [ ];
    mainProgram = "hasplmd_x86_64";
  };
}
