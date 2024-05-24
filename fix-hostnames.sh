#!/usr/bin/env bash

set -euo pipefail

# Find all IP addresses using `grep -Er "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"`

if [ -z "${GIT_WORK_TREE+x}" ]; then
  REPLACEMENT_ROOT=.
else
  REPLACEMENT_ROOT=${GIT_WORK_TREE}
fi

echo "Updating hostnames in directory ${REPLACEMENT_ROOT}"

GIT_REPO_HOST_IN_SOURCE=k8s-gitea-giteahtt-cb28b6957b-c5636c32d8003bdd.elb.eu-west-1.amazonaws.com:3180
KEYCLOAK_HOST_IN_SOURCE=k8s-keycloak-keycloak-2abea3d365-1b665a37f4fc7782.elb.eu-west-1.amazonaws.com:8080

if kubectl -n gitea get svc gitea-http >/dev/null 2>&1; then
  GIT_REPO_HOST_IN_TARGET=$(kubectl -n gitea get svc gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].*}' 2>/dev/null):3180
fi
#GIT_REPO_HOST_IN_TARGET=1.2.3.4:4445

if kubectl -n keycloak get service keycloak >/dev/null 2>&1; then
  KEYCLOAK_HOST_IN_TARGET=$(kubectl -n keycloak get service keycloak -o jsonpath='{.status.loadBalancer.ingress[0].*}' 2>/dev/null):8080
fi
#KEYCLOAK_HOST_IN_TARGET=5.6.7.8:8889

echo "Using new Git repo: ${GIT_REPO_HOST_IN_TARGET:-unset}"
if [ ! -z "${GIT_REPO_HOST_IN_TARGET+x}" ]; then
  echo Applying
  LC_ALL=C find ${REPLACEMENT_ROOT} -type f -not -path '*/\.git/*' \
    -exec sed -i '' -e "s/${GIT_REPO_HOST_IN_SOURCE}/${GIT_REPO_HOST_IN_TARGET}/g" {} \;
fi

echo "Using new Keycloak host: ${KEYCLOAK_HOST_IN_TARGET:-unset}"
if [ ! -z "${KEYCLOAK_HOST_IN_TARGET+x}" ]; then
  echo Applying
  LC_ALL=C find ${REPLACEMENT_ROOT} -type f -not -path '*/\.git/*' \
    -exec sed -i '' -e "s/${KEYCLOAK_HOST_IN_SOURCE}/${KEYCLOAK_HOST_IN_TARGET}/g" {} \;
fi

