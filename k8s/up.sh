#!/usr/bin/env bash
# Run from repo root. Creates k3d cluster, builds app image, imports it, deploys Redis + app.
set -e
CLUSTER_NAME="${CLUSTER_NAME:-lunch-rush}"
APP_DIR="containers/backend/lunch_rush"
K8S_DIR="k8s"

echo "==> Creating k3d cluster: $CLUSTER_NAME (host port 8000 -> 8000)"
k3d cluster create "$CLUSTER_NAME" --port 8000:8000@loadbalancer

echo "==> Building app image from $APP_DIR"
docker build -t lunch_rush_app:latest "$APP_DIR"

echo "==> Importing image into k3d cluster"
k3d image import lunch_rush_app:latest -c "$CLUSTER_NAME"

echo "==> Deploying Redis and app"
kubectl apply -f "$K8S_DIR/redis.yaml"
kubectl apply -f "$K8S_DIR/app.yaml"

echo "==> Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=redis --timeout=60s
kubectl wait --for=condition=Ready pod -l app=lunch-rush-app --timeout=120s

echo ""
echo "Done. Try: curl http://localhost:8000/menu/"
echo "Run multiple times to see different \"server\" (pod) names."
echo "Scale: kubectl scale deployment lunch-rush-app --replicas=5"
echo "Delete cluster: k3d cluster delete $CLUSTER_NAME"
