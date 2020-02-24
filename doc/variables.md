# release-tools CI variables

This project makes heavy use of environment variables for configuration. This
document aims to provide a reference for the most important ones, but is not
necessarily comprehensive.

These are the [CICD variables](https://gitlab.com/gitlab-org/release-tools/settings/ci_cd) that are
defined in the [release-tools project](https://gitlab.com/gitlab-org/release-tools).

## Instance tokens

| Variable Name                | Deployment         | Token name\*      | Scopes        | User          |
| ------------                 | ------------       | ------------      | ------------  | ------------
| `DEV_API_PRIVATE_TOKEN`        | dev.gitlab.org     | release-tools     | api           | [@gitlab-release-tools-bot][gitlab-release-tools-bot-dev] |
| `RELEASE_BOT_DEV_TOKEN`        | dev.gitlab.org     | release-tools     | api           | [@gitlab-release-tools-bot][gitlab-release-tools-bot-dev] |
| `OPS_API_PRIVATE_TOKEN`        | ops.gitlab.net     | deployer token for ops.gitlab.net | api, read_user, read_repository, read_registry | [@deployer][deployer-ops] |
| `RELEASE_BOT_OPS_TOKEN`        | ops.gitlab.net     | Release token | api | [@gitlab-release-tools-bot][gitlab-release-tools-bot-ops] |
| `RELEASE_BOT_PRODUCTION_TOKEN` | gitlab.com         | release-tools | api | [@gitlab-release-tools-bot][gitlab-release-tools-bot-com] |
| `VERSION_API_PRIVATE_TOKEN`    | version.gitlab.com | private token | api | robert+release-tools@gitlab.com

_* Token name refers to the name that was entered when the token was created_

## SSH private keys

Private keys are used to push to repositories via SSH, rather than
authenticating over HTTPS with an access token.

- `RELEASE_BOT_PRIVATE_KEY` -- Private key for
  [@gitlab-release-tools-bot][gitlab-release-tools-bot-com].

## Auto-deploy

- `AUTO_DEPLOY_BRANCH` -- The current auto-deploy branch. Gets updated via API
  by auto-deploy jobs and **should not be changed manually.**
- `OMNIBUS_BUILD_TRIGGER_TOKEN` -- Used to trigger an Omnibus build.

## Miscellany

- `SENTRY_DSN` -- DSN for the `release-tools` project on
  [Sentry](https://sentry.gitlab.net/gitlab/release-tools/).
- `SLACK_CHATOPS_URL` -- Full Slack webhook URL for ChatOps responses.
- `SLACK_TAG_URL` -- Full Slack webhook URL for tagging notifications.
  notifications.

[gitlab-release-tools-bot-com]: https://gitlab.com/gitlab-release-tools-bot
[gitlab-release-tools-bot-dev]: https://dev.gitlab.org/gitlab-release-tools-bot
[gitlab-release-tools-bot-ops]: https://ops.gitlab.net/gitlab-release-tools-bot
[deployer-ops]: https://ops.gitlab.net/deployer
[gitlab-bot-com]: https://gitlab.com/gitlab-bot

---

[Return to Documentation](../README.md#documentation)
