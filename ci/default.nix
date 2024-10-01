{
  system ? builtins.currentSystem,
}:
let
  pinnedNixpkgs = builtins.fromJSON (builtins.readFile ./pinned-nixpkgs.json);

  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${pinnedNixpkgs.rev}.tar.gz";
    sha256 = pinnedNixpkgs.sha256;
  };

  pkgs = import nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };

in
{
  inherit pkgs;
  requestReviews = pkgs.callPackage ./request-reviews { };

  codeownersValidator = pkgs.callPackage ./codeowners-validator { };
}
