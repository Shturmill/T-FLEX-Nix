# Проверки без Wine-префикса с T-FLEX CAD и без проприетарных файлов.
#
#   package          — сборка настоящего пакета (shellcheck всех команд);
#   scenarios        — сценарии команд на фальшивом Wine (tests/mocks);
#   shellcheck       — скрипты, фальшивый Wine и сами сценарии;
#   safety           — в скриптах нет опасных операций;
#   desktop          — ярлык и тип файлов проходят валидаторы;
#   format           — оформление .nix (nixfmt);
#   module-eval      — programs.tflex17 и services.tflex17-licensing;
#   sentinel-hasplm  — сборка службы HASP из фальшивого архива;
#   vm               — NixOS в виртуальной машине: модули, служба
#                      лицензий (фальшивая) и создание префикса НАСТОЯЩИМ
#                      Wine. Нужен KVM.
#
# Фальшивый Wine проверяет только логику обёрток. Работу T-FLEX CAD эти
# проверки не подтверждают — для этого нужен настоящий дистрибутив
# (см. «Проверка на настоящем дистрибутиве» в README).
{
  pkgs,
  nixpkgs,
  self,
}:

let
  inherit (pkgs) lib runCommand;

  # Служба HASP помечена unfree (как и настоящий архив).
  pkgsUnfree = import nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  mocks = pkgs.callPackage ./mocks { };
  tflexMock = self.lib.mkTflex17 pkgs {
    winePackage = mocks.wine;
    inherit (mocks) winetricks;
  };

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../pkgs
      ../modules
      ../scripts
      ../tests
    ];
  };

  # Архив той же структуры, что HASP_Linux в Prerequisites_T-FLEX_Linux.zip.
  # Бинарники — фальшивые (fake-hasp.c) с FHS-загрузчиком, как у настоящих:
  # autoPatchelf пакета должен их исправить.
  fakePrereqsZip =
    pkgs.runCommandCC "Prerequisites_T-FLEX_Linux.zip"
      {
        nativeBuildInputs = [
          pkgs.zip
          pkgs.patchelf
        ];
      }
      ''
        b=HASP_Linux/aksusbd/bin
        mkdir -p "$b"
        for n in aksusbd_x86_64 hasplmd_x86_64; do
          cc -O2 -Wall -Werror -o "$b/$n" ${./fake-hasp.c}
          patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --remove-rpath "$b/$n"
        done
        echo 'int haspvlib_fake(void) { return 46113; }' > v.c
        cc -shared -fPIC -o HASP_Linux/haspvlib_x86_64_46113.so v.c
        patchelf --remove-rpath HASP_Linux/haspvlib_x86_64_46113.so
        echo template > "$b/ru.17.0.alp"
        cat > "$b/hasp_x86_64.rules" <<'EOF'
        ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0529", ATTRS{idProduct}=="0001", MODE="664", RUN+="/usr/sbin/aksusbd_x86_64 -c $root/aks/hasp/$kernel"
        ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0529", ATTRS{idProduct}=="0003", MODE="666", GROUP="plugdev", ENV{SENTINELHID}="1"
        EOF
        # Лишнее, что пакет брать не должен.
        mkdir -p HASP_Linux/aksusbd/pkg Components
        echo deb > HASP_Linux/aksusbd/pkg/aksusbd_8.31-1_amd64.deb
        echo x > Components/vc_redist.x64.exe
        zip -qr "$out" HASP_Linux Components
      '';

  hasplm = self.lib.mkSentinelHasplm pkgsUnfree { src = fakePrereqsZip; };

  mkSystem =
    extra:
    nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.default
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          nixpkgs.config.allowUnfree = true;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "26.05";
        }
        extra
      ];
    };

  failedAssertions = c: map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);

  plain = (mkSystem { }).config;
  client =
    (mkSystem {
      programs.tflex17 = {
        enable = true;
        dpi = 144;
      };
    }).config;
  licensed =
    (mkSystem {
      services.tflex17-licensing.hasp = {
        enable = true;
        prerequisites = fakePrereqsZip;
        openFirewall = true;
      };
    }).config;
  noPrereqs = (mkSystem { services.tflex17-licensing.hasp.enable = true; }).config;
