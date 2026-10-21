{
  description = "T-FLEX CAD 17 для NixOS через Wine — команды установки и запуска, NixOS-модули. Дистрибутив не входит: его приносит пользователь";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      tflex17 = self.lib.mkTflex17 pkgs { };

      app = name: description: {
        type = "app";
        program = "${tflex17}/bin/${name}";
        meta = { inherit description; };
      };
    in
    {
      lib = {
        # Пакет с другими параметрами: inputs.tflex.lib.mkTflex17 pkgs { dpi = 144; }
        mkTflex17 = pkgs: args: pkgs.callPackage ./pkgs/tflex17 args;

        # Служба Sentinel HASP из официального Prerequisites_T-FLEX_Linux.zip
        # (обычно через модуль services.tflex17-licensing.hasp).
        mkSentinelHasplm = pkgs: args: pkgs.callPackage ./pkgs/sentinel-hasplm args;

        # Архив компонентов, который пользователь сам положил в стор:
        #   nix store add --mode flat ~/Downloads/Prerequisites_T-FLEX_Linux.zip
        #   nix hash file ~/Downloads/Prerequisites_T-FLEX_Linux.zip
        requirePrerequisites =
          pkgs:
          {
            name ? "Prerequisites_T-FLEX_Linux.zip",
            hash,
          }:
          pkgs.requireFile {
            inherit name hash;
            message = ''

              Архив «${name}» не скачивается автоматически и не входит в этот
              репозиторий. Скачайте «Компоненты поддержки T-FLEX PLM 17 (Linux)»
              с https://www.tflex.ru/downloads/ и добавьте файл в стор:

                nix store add --mode flat /путь/к/${name}

              (без --mode flat файл добавится как NAR и путь не совпадёт).
              После nix-collect-garbage команду придётся повторить.
            '';
          };
      };

      packages.${system} = {
        default = tflex17;
        inherit tflex17;
      };

      apps.${system} = {
        default = app "tflex17" "Запустить T-FLEX CAD 17";
        tflex17 = app "tflex17" "Запустить T-FLEX CAD 17";
        install = app "tflex17-install" "Установить T-FLEX CAD 17 из локального дистрибутива";
        deps = app "tflex17-deps" "Установить компоненты поддержки в Wine-префикс";
        doctor = app "tflex17-doctor" "Диагностика Wine, префикса, графики и лицензирования";
        winecfg = app "tflex17-winecfg" "winecfg в префиксе T-FLEX CAD 17";
      };

      overlays.default = final: _prev: {
        tflex17 = final.callPackage ./pkgs/tflex17 { };
      };

      nixosModules = {
        default = {
          imports = [
            ./modules/default.nix
            ./modules/licensing.nix
          ];
        };
        tflex17 = ./modules/default.nix;
        licensing = ./modules/licensing.nix;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.shellcheck
          pkgs.shfmt
          pkgs.nixfmt
        ];
      };

      checks.${system} = import ./tests { inherit pkgs nixpkgs self; };

      formatter.${system} = pkgs.nixfmt;
    };
}
