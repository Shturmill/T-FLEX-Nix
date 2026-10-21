# Программы, которые видят команды tflex17* (их PATH собирается только
# отсюда — хостовые программы не используются, кроме запуска самого
# T-FLEX: см. inheritPath в default.nix).
#
# Wine — Windows-приложение, поэтому FHS-окружение (buildFHSEnv, как в
# 1C-Nix) не нужно: нативных Linux-бинарников T-FLEX нет, а Wine из
# nixpkgs сам находит свои библиотеки и драйверы OpenGL/Vulkan через
# /run/opengl-driver.
{
  wine,
  winetricks,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  util-linux,
  procps,
  unzip,
  icoutils,
  _7zz,
  zenity,
  mesa-demos,
  xdpyinfo,
}:

let
  # flock (util-linux) — блокировка префикса; od/realpath/mktemp — coreutils.
  base = [
    wine
    coreutils
    findutils
    gnugrep
    gnused
    util-linux
    procps
  ];
in
{
  # zenity — окно с ошибкой при запуске из меню приложений.
  tflex17 = base ++ [ zenity ];

  # winetricks ставит .NET/VC++; unzip — архив компонентов; 7-Zip —
  # архив дистрибутива (перекодирует имена CP866, см. lib.sh); icoutils —
  # иконка из установленного TFlexCad.exe.
  tflex17-install = base ++ [
    winetricks
    unzip
    _7zz
    icoutils
  ];

  tflex17-deps = base ++ [
    winetricks
    unzip
  ];

  tflex17-winecfg = base ++ [ zenity ];

  tflex17-wine = base;

  # glxinfo (mesa-demos) и xdpyinfo — проверка OpenGL и X-сервера.
  tflex17-doctor = base ++ [
    winetricks
    gawk
    mesa-demos
    xdpyinfo
  ];
}
