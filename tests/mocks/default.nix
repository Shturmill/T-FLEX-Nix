# Фальшивые wine, wineserver и winetricks для проверок без Wine и без
# дистрибутива T-FLEX (см. wine.sh). Подставляются в пакет вместо
# настоящих: self.lib.mkTflex17 pkgs { winePackage = mocks.wine; … }.
{
  writeShellApplication,
  symlinkJoin,
  runCommand,
  coreutils,
  gnused,
}:

let
  mk =
    name:
    writeShellApplication {
      inherit name;
      runtimeInputs = [
        coreutils
        gnused
      ];
      text = builtins.readFile (./. + "/${name}.sh");
    };
in
{
  wine = symlinkJoin {
    name = "mock-wine";
    paths = [
      (mk "wine")
      (mk "wineserver")
      # Как в nixpkgs: bin/wine — обёртка, настоящий загрузчик — bin/.wine.
      (runCommand "mock-wine-loader" { } ''
        mkdir -p "$out/bin"
        printf '#!/bin/sh\nexit 0\n' > "$out/bin/.wine"
        chmod +x "$out/bin/.wine"
      '')
    ];
  };
  winetricks = mk "winetricks";
}
