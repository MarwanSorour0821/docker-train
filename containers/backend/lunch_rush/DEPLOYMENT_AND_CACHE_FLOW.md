# Lunch Rush: Deployment & Redis Cache Flow

## 1. Deployment flow (Mac → Docker Hub → EC2)

```mermaid
flowchart LR
    subgraph Mac["On your Mac"]
        A[Edit code] --> B[docker buildx build --platform linux/amd64]
        B --> C[docker push to Docker Hub]
    end

    subgraph EC2["On EC2"]
        D[docker-compose pull] --> E[docker-compose up -d]
        E --> F[App + Redis containers run]
    end

    C --> D
```

| Step | Where | What you do |
|------|--------|-------------|
| 1 | Mac | Change code in `lunch_rush` |
| 2 | Mac | `cd .../lunch_rush` → `docker buildx build --platform linux/amd64 -t marwansorour08212003/lunch_rush_app:latest --push .` |
| 3 | EC2 | `docker-compose -f docker-compose.prod.yml down` (if needed) → `pull` → `up -d` |
| 4 | — | No build on EC2; it only pulls and runs the image. |

---

## 2. Runtime: request flow and Redis cache

```mermaid
flowchart TB
    Client[Client / curl] -->|:8000| App["App container (Gunicorn)"]
    App -->|GET /menu/| View[menu_views]
    View -->|cache.get('menu_items')| Redis[(Redis container)]
    Redis -->|key exists?| View
    View -->|Yes: return cached JSON| Client
    View -->|No: build response| Set["cache.set(..., timeout=10)"]
    Set --> Redis
    View -->|return JSON + from_cache: false| Client
```

```mermaid
sequenceDiagram
    participant C as Client
    participant A as App (Gunicorn)
    participant R as Redis

    C->>A: GET /menu/
    A->>R: cache.get('menu_items')
    alt cache HIT
        R-->>A: cached dict
        A-->>C: JSON (from_cache: true, same served_at)
    else cache MISS
        R-->>A: None
        A->>A: build response_data
        A->>R: cache.set('menu_items', response_data, 10s)
        A-->>C: JSON (from_cache: false, new served_at)
    end
```

---

## 3. What we had to do to make it work

```mermaid
flowchart TB
    subgraph Prereqs["Prerequisites (EC2)"]
        P1[Install Git: sudo yum install git -y]
        P2[Use docker-compose -f file.yml not docker compose]
        P3[Install docker-compose if missing]
    end

    subgraph Build["Build & run"]
        B1[Build for EC2: --platform linux/amd64 so image is amd64]
        B2[Port 8000 in use → docker-compose down then up -d]
    end

    subgraph Cache["Redis cache"]
        C1[REDIS_URL=redis://redis:6379/0 in compose]
        C2[KEY_PREFIX in Django CACHES so all workers share same key]
        C3[Optional: from_cache in response to verify]
    end

    Prereqs --> Build --> Cache
```

| Issue | Fix |
|-------|-----|
| `git: command not found` on EC2 | `sudo yum install git -y` |
| `unknown shorthand flag: -f` | Use `docker-compose` (hyphen), or install Compose v2 plugin |
| `no matching manifest for linux/amd64` | On Mac: `docker buildx build --platform linux/amd64 ... --push .` |
| `Bind for 0.0.0.0:8000 failed: port already allocated` | `docker-compose -f docker-compose.prod.yml down` then `up -d` |
| Cache always miss (different `served_at` every time) | Set `KEY_PREFIX: 'lunch_rush'` in `CACHES` in `settings.py` so all Gunicorn workers use the same Redis key |
| Verify cache | Add `from_cache` to JSON response; hit `/menu/` twice → second has `from_cache: true` and same `served_at` |

---

## 4. Architecture overview

```mermaid
flowchart LR
    subgraph Docker Host["EC2 (Docker host)"]
        subgraph lunch_rush_default["network: lunch_rush_default"]
            App["app:8000\nGunicorn + Django"]
            Redis["redis:6379\nRedis 7 Alpine"]
        end
        App <-->|redis://redis:6379/0| Redis
    end

    User[User / curl] -->|:8000| App
```

- **App container:** Serves HTTP on 8000; uses Django cache (Redis backend).
- **Redis container:** In-memory store; shared by all Gunicorn workers.
- **Compose:** Sets `REDIS_URL` and `depends_on: redis` so the app can reach Redis by hostname `redis`.

---

## 5. Load test: why `ab -c 100` timed out

### Capacity vs concurrency

```mermaid
flowchart TB
    subgraph Client["ab (ApacheBench)"]
        AB["ab -n 2000 -c 100\n= 100 connections at once"]
    end

    subgraph LB["Nginx (load balancer)"]
        N[":8000"]
    end

    subgraph Backend["App (3 containers × 2 workers = 6 at a time)"]
        W1["worker 1"]
        W2["worker 2"]
        W3["worker 3"]
        W4["worker 4"]
        W5["worker 5"]
        W6["worker 6"]
    end

    AB -->|"100 requests\nat once"| N
    N --> W1
    N --> W2
    N --> W3
    N --> W4
    N --> W5
    N --> W6

    W1 -.->|"only 6 can run\nat once"| Q["94 requests waiting in queue"]
    W2 -.-> Q
    W3 -.-> Q
```

**What happened:**

| You asked for | What you have | Result |
|---------------|----------------|--------|
| 100 concurrent requests | 6 workers (3 containers × 2 Gunicorn workers) | 6 handle requests; 94 wait in a queue |
| 2000 total requests | ab timeout ~30 s default | After ~30 s ab gives up → "The timeout specified has expired" |
| — | Only 603 completed | The rest were still waiting when ab timed out |

### Request flow over time

```mermaid
sequenceDiagram
    participant ab as ab -c 100
    participant nginx as Nginx
    participant app as 6 workers

    ab->>nginx: 100 connections open at once
    nginx->>app: forwards to app (round-robin)
    Note over app: 6 workers busy, 1 request each
    Note over ab: 94 requests still waiting (queued in Nginx / OS)
    app->>nginx: worker finishes, takes next from queue
    nginx->>ab: response
    Note over ab: After ~30s: "timeout expired" for requests still waiting
```

### Fix: match concurrency to capacity

```mermaid
flowchart LR
    subgraph Good["ab -c 10 or -c 20"]
        A["10–20 concurrent"]
        B["6 workers"]
        A --> B
        B --> C["No long queue\n→ no timeout"]
    end

    subgraph Bad["ab -c 100"]
        D["100 concurrent"]
        E["6 workers"]
        D --> E
        E --> F["94 waiting\n→ timeout"]
    end
```

- **Use `-c 10` or `-c 20`** so you don’t queue way more than 6 workers can handle.
- Or use **`-s 60`** (longer timeout) if you want to stress-test with `-c 100` and accept that many requests will wait a long time.
