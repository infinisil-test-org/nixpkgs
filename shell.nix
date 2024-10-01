# A shell to get tooling for Nixpkgs development
#
# Note: We intentionally don't use Flakes here,
# because every time you change any file and do another `nix develop`,
# it would create another copy of the entire ~500MB tree in the store.
# See https://github.com/NixOS/nix/pull/6530 for the future
{
  system ? builtins.currentSystem,
}:
let
  inherit (import ./ci { inherit system; }) pkgs;
in
pkgs.mkShellNoCC {
  packages = with pkgs; [
    # The default formatter for Nix code
    # See https://github.com/NixOS/nixfmt
    nixfmt-rfc-style
    # Helper to review Nixpkgs PRs
    # See CONTRIBUTING.md
    nixpkgs-review
  ];
}
