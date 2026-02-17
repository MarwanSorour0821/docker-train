#!/usr/bin/env bash
# Run on EC2 from repo root. Uses Docker Hub image (no build). Open port 8000 in Security Group.
set -e
CLUSTER_NAME="${CLUSTER_NAME:-lunch-rush}"
K8S_DIR="k8s"

echo "==> Creating k3d cluster: $CLUSTER_NAME (host port 8000 -> 8000)"
k3d cluster create "$CLUSTER_NAME" --port 8000:8000@loadbalancer

echo "==> Deploying Redis and app (image from Docker Hub)"
kubectl apply -f "$K8S_DIR/redis.yaml"
kubectl apply -f "$K8S_DIR/app-ec2.yaml"

echo "==> Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=redis --timeout=60s
kubectl wait --for=condition=Ready pod -l app=lunch-rush-app --timeout=120s

echo ""
echo "Done. From this host: curl http://localhost:8000/menu/"
echo "From the internet: curl http://<EC2_PUBLIC_IP>:8000/menu/"
echo "Ensure Security Group allows inbound TCP 8000 (and 22 for SSH)."
echo "Scale: kubectl scale deployment lunch-rush-app --replicas=5"
echo "Delete cluster: k3d cluster delete $CLUSTER_NAME"
