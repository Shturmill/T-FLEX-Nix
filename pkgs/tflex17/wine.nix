# Wine по умолчанию для префикса T-FLEX CAD 17: Wine Staging, как в
# официальной инструкции, в режиме WoW64 — 64-битная сборка, которая
# запускает и 32-битные установщики компонентов без 32-битных библиотек
# хоста. Классическая сборка (wineWowPackages) в nixpkgs объявлена устаревшей.
#
# В Wine 11.7–11.13 переписанный msxml3 возвращает из
# IXMLDOMNamedNodeMap::setNamedItem NULL вместо добавленного атрибута:
# ToolkitPro в T-FLEX CAD получает _com_error, и программа падает при
# запуске (пустое окно и предложение отправить отчёт). Исправлено в 11.14.
# Если Staging из nixpkgs попадает в этот диапазон (в nixos-26.05 — 11.8),
# берётся стабильный Wine.
{ lib, wineWow64Packages }:

let
  staging = wineWow64Packages.stagingFull;
  brokenMsxml = lib.versionAtLeast staging.version "11.7" && lib.versionOlder staging.version "11.14";
in
if brokenMsxml then wineWow64Packages.stableFull else staging
