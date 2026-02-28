# LEARNING NOTES

Deep-dives on the concepts used in this project.

---

## 1. Why a Different Language Per Service?

Each language was chosen for a concrete technical reason — not variety for variety's sake:

| Service | Language | Real Reason |
|---------|----------|-------------|
| user-service | Node.js | High ecosystem familiarity; JWT libs are mature; async I/O suits auth-check latency |
| product-service | Python/FastAPI | Auto-generated OpenAPI docs; Pydantic makes schema validation trivial; async MongoDB driver |
| order-service | Go | Compiled to a ~10MB static binary; goroutines for concurrent DB + Redis writes; fastest startup time |
| payment-service | Rust | Memory safety WITHOUT GC pauses — critical for payment latency; teaches ownership/borrow checker |
| notification-service | Node.js | Event loop is perfect for "listen to Redis, react" patterns; no threading complexity |
| api-gateway-bff | Python/FastAPI | asyncio fan-out patterns are expressive; httpx is excellent for concurrent upstream calls |

---

## 2. How Vault Agent Injection Works (Step by Step)

```
1. Your pod gets admitted to the API server
2. The Vault Agent Injector (mutating webhook) reads pod annotations:
     vault.hashicorp.com/agent-inject: "true"
     vault.hashicorp.com/role: "user-service"
3. The webhook MUTATES the pod spec — adds TWO extra containers:
     a. vault-agent-init (init container): logs in to Vault using the pod's
        ServiceAccount token, fetches secrets, writes them to /vault/secrets/
     b. vault-agent (sidecar container): runs alongside your app,
        continuously refreshes short-lived secrets (e.g. dynamic DB creds)
4. Your app container reads secrets from /vault/secrets/ as files,
   OR the agent is configured to export them as env vars

WHY ServiceAccount? Kubernetes ServiceAccount tokens are signed JWTs.
Vault's Kubernetes auth method validates these with the K8s API,
proving "this pod is running in namespace X with SA Y" without
needing a static username/password anywhere.
```

---

## 3. IRSA vs Node-Level IAM

| Feature | IRSA | Node-level IAM |
|---------|------|----------------|
| Scope | Per pod (via K8s SA) | All pods on the node |
| Safety | Blast radius = 1 service | Blast radius = ALL services on node |
| Auditability | CloudTrail shows WHICH pod called which API | Only shows the EC2 instance |
| Setup | Requires OIDC provider + IAM role + K8s annotation | Just add policy to node IAM role |

**Rule**: Always use IRSA for Pod-level AWS access (ECR, S3, DynamoDB).
Use node-level IAM ONLY for cluster-wide operations (SSM agent, CloudWatch).

---

## 4. GitOps vs Traditional CI/CD

```
Traditional CI/CD:
  Git push → CI builds image → CI SSH into server and deploys
  Problem: CI pipeline has direct deploy access. Credentials leak = game over.

GitOps:
  Git push → CI builds image → CI updates Helm chart tag in Git (another git push)
  ArgoCD (running IN cluster) detects Git change → pulls and deploys
  
  Advantages:
  - ClUSTER pulls from Git (not the other way around)
  - CI pipeline never needs cluster credentials!
  - Git is single source of truth — `git revert` = instant rollback
  - Self-healing: ArgoCD resists manual cluster changes (drift detection)
```

---

## 5. Kong vs raw Nginx Ingress

| Feature | Kong | Nginx Ingress |
|---------|------|---------------|
| Plugins | 50+ built-in (auth, rate-limit, transformations) | Must configure manually in Nginx config |
| Admin API | Dynamic changes without restart | Reload required |
| Multi-tenancy | Projects/workspaces/teams | Not supported |
| Plugin authz | Per-route, per-consumer granularity | Global only |
| Complexity | Higher | Lower |

**For this project**: Kong KongPlugin CRDs make it easy to annotate Services/Ingresses
with plugins without writing Lua or Nginx config. The learning value is high.

---

## 6. PrometheusRule — How Alerts Fire

```
PromQL expression evaluated every 30s:
  kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1

If the expression is TRUTHY for a duration longer than `for: 2m`:
  → Alert moves from "pending" to "firing"
  → Alertmanager routes it to Slack/PagerDuty/email

The `for` clause prevents flapping:
  - Pod restarts for 30s → alert is "pending" (no notification yet)
  - Still crashing at 2m mark → alert fires
  
This means a pod that crashes and recovers quickly never sends an alert.
```

---

## 7. Helm values.yaml Layering

```
values.yaml         → Production defaults          (EKS, ECR, Vault enabled, 2 replicas)
values-local.yaml   → Local overrides on top       (k3d registry, 1 replica, Vault disabled)

Merge order in Helm:
  helm install svc ./chart -f values.yaml -f values-local.yaml
  values-local.yaml WINS on any conflicting key
  Non-conflicting keys from values.yaml are kept

ArgoCD equivalent:
  spec.source.helm.valueFiles: [values.yaml, values-local.yaml]
  → ArgoCD merges in order, passes to Helm template engine
```

---

## 8. Redis Pub/Sub Channel Flow for Notifications

```
                   order-service (Go)
                         │
                         │ 1. PUBLISH "order.created" to Redis channel
                         ▼
                     Redis (in-memory)
                         │
                         │ 2. Redis delivers to ALL subscribers (fan-out)
                         ▼
              notification-service (Node.js)
                         │
                         │ 3. Receives JSON event, processes it
                         ▼
                    Console log / Email / SMS

WHY Redis Pub/Sub and not Kafka/RabbitMQ?
  - Zero infrastructure overhead for this learning project
  - Pub/Sub is fire-and-forget (no durability) — acceptable for notifications
  - Real production with durability guarantees → use Kafka or SQS
  - Redis already in the stack for caching — no extra service needed
```

---

## 9. Multi-Stage Docker Build Benefits

```
# Without multi-stage:
  Base image + build tools + source + deps + binary = ~500MB image
  Build secrets might be embedded in layers!

# With multi-stage:
  builder stage → has gcc, npm, cargo, pip (never shipped)
  runtime stage → has ONLY the binary/bundle + runtime (~15-50MB)

  Result: Smaller attack surface, faster pulls, faster pod scheduling
```

---

## 10. k3d vs full EKS for Local Dev

```
k3d (this project's local setup):
  - K3s (lightweight Kubernetes) inside Docker containers
  - Creates in seconds, no cloud account needed
  - local-path StorageClass for PVCs
  - Single load balancer (Docker port mapping)

EKS (production):
  - Managed control plane (AWS runs etcd, kube-apiserver)
  - EBS CSI driver for PVCs
  - ALB Ingress Controller for load balancers
  - IAM integration via IRSA

Your Helm charts are portable between both:
  values-local.yaml  → k3d settings
  values.yaml        → EKS settings
```
