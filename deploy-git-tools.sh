#!/usr/bin/env bash

set -euo pipefail

CLUSTER1=${CLUSTER1:=cluster1}
GITEA_VERSION=10.4.1
ARGOCD_VERSION=7.6.7

export GITEA_HTTP=http://git.example.com:3180

helm upgrade --install gitea gitea \
  --repo https://dl.gitea.com/charts/ \
  --version ${GITEA_VERSION} \
  --namespace gitea \
  --create-namespace \
  --wait \
  -f -<<EOF
service:
  http:
    type: LoadBalancer
    port: 3180
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-type: external
redis-cluster:
  enabled: false
postgresql-ha:
  enabled: false
persistence:
  enabled: false
gitea:
  config:
    repository:
      ENABLE_PUSH_CREATE_USER: true
      DEFAULT_PUSH_CREATE_PRIVATE: false
    database:
      DB_TYPE: sqlite3
    session:
      PROVIDER: memory
    cache:
      ADAPTER: memory
    queue:
      TYPE: level
    server:
      ROOT_URL: ${GITEA_HTTP}
      OFFLINE_MODE: true
    webhook:
      ALLOWED_HOST_LIST: private
EOF

kubectl -n gitea wait svc gitea-http --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' --timeout=300s

# For webhooks to work, it's crucial that Gitea's ROOT_URL matches the one used in Argo CD application repos.
# If you're not able to use /etc/hosts where Argo CD is running (e.g. running on a public cloud),
# update ROOT_URL to the Gitea load balancer IP/name:

# export GITEA_HTTP=http://$(kubectl -n gitea get svc gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].*}'):3180
# helm upgrade --install gitea gitea \
#   --repo https://dl.gitea.com/charts/ \
#   --version ${GITEA_VERSION} \
#   --namespace gitea \
#   --reuse-values \
#   --wait \
#   -f -<<EOF
# gitea:
#   config:
#     server:
#       ROOT_URL: ${GITEA_HTTP}
# EOF

echo -n "Waiting for Gitea load balancer..."
timeout -v 5m bash -c "until [[ \$(curl -s --fail ${GITEA_HTTP}) ]]; do
  sleep 5
  echo -n .
done
echo"

GITEA_ADMIN_TOKEN=$(curl -Ss ${GITEA_HTTP}/api/v1/users/gitea_admin/tokens \
  -H "Content-Type: application/json" \
  -d '{"name": "workshop", "scopes": ["write:admin", "write:repository"]}' \
  -u 'gitea_admin:r8sA8CPHD9!bt6d' \
  | jq -r .sha1)

curl -i ${GITEA_HTTP}/api/v1/admin/users \
  -H "accept: application/json" -H "Content-Type: application/json" \
  -H "Authorization: token ${GITEA_ADMIN_TOKEN}" \
  -d '{
    "username": "gloo-gitops",
    "password": "password",
    "email": "gloo-gitops@solo.io",
    "full_name": "Solo.io GitOps User",
    "must_change_password": false
  }'

ARGOCD_WEBHOOK_SECRET=$(shuf -ern32 {A..Z} {a..z} {0..9} | paste -sd "\0" -)
echo "Argo CD webhook secret: ${ARGOCD_WEBHOOK_SECRET}"

helm upgrade --install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version ${ARGOCD_VERSION} \
  --namespace argocd \
  --create-namespace \
  --wait \
  -f -<<EOF
server:
  service:
    type: LoadBalancer
    servicePortHttp: 3280
    servicePortHttps: 3243
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-type: external
configs:
  params:
    server.insecure: true
    server.disable.auth: true
  secret:
    gogsSecret: ${ARGOCD_WEBHOOK_SECRET}
  cm:
    timeout.reconciliation: 10s
  clusterCredentials:
    ${CLUSTER1}:
      server: https://kubernetes.default.svc
      config:
        tlsClientConfig:
          insecure: false
EOF

kubectl -n argocd wait svc argo-cd-argocd-server --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' --timeout=300s

ARGOCD_HTTP_IP=$(kubectl -n argocd get svc argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -n "Waiting for Argo CD load balancer..."
timeout -v 5m bash -c "until [[ \$(curl -s --fail http://${ARGOCD_HTTP_IP}:3280/healthz?full=true) ]]; do
  sleep 5
  echo -n .
done
echo"

argocd login ${ARGOCD_HTTP_IP}:3280 --username admin --password ${ARGOCD_ADMIN_SECRET} --plaintext

unset GIT_WORK_TREE GIT_DIR

export GITOPS_REPO_LOCAL=$(mktemp -d "${TMPDIR:-/tmp}/gloo-gitops-repo.XXXXXXXXX")
git -C ${GITOPS_REPO_LOCAL} init -b main
git -C ${GITOPS_REPO_LOCAL} config commit.gpgsign false
git -C ${GITOPS_REPO_LOCAL} config push.autoSetupRemote true
git -C ${GITOPS_REPO_LOCAL} config credential.helper '!f() { sleep 1; echo "username=gloo-gitops"; echo "password=password"; }; f'
git -C ${GITOPS_REPO_LOCAL} remote add origin ${GITEA_HTTP}/gloo-gitops/gitops-repo.git

mkdir -p ${GITOPS_REPO_LOCAL}/platform/apps
cat <<EOF > ${GITOPS_REPO_LOCAL}/platform/apps/aoa.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  finalizers:
  - resources-finalizer.argocd.argoproj.io/background
spec:
  project: platform
  sources:
  - repoURL: ${GITEA_HTTP}/gloo-gitops/gitops-repo.git
    targetRevision: HEAD
    path: platform/apps
  destination:
    name: ${CLUSTER1}
    namespace: argocd
  syncPolicy:
    automated:
      allowEmpty: true
      prune: true
    syncOptions:
    - ApplyOutOfSyncOnly=true
EOF

git -C ${GITOPS_REPO_LOCAL} add .
git -C ${GITOPS_REPO_LOCAL} commit -m "App-of-apps"
git -C ${GITOPS_REPO_LOCAL} push

kubectl -n argocd apply -f ${GITOPS_REPO_LOCAL}/platform/apps/aoa.yaml

curl -i ${GITEA_HTTP}/api/v1/repos/gloo-gitops/gitops-repo/hooks \
  -H "accept: application/json" -H "Content-Type: application/json" \
  -H "Authorization: token ${GITEA_ADMIN_TOKEN}" \
  -d '{
    "active": true,
    "type": "gitea",
    "branch_filter": "*",
    "config": {
      "content_type": "json",
      "url": "'http://${ARGOCD_HTTP_IP}:3280/api/webhook'",
      "secret": "'${ARGOCD_WEBHOOK_SECRET}'"
    },
    "events": [
      "push"
    ]
  }'

rm -rf ${GITOPS_REPO_LOCAL}

echo
echo "${GITEA_HTTP}/gloo-gitops/gitops-repo.git is ready to clone"
echo "Gitea is at ${GITEA_HTTP}"
echo "ArgoCD is at http://${ARGOCD_HTTP_IP}:3280/"
