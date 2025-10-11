const excludeTeams = [
  /^voters.*$/,
  /^nixpkgs-maintainers$/,
  /^nixpkgs-committers$/,
]

module.exports = async ({ github, context, core, outFile }) => {
  const withRateLimit = require('./withRateLimit.js')
  const { writeFileSync } = require('node:fs')
  const result = {}
  await withRateLimit({ github, core }, async (stats) => {
    /// Turn an Array of users into an Object, mapping user.login -> user.id
    function makeUserSet(users) {
      return (
        users
          .sort((user1, user2) => (user1.login > user2.login ? 1 : -1))
          // biome-ignore lint/performance/noAccumulatingSpread: We don't care about time complexity
          .reduce((acc, user) => ({ ...acc, [user.login]: user.id }), {})
      )
    }

    /// Process a list of teams and append to the result variable
    async function processTeams(teams) {
      for (const team of teams) {
        core.notice(`Processing team ${team.slug}`)
        if (!excludeTeams.some((regex) => team.slug.match(regex))) {
          const members = makeUserSet(
            await github.paginate(github.rest.teams.listMembersInOrg, {
              org: context.repo.owner,
              team_slug: team.slug,
              role: 'member',
            }),
          )
          const maintainers = makeUserSet(
            await github.paginate(github.rest.teams.listMembersInOrg, {
              org: context.repo.owner,
              team_slug: team.slug,
              role: 'maintainer',
            }),
          )
          result[team.slug] = {
            description: team.description,
            id: team.id,
            maintainers,
            members,
            name: team.name,
          }
        }
        await processTeams(
          await github.paginate(github.rest.teams.listChildInOrg, {
            org: context.repo.owner,
            team_slug: team.slug,
          }),
        )
      }
    }

    const teams = await github.paginate(github.rest.repos.listTeams, {
      owner: context.repo.owner,
      repo: context.repo.repo,
    })

    await processTeams(teams)
  })

  // Sort the teams by team name
  const sorted = Object.keys(result)
    .sort()
    // biome-ignore lint/performance/noAccumulatingSpread: We don't care about time complexity
    .reduce((acc, key) => ({ ...acc, [key]: result[key] }), {})
  const json = `${JSON.stringify(sorted, null, 2)}\n`

  if (outFile) {
    writeFileSync(outFile, json)
  } else {
    console.log(json)
  }
}
