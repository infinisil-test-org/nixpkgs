- Daily sync from all GitHub teams to Nixpkgs
  - Only sync the teams that have permissions for Nixpkgs (aka the ones that can be requested for review!)
  - gh api /repos/NixOS/nixpkgs/teams
  - And their child teams ofc
  - Only teams that are not secret (visibility), but rather "closed"
- Create a JSON of the form
  ```json
  {
    "teams": {
      "slug": "foo",
      "description": "florp",
      "members": [
        "infinisil",
        "ra33it0",
        "refroni"
      ],
      "maintainers": [
      ];
    }
  }
  ```
  - Why not github ids? Because it's less transparent, and it gets synced daily anyways, so name changes aren't problematic
- For the syncs, CI needs to check that all team members have a corresponding maintainers entry, that's how `lib.teams` gets created
  - Anybody who doesn't have a maintainers entry either needs to add it, or will be removed from the team
- `lib.teams` gets assembled by matching the generated team list with `lib.maintainers`, plus some extra manual information like
- What to do with enableFeatureFreezePing?
  - Allow teams to manually enable it by changing the code
