# ChatOps

Several [Rake tasks](./rake-tasks.md) are available to be run via [GitLab
ChatOps][chatops].

Performing these tasks via ChatOps offers some important benefits:

- release-tools doesn't need to be configured with access tokens
- Task runs won't be interrupted by spotty internet connections or
  random computer reboots
- Anyone can follow the progress of a task by viewing its CI job
- The release manager doesn't need to switch away from Slack as frequently

[chatops]: https://gitlab.com/gitlab-com/chatops

## Preparation

Before you're able to run any ChatOps commands, your Slack account needs to be
authenticated to the ChatOps project. Run `/chatops` in Slack to introduce
yourself to the bot, who will help get you authenticated.

Once authenticated, you can run `/chatops help` to see a list of available
commands. Commands implemented for release tools are all performed via `/chatops
run [command]`, and are outlined below.

All `run` commands take a `--help` flag that details their available options.

## Commands

### `release`

Tags the specified version.

> NOTE: If for some reason the ChatOps command isn't working as expected, you
> can run the equivalent [`rake release`](./rake-tasks.md#releaseversion)
> command locally.

#### Options

| flag         | description                                                           |
| ----         | -----------                                                           |
| `--security` | Perform a [security release](./rake-tasks.md#security_releaseversion) |

#### Examples

```
/chatops run release 11.0.0-rc10

/chatops run release 11.0.1

/chatops run release --security 11.0.2
```

## Technical details

ChatOps commands are implemented in the [ChatOps project][chatops-commands].
Those commands use [triggers](https://docs.gitlab.com/ee/ci/triggers/) to
trigger the `chatops` job in this project, which runs
[`bin/chatops`](../bin/chatops), which triggers the appropriate [Rake
task](./rake-tasks.md).

[chatops-commands]: https://gitlab.com/gitlab-com/chatops/tree/master/lib/chatops/commands

---

[Return to Documentation](../README.md#documentation)