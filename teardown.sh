#!/usr/bin/env bash

set -euo pipefail

kubectl -n argocd delete apps --all || true

helm uninstall argo-cd -n argocd || true
kubectl delete ns argocd || true

kubectl delete ns argo-rollouts || true

helm uninstall gitea -n gitea || true
kubectl -n gitea delete pvc --all
kubectl delete ns gitea || true

kubectl delete ns gloo-system || true
kubectl delete ns bookinfo || true
kubectl delete ns httpbin || true
kubectl delete ns keycloak || true
