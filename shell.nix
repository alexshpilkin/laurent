#!/usr/bin/env -S nix develop --no-write-lock-file -f

{ pkgs ? import <nixpkgs> { }
, lua ? pkgs.lua
, luaPackages ? lua.pkgs
, lmpfr ? luaPackages.lmpfr
}:

pkgs.mkShellNoCC {
	packages = [ (lua.withPackages (_: [ lmpfr ])) ];
}
