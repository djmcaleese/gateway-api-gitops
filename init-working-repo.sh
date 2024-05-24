#!/usr/bin/env bash

set -euo pipefail

INPUT_PATH=${1:-working}
PARENT_DIR=$(dirname ${INPUT_PATH})

if [[ ! -d ${PARENT_DIR} ]]; then
  echo "[ERROR] Parent directory \"${PARENT_DIR}\" doesn't exist"
  exit 1
fi

SUB_DIR=$(basename ${INPUT_PATH})
WORK_DIR=$(realpath ${PARENT_DIR})/${SUB_DIR}

if [[ ${WORK_DIR} != /Users/* ]]; then
  echo "[ERROR] Path must be in a home directory"
  exit 2
fi

if [[ -f ${WORK_DIR} && ! -d ${WORK_DIR} ]]; then
  echo "[ERROR] \"${SUB_DIR}\" is not a directory"
  exit 3
fi

echo "Setting up working directory in ${WORK_DIR}"

rm -rf ${WORK_DIR}
mkdir ${WORK_DIR}
cd ${WORK_DIR}
git init
git config commit.gpgsign false
git config push.autoSetupRemote true
git commit --allow-empty -m "Initial commit"

if kubectl -n gitea get svc gitea-http >/dev/null 2>&1; then
  GITEA_HTTP=http://$(kubectl -n gitea get svc gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].*}' 2>/dev/null):3180
  echo "Adding remote ${GITEA_HTTP} and force pushing"
  git remote add origin ${GITEA_HTTP}/gloo-gitops/gitops-repo.git
  git config credential.helper '!f() { sleep 1; echo "username=gloo-gitops"; echo "password=password"; }; f'
#  git push --force
fi

echo
echo "Run this command in the tagged repo to target the working directory:"
echo "  export GIT_WORK_TREE=$(realpath ${WORK_DIR})"
