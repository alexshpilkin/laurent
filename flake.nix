{
	outputs = { self, nixpkgs }:
		with nixpkgs.lib;
		let
			supportedSystems = systems.flakeExposed;
			supportedLuas = [ "luajit" "lua5_1" "lua5_2" "lua5_3" "lua5_4" ];
			addDefault = variants: variants // { default = variants.luajit; };

			forAllArgs = f:
				genAttrs supportedSystems (system:
					let pkgs = nixpkgs.legacyPackages.${system};
					in addDefault (genAttrs supportedLuas (lua:
						f {
							inherit pkgs;
							lua = pkgs.${lua};
						})));
		in {
			packages = forAllArgs (import ./.);
			devShells = forAllArgs (import ./shell.nix);
		};
}
