# Lunch Rush on Kubernetes (k3d)

Run the app on a local Kubernetes cluster with **k3d**. Traffic is load-balanced across multiple app replicas; the `/menu/` response includes `server` (pod hostname) so you can see which replica handled each request.

## Prerequisites

- **Docker** running
- **k3d**: [install](https://k3d.io/v5.6.0/usage/installation/)
- **kubectl**: [install](https://kubernetes.io/docs/tasks/tools/)

```bash
# macOS (Homebrew)
brew install k3d kubectl
```

## Quick start

From the **repo root** (not inside `k8s/`).

**Option A – one script (if you have k3d and kubectl installed):**

```bash
./k8s/up.sh
```

**Option B – step by step:**

```bash
# 1. Create a k3d cluster (map host 8000 to LB so the app Service is reachable)
k3d cluster create lunch-rush --port 8000:8000@loadbalancer

# 2. Build the app image (from the app directory)
cd containers/backend/lunch_rush
docker build -t lunch_rush_app:latest .
cd ../../..

# 3. Import the image into the k3d cluster (so it can run the pod)
k3d image import lunch_rush_app:latest -c lunch-rush

# 4. Deploy Redis and the app
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/app.yaml

# 5. Wait for pods to be Ready and the app Service to get an address
kubectl get pods -w
# Ctrl+C when all are Running; then:
kubectl get svc lunch-rush-app
```

**Note:** The app is exposed with a **LoadBalancer** Service. With `--port 8000:8000@loadbalancer`, k3d makes it reachable on host port **8000**. Use:

```bash
curl http://localhost:8000/menu/
```

Each response includes `"server": "<pod-name>"`. Run `curl` several times to see different pod names as requests are distributed.

## Optional: use a different port

If 8000 is already in use, create the cluster with another port:

```bash
k3d cluster create lunch-rush --port 9080:8000@loadbalancer
# Then use: curl http://localhost:9080/menu/
```

## Scale replicas

```bash
kubectl scale deployment lunch-rush-app --replicas=5
kubectl get pods -l app=lunch-rush-app
```

Then hit the same URL repeatedly; you should see more distinct `server` values.

## Observe load distribution

```bash
# Hit the endpoint 10 times and show only the "server" field
for i in $(seq 1 10); do curl -s http://localhost:8000/menu/ | grep -o '"server":"[^"]*"'; done
```

## Use the image from Docker Hub instead of building locally

If you prefer not to build/import:

1. Edit `k8s/app.yaml`: set `image` to `marwansorour08212003/lunch_rush_app:latest` and `imagePullPolicy: Always` (or remove it).
2. Skip the `docker build` and `k3d image import` steps; run only `k3d cluster create`, then `kubectl apply -f k8s/redis.yaml` and `kubectl apply -f k8s/app.yaml`.

## Running on EC2

Run the same k3d stack on an **Amazon EC2** instance so you can reach the app via the instance’s public IP.

### 1. EC2 and Security Group

- Launch an EC2 instance (e.g. **Amazon Linux 2023** or **Ubuntu 22.04**), size at least **t3.small** (2 vCPU, 2 GB RAM).
- In the **Security Group**, allow:
  - **22** (SSH) from your IP.
  - **8000** (TCP) from `0.0.0.0/0` (or your IP) so the app is reachable.

### 2. Install Docker, k3d, and kubectl on the instance

SSH in, then run one of the following.

**Amazon Linux 2023:**

```bash
# Docker
sudo yum update -y
sudo yum install -y docker
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in (or new SSH session) so docker runs without sudo

# k3d (after re-login)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
sudo mv k3d /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

**Ubuntu 22.04:**

```bash
# Docker
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
# Log out and back in

# k3d (after re-login)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
sudo mv k3d /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

### 3. Get the repo on the instance

From your **local machine** (clone and SCP, or clone on EC2 if the repo is public):

```bash
# Option A: on EC2, clone the repo (if public)
git clone https://github.com/YOUR_USER/docker-train.git
cd docker-train

# Option B: from your laptop, copy k8s to EC2 (on EC2 run: mkdir -p ~/docker-train first)
scp -r k8s ec2-user@<EC2_PUBLIC_IP>:~/docker-train/
```

### 4. Start the stack on EC2

On the **EC2 instance** (from repo root, after `cd docker-train`):

```bash
chmod +x k8s/up-ec2.sh
./k8s/up-ec2.sh
```

This uses the **Docker Hub** image `marwansorour08212003/lunch_rush_app:latest` (no build on EC2).

### 5. Use the app

- On the instance: `curl http://localhost:8000/menu/`
- From your laptop: `curl http://<EC2_PUBLIC_IP>:8000/menu/`

Run multiple times to see different `"server"` pod names. Scale with:

```bash
kubectl scale deployment lunch-rush-app --replicas=5
```

### 6. Clean up on EC2

```bash
k3d cluster delete lunch-rush
```

## Clean up (local)

```bash
k3d cluster delete lunch-rush
```

## Flow summary

| Step | What happens |
|------|----------------|
| VM / host | Your machine runs Docker and k3d. |
| Containers | App and Redis run as containers inside Kubernetes pods. |
| App | Django/Gunicorn serves `/menu/`; Redis is the shared cache. |
| Load | The `lunch-rush-app` Service load-balances across all app pods. |
| Scaling | Increase `replicas` in the Deployment (or `kubectl scale`); new pods get traffic automatically. |

This ties together: **VM → Containers → App → Load → Scaling.**
