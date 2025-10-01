{
  lib,
}:
{
  changedattrs,
  changedpathsjson,
  removedattrs,
  byName ? false,
}:
let
  pkgs = import ../../.. {
    system = "x86_64-linux";
    config = { };
    overlays = [ ];
  };

  changedpaths = builtins.fromJSON (builtins.readFile changedpathsjson);

  anyMatchingFile =
    filename: builtins.any (changed: lib.strings.hasSuffix changed filename) changedpaths;

  anyMatchingFiles = files: builtins.any anyMatchingFile files;

  attrsWithMaintainers = lib.pipe (changedattrs ++ removedattrs) [
    (builtins.map (
      name:
      let
        # Some packages might be reported as changed on a different platform, but
        # not even have an attribute on the platform the maintainers are requested on.
        # Fallback to `null` for these to filter them out below.
        package = lib.attrByPath (lib.splitString "." name) null pkgs;
      in
      {
        inherit name package;
        # `meta.maintainers` would contain also individual team members.
        # We don't want to ping people individually when added via the team though,
        # to allow use of GitHub's more advanced team review features
        maintainers = package.meta.individualMaintainers or [ ];
        teams = package.meta.teams or [ ];
      }
    ))
    # No need to match up packages without maintainers with their files.
    # This also filters out attributes where `packge = null`, which is the
    # case for libintl, for example.
    (builtins.filter (pkg: pkg.maintainers != [ ] || pkg.teams != [ ]))
  ];

  relevantFilenames =
    drv:
    (lib.lists.unique (
      builtins.map (pos: lib.strings.removePrefix (toString ../..) pos.file) (
        builtins.filter (x: x != null) [
          ((drv.meta or { }).maintainersPosition or null)
          ((drv.meta or { }).teamsPosition or null)
          (builtins.unsafeGetAttrPos "src" drv)
          # broken because name is always set by stdenv:
          #    # A hack to make `nix-env -qa` and `nix search` ignore broken packages.
          #    # TODO(@oxij): remove this assert when something like NixOS/nix#1771 gets merged into nix.
          #    name = assert validity.handled; name + lib.optionalString
          #(builtins.unsafeGetAttrPos "name" drv)
          (builtins.unsafeGetAttrPos "pname" drv)
          (builtins.unsafeGetAttrPos "version" drv)

          # Use ".meta.position" for cases when most of the package is
          # defined in a "common" section and the only place where
          # reference to the file with a derivation the "pos"
          # attribute.
          #
          # ".meta.position" has the following form:
          #   "pkgs/tools/package-management/nix/default.nix:155"
          # We transform it to the following:
          #   { file = "pkgs/tools/package-management/nix/default.nix"; }
          { file = lib.head (lib.splitString ":" (drv.meta.position or "")); }
        ]
      )
    ));

  attrsWithFilenames = builtins.map (
    pkg: pkg // { filenames = relevantFilenames pkg.package; }
  ) attrsWithMaintainers;

  attrsWithModifiedFiles = builtins.filter (pkg: anyMatchingFiles pkg.filenames) attrsWithFilenames;

  userPings =
    pkg:
    lib.map (maintainer: {
      type = "user";
      user = if byName then maintainer.github else toString maintainer.githubId;
      packageName = pkg.name;
    });

  teamPings =
    pkg: team:
    if team ? github then
      [
        {
          type = "team";
          # FIXME: If byName is false, use team.githubId, which is not tracked at the moment, but should be to avoid problems with team renames
          team = team.github;
          packageName = pkg.name;
        }
      ]
    else
      userPings pkg team.members;

  maintainersToPing = lib.concatMap (
    pkg: userPings pkg pkg.maintainers ++ lib.concatMap (teamPings pkg) pkg.teams
  ) attrsWithModifiedFiles;

  byType = lib.groupBy (ping: ping.type) maintainersToPing;

  byUser = lib.pipe (byType.user or [ ]) [
    (lib.groupBy (ping: ping.user))
    (lib.mapAttrs (_user: lib.map (pkg: pkg.packageName)))
  ];
  byTeam = lib.pipe (byType.team or [ ]) [
    (lib.groupBy (ping: ping.team))
    (lib.mapAttrs (_team: lib.map (pkg: pkg.packageName)))
  ];
in
{
  users = byUser;
  teams = byTeam;
}
