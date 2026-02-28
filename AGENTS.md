# AGENTS.md — E-Commerce Microservice Platform

## Project Overview
A Kubernetes-based e-commerce microservice platform deployed on AWS EKS.
Built for hands-on learning of cloud-native patterns.

## Architecture
- 6 microservices: user-service, product-service, order-service,
  payment-service, notification-service, api-gateway-bff
- IaC: Terraform with LOCAL state backend (NO S3, NO DynamoDB)
- GitOps: GitHub Actions + Helm + ArgoCD (App-of-Apps pattern)
- API Gateway: Kong Gateway
- Secrets: HashiCorp Vault with Kubernetes Auth
- Observability: Prometheus + Grafana + (future) Tempo + Loki

## Tech Stack per Service
- user-service: Node.js + Express + PostgreSQL
- product-service: Python + FastAPI + MongoDB
- order-service: Go + PostgreSQL
- payment-service: Rust + Actix-web
- notification-service: Node.js + Redis Pub/Sub
- api-gateway-bff: Python + FastAPI

## Directory Structure
/infrastructure/terraform/   # Terraform IaC, local state
/services/<name>/            # Service source code + Dockerfile
/helm-charts/<name>/         # Helm chart per service
/argocd/apps/                # ArgoCD App-of-Apps manifests
/platform/kong/              # Kong plugins and config
/platform/vault/             # Vault policies and roles
/platform/observability/     # Prometheus rules, Grafana dashboards
/scripts/                    # Shell scripts (NO Makefile)

## Essential Commands
# Local development (macOS Intel, no Homebrew)
k3d cluster create ecommerce-local --servers 1 --agents 2 \
  --port "80:80@loadbalancer" \
  --registry-use k3d-local-registry:5050 \
  --k3s-arg "--disable=traefik@server:0"

skaffold dev --profile=local   # hot-reload dev mode
skaffold run --profile=local   # one-time deploy

# Infrastructure
./scripts/infra-init.sh        # terraform init + validate
./scripts/infra-apply.sh       # terraform apply
./scripts/destroy.sh           # terraform destroy

# Platform
./scripts/argocd-bootstrap.sh  # install ArgoCD + register apps
./scripts/vault-setup.sh       # configure Vault auth + secrets
./scripts/port-forward.sh      # expose Grafana, ArgoCD, Kong UI

## Coding Conventions
- All shell scripts use `set -e` at the top
- Terraform: always run `terraform fmt` before committing
- Helm values files: `values.yaml` for defaults,
  `values-local.yaml` for k3d overrides,
  `values-prod.yaml` for EKS/production
- Docker images: always use multi-stage builds
- Every service MUST expose `/health` and `/metrics` endpoints
- No hardcoded secrets anywhere — use Vault or environment variables

## Constraints — NEVER violate these
- Terraform backend: LOCAL ONLY (no S3, no DynamoDB)
- No Makefile — use .sh scripts in /scripts/ only
- No Homebrew commands in scripts (macOS Intel, binary installs only)
- Do not expose any service directly — all external traffic goes through Kong
- Do not commit .env files — only .env.example

## Local vs Production Differences
| Config         | Local (k3d)                    | Production (EKS)         |
|----------------|--------------------------------|--------------------------|
| Image registry | k3d-local-registry:5050        | AWS ECR URL              |
| Ingress        | NodePort                       | AWS ALB                  |
| Storage        | local-path provisioner         | EBS CSI driver           |
| State backend  | local (terraform.tfstate)      | (future) S3 + DynamoDB   |
| Vault mode     | dev mode                       | HA with Raft storage     |

## Current Status
- [ ] Infrastructure: Terraform EKS + VPC
- [ ] Services: all 6 services with Dockerfile
- [ ] Helm charts: all services
- [ ] CI/CD: GitHub Actions + ArgoCD
- [ ] Platform: Kong, Vault, Prometheus/Grafana
- [ ] Service Mesh: Istio (planned Phase 2)
- [ ] Distributed Tracing: Tempo + OpenTelemetry (planned Phase 2)
- [ ] Kafka: replace Redis Pub/Sub (planned Phase 3)
