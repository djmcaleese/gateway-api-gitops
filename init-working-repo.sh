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

GITEA_HTTP=http://git.example.com:3180
git clone ${GITEA_HTTP}/gloo-gitops/gitops-repo.git ${WORK_DIR}
git -C ${WORK_DIR} config commit.gpgsign false
git -C ${WORK_DIR} config credential.helper '!f() { sleep 1; echo "username=gloo-gitops"; echo "password=password"; }; f'

echo
echo "Run this command in the tagged repo to target the working directory:"
echo "  export GIT_WORK_TREE=$(realpath ${WORK_DIR})"
