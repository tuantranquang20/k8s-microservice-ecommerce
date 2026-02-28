# ============================================================
# argocd.tf — ArgoCD installed via Terraform helm_release
# ============================================================
# LEARNING NOTE — Why install ArgoCD via Terraform?
#
# "Infrastructure as code" means the cluster's initial platform
# tooling is also declared and versioned. Once ArgoCD is installed,
# it takes over managing all application deployments via GitOps.
# This is the "bootstrap" problem: someone has to install the installer!
#
# Flow:
#   terraform apply → ArgoCD installed → argocd-bootstrap.sh runs →
#   App-of-Apps registered → ArgoCD syncs all services → done.

# ── Namespace ─────────────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ── ArgoCD Helm Release ───────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.14" # Pin version for reproducibility
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # wait=true means Terraform waits until all ArgoCD pods are Running
  # before marking this resource as complete. Important because later
  # resources (like ArgoCD Applications) depend on this being ready.
  wait    = true
  timeout = 600 # 10 minutes — ArgoCD can take a while on first pull

  values = [
    yamlencode({
      # ── Server config ────────────────────────────────────────
      server = {
        # Expose ArgoCD UI via LoadBalancer for easy access in learning env.
        # In production, use an Ingress with TLS.
        service = {
          type = "ClusterIP" # use port-forward locally (scripts/port-forward.sh)
        }

        # Disable TLS on the server (we terminate TLS at the ALB/Kong layer)
        extraArgs = ["--insecure"]
      }

      # ── Global resource tracking ─────────────────────────────
      # "annotation" tracking method is more reliable than "label" in
      # environments with GitOps-managed resources.
      configs = {
        cm = {
          "application.resourceTrackingMethod" = "annotation"

          # Health checks for CRDs (Kong, Vault, etc.)
          "resource.customizations.health.argoproj.io_Application" = <<-EOT
            hs = {}
            hs.status = "Progressing"
            hs.message = ""
            if obj.status ~= nil then
              if obj.status.health ~= nil then
                hs.status = obj.status.health.status
                if obj.status.health.message ~= nil then
                  hs.message = obj.status.health.message
                end
              end
            end
            return hs
          EOT
        }

        # ── Repository server performance ────────────────────────
        repoServer = {
          resources = {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }

      # ── Redis for ArgoCD (internal caching) ──────────────────
      # ArgoCD uses its own Redis — separate from our app Redis
      redis = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# ── Platform Namespaces ───────────────────────────────────────
# Create namespaces for each environment. ArgoCD will deploy
# app manifests into these namespaces.
resource "kubernetes_namespace" "ecommerce_dev" {
  metadata {
    name = "ecommerce-dev"
    labels = {
      environment                    = "dev"
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_namespace" "ecommerce_staging" {
  metadata {
    name = "ecommerce-staging"
    labels = {
      environment                    = "staging"
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }
  depends_on = [aws_eks_node_group.main]
}
