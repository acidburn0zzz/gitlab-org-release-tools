#!/bin/sh

set -e

require_version()
{
  if [ -z "${RELEASE_VERSION}" ]; then
    echo "RELEASE_VERSION required!"
    exit 1
  fi
}

configure_git()
{
  git config --global user.email "robert+release-tools@gitlab.com"
  git config --global user.name "GitLab Release Tools Bot"
}

setup_ssh()
{
  if ! which ssh-agent; then
    apt-get update -y && apt-get install openssh-client -y
  fi

  eval $(ssh-agent -s)

  echo "$RELEASE_BOT_PRIVATE_KEY" | tr -d '\r' | ssh-add - > /dev/null

  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
  chmod 644 ~/.ssh/known_hosts
}

setup_env()
{
  export GITLAB_API_PRIVATE_TOKEN="$RELEASE_BOT_PRODUCTION_TOKEN"
  export DEV_API_PRIVATE_TOKEN="$RELEASE_BOT_DEV_TOKEN"
}

require_version
configure_git
setup_ssh
setup_env
