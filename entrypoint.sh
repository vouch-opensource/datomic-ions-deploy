#!/usr/bin/env bash

set -e
set -x

# Github Actions sets the home directory to /github/home which is not what the ions deploy tools expect
# when using tools.deps gitlibs.
# This is a work-around and might be removed when a solution is provided in ions deploy tools.
export HOME=/root

### Setup parameters

## Use :ion-dev alias by default
aliases=${1:-":ion-dev"}
COMPUTE_GROUP=$2
export AWS_REGION=$3
export AWS_ACCESS_KEY_ID=$4
export AWS_SECRET_ACCESS_KEY=$5
WORKING_DIR=$6
APP_NAME=$7
SSH_KEY=$8

## Setup SSH Agent
if [[ -n $SSH_KEY ]]
then

  eval "$(ssh-agent -s)"

  [[ ! -d ~/.ssh ]] && mkdir -p $HOME/.ssh

  ssh-keyscan github.com >> $HOME/.ssh/known_hosts

  ssh-add <(echo "$SSH_KEY")

fi

## Move to the working directory
if [[ -n $WORKING_DIR ]]; then
  cd "$WORKING_DIR"
fi

## Retrieve the git sha as the ions deployment version
SHA=$(git rev-parse HEAD)

a_Opts="-A$aliases"

function get_version {
  # Get the currently deployed version of the ions repo
  aws deploy get-deployment --deployment-id \
    $(aws deploy list-deployments --application-name $2 --deployment-group-name $1 --include-only-statuses Succeeded --no-paginate --query "deployments[0]" --output text) \
    --query "deploymentInfo.revision.s3Location.key" --output text | sed 's|^datomic/apps/.*/stable/\(.*\).zip|\1|'
}

function push {
  # Push the ions code to AWS
  clojure $a_Opts "{:op :push :region $AWS_REGION}"
}

function getDeployStatus() {
  # Retrieve the status of the current deployment
  STATUS_COMMAND=$(jet -q ':status-command println' < .deploys/$1)
  eval $STATUS_COMMAND | jet -q ':deploy-status println'
}

function waitUntilDeployed() {
  sleep_time_seconds=10
  timeout_seconds=300
  max_iterations_count=$(($timeout_seconds / $sleep_time_seconds))
  iterations=0

  status=$(getDeployStatus $1)

  while [[ ($status != "SUCCEEDED") && ($iterations -lt $max_iterations_count) ]]; do
    sleep $sleep_time_seconds
    status=$(getDeployStatus $1)
    echo "Deploy $status"
    ((iterations += 1))
  done

  if [[ $status != "SUCCEEDED" ]]; then
    echo "Failed to deploy $1 in $timeout_seconds seconds. STATUS: $status"
    exit 1
  fi
}

function deploy {
  mkdir -p .deploys

  ## if this fails, print out the error instead of sending it to the file
  set +e
  CLJ_OUTPUT=$(clojure -Sforce -A:ion-dev "{:op :deploy, :region $AWS_REGION, :group $1, :rev \"$SHA\"}")

  if [ $? -eq 0 ]; then
    echo $CLJ_OUTPUT >.deploys/$1_$SHA
    set -e
  else
    echo $CLJ_OUTPUT
    exit 1
  fi

  waitUntilDeployed "$1_$SHA"
}

if [[ $SHA != $(get_version $COMPUTE_GROUP $APP_NAME) ]]; then
  push
  deploy $COMPUTE_GROUP
fi
