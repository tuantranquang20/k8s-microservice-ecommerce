# ============================================================
# ecr.tf — Amazon ECR Repositories (one per service)
# ============================================================
# LEARNING NOTE: ECR is AWS's managed container registry.
# In production, CI/CD pushes tagged images here and Kubernetes
# pulls from ECR using node IAM roles (no registry credentials needed!).
# For local dev, we use k3d's local registry (k3d-local-registry:5050).

# Create one repository per service using for_each on var.services list.
# for_each is preferred over count because you can add/remove services
# without affecting unrelated repos.
resource "aws_ecr_repository" "services" {
  for_each = toset(var.services)

  name                 = "${var.cluster_name}/${each.key}"
  image_tag_mutability = "MUTABLE" # MUTABLE allows overwriting :latest — OK for dev;
  # use IMMUTABLE in prod to enforce image provenance

  # Scan images on push — ECR will report known CVEs for free
  image_scanning_configuration {
    scan_on_push = true
  }

  # Force delete even if images exist (useful during terraform destroy on learning envs)
  force_delete = true

  tags = { Name = "${var.cluster_name}-${each.key}" }
}

# ── Lifecycle Policy ──────────────────────────────────────────
# Automatically delete untagged images older than 7 days.
# Without this, ECR fills up with every CI push and you pay for storage.
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged releases"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
