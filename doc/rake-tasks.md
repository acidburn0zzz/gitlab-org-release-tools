# Rake Tasks

This project includes several Rake tasks to automate parts of the release
process.

Generally these tasks are executed via [ChatOps](./chatops.md) and should not
need to be run directly.

## Setup

1. Install the required dependencies with Bundler:

    ```sh
    bundle install
    ```

1. Several of the tasks require API access to a GitLab instance. These tokens
   should be provided at runtime via environment variables. See
   [`variables.md`](./variables.md) for a list of recognized variables.

## `release` tasks

Tasks in this namespace automate release-related activities such as tagging and
publishing packages.

### `release:issue[version]`

Create a task issue for the specified version.

### `release:merge[version]`

Cherry-pick merge requests into the preparation branches for the specified
version.

### `release:prepare[version]`

Prepare for a release of the specified version.

For monthly versions (`X.Y.0`), it will:

1. Create the `Pick into X.Y` group label
1. Create the `X-Y-stable[-ee]` branches
1. Create the monthly release task issue
1. Create the RC1 task issue
1. Create the RC1 preparation MRs

For patch versions (`X.Y.Z` or `X.Y.0-rcX`), it will:

1. Create the task issue
1. Create the preparation MRs

### `release:qa[from,to]`

Create an issue that lists changes introduced between `from` and `to` and return
the URL of the new issue.

### `release:tag[version]`

Tag the specified version.

### `release:helm:tag[charts_version,gitlab_version]`

This task will:

1. Create the `X-Y-stable` branch off the current `master` using the `version`
   argument, if the branch doesn't yet exist.
1. Runs the `bump_version` script in the `gitlab-org/charts/gitlab` repo;
   passing the `charts_version`, and `gitlab_version` (if provided) for the
   branches above.
1. Create the `v[charts_version]` tag, pointing to the respective branch created
   above.  But only if the `gitlab_version` is not an RC. (we currently don't
   tag RC charts
1. Push all newly-created branches and tags to all remotes.
1. Runs the `bump_version` script in the master branch, only passing the
   `charts_version`. And only running if `charts_version` is newer than what is
   already in master.
1. Pushes the master branch to all remotes.

Details on the chart version scheme can be found
in the `gitlab-org/charts/gitlab` repo's [release documentation](https://gitlab.com/gitlab-org/charts/gitlab/blob/master/doc/development/release.md)

#### Arguments

| argument         | required | description                               |
| ------           | -----    | -----------                               |
| `charts_version` | yes      | Chart version to tag                      |
| `gitlab_version` | no       | GitLab image version to use in the branch |

If `gitlab_version` is provided, the version of GitLab used in the chart will be
updated before tagging.

If `charts_version` is empty, but a valid `gitlab_version` has been provided,
then the script will tag using an increment of the previous tagged release. This
scenario is only intended to be used by CI release automation, where it is being
run in a project that is only aware of the desired GitLab Version.

#### Configuration

| Option          | Purpose                                |
| ------          | -------                                |
| `TEST=true`     | Don't push anything to remotes         |

#### Examples

```sh
# Create 0-3-stable branch, but don't tag, for testing using 11.1 RC1:
bundle exec rake "release:helm:tag[0.3.0,11.1.0-rc1]"

# Tag 0.3.1, and include GitLab Version 11.1.1
bundle exec rake "release:helm:tag[0.3.1,11.1.1]"

# Tag 0.3.2, but don't change the GitLab version:
bundle exec rake "release:helm:tag[0.3.2]"

# Don't push branches or tags to remotes:
TEST=true bundle exec rake "release:helm:tag[0.3.3]"

# Tag using an increment of the last tag, and update the GitLab version
bundle exec rake "release:helm:tag[,11.1.2]"
```

## `security` tasks

Tasks in this namespace largely mirror their [`release`
counterparts](#release-tasks), but with additional safeguards in place for
performing a security release of GitLab.

### `security:prepare[version]`

Create a security issue for an upcoming security release. One issue is created
for all backported releases.

For example, if the current patch versions of the last three minor releases are
`11.9.1`, `11.8.3`, and `11.7.6`, it will create one confidential task issue for
`11.9.2`, `11.8.4`, and `11.7.7`.

ChatOps command to create a regular security release:

```
/chatops run release prepare --security
```

ChatOps command to create a critical security release:

```
/chatops run release prepare --security --critical
```

### `security:validate`

This task is executed via CI schedule. It validates security merge requests
on Security projects.

### `security:merge`

Validates and merges validated merge requests in the security repositories for GitLab projects.

ChatOps command:

```
/chatops run release merge --security
```

### `security:tag[version]`

Tag the specified version as a security release.

ChatOps command:

```
/chatops run release tag --security 12.7.6
```

### `security:qa[from,to]`

Create a confidential QA issue, listing changes between `from` and `to` in order
to verify changes in a release.

QA issue is automatically created by the deployer pipeline if the deploy to staging
was successful.

## `publish[version]`

This task will publish all available CE and EE packages for a specified version.

### Configuration

| Option      | Purpose                                |
| ------      | -------                                |
| `TEST=true` | Don't actually play the manual actions |

### Examples

``` sh
$ bundle exec rake 'publish[11.1.0-rc4]'

Nothing to be done for 11.1.0+rc4.ee.0: https://dev.gitlab.org/gitlab/omnibus-gitlab/pipelines/86189
Nothing to be done for 11.1.0+rc4.ce.0: https://dev.gitlab.org/gitlab/omnibus-gitlab/pipelines/86193
```

```sh
$ bundle exec rake "publish[11.1.0-rc5]"

--> 11.1.0+rc5.ee.0: https://dev.gitlab.org/gitlab/omnibus-gitlab/pipelines/86357
    Ubuntu-14.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599976
    Ubuntu-16.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599977
    Ubuntu-18.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599978
    Debian-7-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599979
    Debian-8-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599980
    Debian-9.1-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599981
    CentOS-6-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599982
    CentOS-7-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599983
    OpenSUSE-42.3-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599984
    SLES-12-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599985
    Docker-Release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599987
    AWS: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599988
    QA-Tag: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599989
    Raspberry-Pi-2-Jessie-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2599993

--> 11.1.0+rc5.ce.0: https://dev.gitlab.org/gitlab/omnibus-gitlab/pipelines/86362
    Ubuntu-14.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600293
    Ubuntu-16.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600294
    Ubuntu-18.04-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600295
    Debian-7-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600296
    Debian-8-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600297
    Debian-9.1-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600298
    CentOS-6-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600299
    CentOS-7-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600300
    OpenSUSE-42.3-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600301
    SLES-12-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600302
    Docker-Release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600304
    AWS: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600305
    QA-Tag: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600306
    Raspberry-Pi-2-Jessie-release: https://dev.gitlab.org/gitlab/omnibus-gitlab/-/jobs/2600310
```

---

[Return to Documentation](../README.md#documentation)

[`config/release_managers.yml`]: ../config/release_managers.yml
