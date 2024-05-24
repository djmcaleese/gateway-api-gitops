#!/usr/bin/env bash

set -euo pipefail

helm upgrade --install gitea gitea \
  --repo https://dl.gitea.com/charts/ \
  --version 10.1.4 \
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
      OFFLINE_MODE: true
EOF

kubectl -n gitea wait svc gitea-http --for=jsonpath='{.status.loadBalancer.ingress[0].*}' --timeout=300s
export GITEA_HTTP=http://$(kubectl -n gitea get svc gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].*}'):3180

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

helm upgrade --install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 6.9.2 \
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
  cm:
    timeout.reconciliation: 10s
EOF

kubectl -n argocd wait svc argo-cd-argocd-server --for=jsonpath='{.status.loadBalancer.ingress[0].*}' --timeout=300s

ARGOCD_HTTP_IP=$(kubectl -n argocd get svc argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].*}')
ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -n "Waiting for Argo CD load balancer..."
timeout -v 5m bash -c "until [[ \$(curl -s --fail http://${ARGOCD_HTTP_IP}:3280/healthz?full=true) ]]; do
  sleep 5
  echo -n .
done
echo"

argocd login ${ARGOCD_HTTP_IP}:3280 --username admin --password ${ARGOCD_ADMIN_SECRET} --plaintext
argocd cluster set in-cluster --name ${CLUSTER1}

export GITOPS_REPO_LOCAL=$(mktemp -d "${TMPDIR:-/tmp}/gloo-gitops-repo.XXXXXXXXX")
git -C ${GITOPS_REPO_LOCAL} init -b main
git -C ${GITOPS_REPO_LOCAL} config commit.gpgsign false
git -C ${GITOPS_REPO_LOCAL} config push.autoSetupRemote true
git -C ${GITOPS_REPO_LOCAL} config credential.helper '!f() { sleep 1; echo "username=gloo-gitops"; echo "password=password"; }; f'
git -C ${GITOPS_REPO_LOCAL} remote add origin ${GITEA_HTTP}/gloo-gitops/gitops-repo.git
git -C ${GITOPS_REPO_LOCAL} commit --allow-empty -m "Initial commit"
git -C ${GITOPS_REPO_LOCAL} push

kubectl -n argocd apply -f - <<EOF
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

rm -rf ${GITOPS_REPO_LOCAL}

echo
echo "${GITEA_HTTP}/gloo-gitops/gitops-repo.git is ready to clone"
echo "Gitea is at ${GITEA_HTTP}"
echo "ArgoCD is at http://${ARGOCD_HTTP_IP}:3280/"