in
{
  package = self.packages.x86_64-linux.default;

  scenarios =
    runCommand "tflex17-test-scenarios"
      {
        nativeBuildInputs = [
          tflexMock
          pkgs.zip
          pkgs.gawk
          pkgs.util-linux
          pkgs.procps
          # iconv: фикстуры с именами в CP866, как в архивах «Топ Системы»
          pkgs.glibc.bin
        ];
      }
      ''
        bash ${./scenarios.sh}
        touch "$out"
      '';

  shellcheck = runCommand "tflex17-test-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    cd ${src}
    shellcheck -s bash scripts/*.sh tests/*.sh tests/mocks/*.sh
    touch "$out"
  '';

  # Единственное удаление — временный каталог mktemp в tflex_cleanup;
  # нет sudo, нет записи в системные каталоги, нет «|| true».
  safety = runCommand "tflex17-test-safety" { } ''
    cd ${src}/scripts
    fail() { echo "safety: $*" >&2; exit 1; }
    if ! rms="$(grep -nE '(^|[^[:alnum:]_-])rm[[:space:]]' *.sh)"; then rms=""; fi
    [ "$(printf '%s\n' "$rms" | grep -c .)" = 1 ] || fail "ожидалось одно удаление, найдено: $rms"
    printf '%s\n' "$rms" | grep -qF 'rm -rf -- "$TFLEX_TMP"' || fail "удаление не временного каталога: $rms"
    grep -n -B3 'rm -rf -- "$TFLEX_TMP"' lib.sh | grep -qF '"$TFLEX_CACHE"/tmp.????????)' ||
      fail "удаление временного каталога без проверки пути"
    ! grep -nE '(^|[^[:alnum:]_])sudo([^[:alnum:]_]|$)' *.sh || fail "найден sudo"
    ! grep -nE '\|\|[[:space:]]*true' *.sh || fail "найдено «|| true»"
    ! grep -nE '(>|cp|mv|mkdir|ln)[^#]*[[:space:]]"?/(etc|usr|opt|var|bin|lib)/' *.sh ||
      fail "запись в системные каталоги"
    ! grep -nE 'wineserver[[:space:]]+-k' tflex17.sh tflex17-install.sh tflex17-deps.sh || fail "wineserver -k вне сброса префикса"
    ! grep -nE '(curl|wget)[[:space:]]' *.sh || fail "скачивание файлов в скриптах"
    touch "$out"
  '';

  desktop =
    runCommand "tflex17-test-desktop"
      {
        nativeBuildInputs = [
          pkgs.desktop-file-utils
          pkgs.libxml2
          pkgs.shared-mime-info
        ];
      }
      ''
        p=${self.packages.x86_64-linux.default}
        desktop-file-validate "$p/share/applications/tflex17.desktop"
        grep -qx 'Exec=env TFLEX_GUI_ERRORS=1 tflex17 %F' "$p/share/applications/tflex17.desktop"
        grep -qx 'StartupWMClass=tflexcad.exe' "$p/share/applications/tflex17.desktop"
        xmllint --noout "$p/share/mime/packages/tflex17.xml"
        mkdir -p mime/packages
        cp "$p/share/mime/packages/tflex17.xml" mime/packages/
        update-mime-database "$PWD/mime"
        grep -q 'application/x-tflex-grb:\*\.grb' mime/globs2
        for c in ${toString self.packages.x86_64-linux.default.commands}; do
          [ -x "$p/bin/$c" ] || { echo "нет команды $c" >&2; exit 1; }
        done
        touch "$out"
      '';

  format = runCommand "tflex17-test-format" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    cd ${src}
    nixfmt --check $(find . -name '*.nix')
    touch "$out"
  '';

  module-eval =
    let
      rules = licensed.systemd.tmpfiles.rules;
      sysPkgs = map (p: p.name) client.environment.systemPackages;
    in
    assert !(plain.programs.tflex17.enable);
    assert !(lib.elem "tflex17-0.1.0" (map (p: p.name) plain.environment.systemPackages));
    assert lib.elem "tflex17-0.1.0" sysPkgs;
    assert client.hardware.graphics.enable;
    assert client.programs.tflex17.package.passthru.dpi == 144;
    # Активация ничего не устанавливает и не создаёт префикс.
    assert !(lib.any (lib.hasInfix "tflex") (lib.attrNames client.system.activationScripts));
    assert !(client.systemd.user.services ? tflex17);
    assert failedAssertions client == [ ];
    assert failedAssertions licensed == [ ];
    assert lib.length (failedAssertions noPrereqs) == 1;
    assert licensed.systemd.services.hasplmd.serviceConfig.Type == "forking";
    assert lib.hasSuffix "/bin/hasplmd_x86_64 -s"
      licensed.systemd.services.hasplmd.serviceConfig.ExecStart;
    assert lib.elem "aksusbd.service" licensed.systemd.services.hasplmd.requires;
    assert lib.any (lib.hasPrefix "L+ /var/hasplm/haspvlib_x86_64_46113.so ") rules;
    assert lib.any (lib.hasPrefix "L+ /etc/hasplm/templates ") rules;
    assert lib.elem 1947 licensed.networking.firewall.allowedTCPPorts;
    assert lib.elem 1947 licensed.networking.firewall.allowedUDPPorts;
    assert !(plain.systemd.services ? hasplmd);
    pkgs.writeText "tflex17-test-module-eval" ''
      systemPackages: ${toString sysPkgs}
      tmpfiles: ${lib.concatStringsSep "\n" rules}
    '';

  sentinel-hasplm = runCommand "tflex17-test-sentinel-hasplm" { } ''
    set -eu
    p=${hasplm}
    for b in aksusbd_x86_64 hasplmd_x86_64; do
      out1="$("$p/bin/$b" --version)"
      [ "$out1" = "fake $b" ] || { echo "$b не запускается после autoPatchelf: $out1" >&2; exit 1; }
    done
    [ -x "$p/lib/hasplm/haspvlib_x86_64_46113.so" ]
    [ -f "$p/share/hasplm/templates/ru.17.0.alp" ]
    r="$p/lib/udev/rules.d/80-hasp.rules"
    grep -qF "RUN+=\"$p/bin/aksusbd_x86_64 -c" "$r"
    ! grep -q '/usr/sbin' "$r"
    ! grep -q plugdev "$r"
    [ ! -e "$p/share/doc" ] && [ ! -e "$p/lib/hasplm/aksusbd_8.31-1_amd64.deb" ]
    touch "$out"
  '';

  vm = pkgsUnfree.testers.runNixOSTest {
    name = "tflex17-vm";
    nodes.machine = {
      imports = [ self.nixosModules.default ];
      virtualisation.memorySize = 2048;
      programs.tflex17.enable = true;
      services.tflex17-licensing.hasp = {
        enable = true;
        prerequisites = fakePrereqsZip;
      };
      users.users.alice.isNormalUser = true;
    };
    testScript = ''
      machine.wait_for_unit("multi-user.target")

      with subtest("служба лицензий HASP (фальшивые демоны, настоящие юниты модуля)"):
          machine.wait_for_unit("aksusbd.service")
          machine.wait_for_unit("hasplmd.service")
          machine.wait_for_open_port(1947)
          machine.succeed("test -L /var/hasplm/haspvlib_x86_64_46113.so")
          machine.succeed("grep -q aksusbd_x86_64 /etc/udev/rules.d/80-hasp.rules")

      with subtest("ярлык и тип файлов в системе, активация не создала префикс"):
          machine.succeed("test -f /run/current-system/sw/share/applications/tflex17.desktop")
          machine.succeed("grep -q 'application/x-tflex-grb' /run/current-system/sw/share/mime/globs2")
          machine.succeed("test ! -e /home/alice/.local/share/tflex17")

      with subtest("префикс создаёт настоящий Wine"):
          machine.succeed("su - alice -c 'tflex17-deps --prefix-only' >&2")
          machine.succeed("grep -q '^#arch=win64' /home/alice/.local/share/tflex17/prefix/system.reg")
          machine.succeed("test -d /home/alice/.local/share/tflex17/prefix/drive_c/windows/syswow64")
          machine.succeed("test -f /home/alice/.local/share/tflex17/prefix/.tflex17/prefix.ok")
          # winemenubuilder отключён в реестре: Wine не создаёт свои ярлыки.
          machine.succeed("grep -qF '\"winemenubuilder.exe\"=\"\"' /home/alice/.local/share/tflex17/prefix/user.reg")
          machine.succeed("test ! -e /home/alice/.local/share/applications/wine")
          # Повторный запуск не пересоздаёт префикс.
          out = machine.succeed("su - alice -c 'tflex17-deps --prefix-only' 2>&1")
          assert "создаю" not in out, out

      with subtest("doctor видит префикс и службу лицензий"):
          _, out = machine.execute("su - alice -c tflex17-doctor 2>&1")
          print(out)
          assert "64-битный Wine-префикс" in out, out
          assert "Sentinel HASP License Manager отвечает" in out, out
          assert "TFlexCad.exe не найден" in out, out
    '';
  };
}
