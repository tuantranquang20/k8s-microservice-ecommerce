# ============================================================
# waf.tf — AWS WAF v2 WebACL
# ============================================================
# LEARNING NOTE — WAF sits in front of the ALB and inspects HTTP requests
# BEFORE they reach your services. Two defences here:
#
#   1. AWSManagedRulesCommonRuleSet — AWS-curated rules blocking:
#      SQL injection, XSS, bad bots, known exploits (Log4Shell etc.)
#      Updated automatically by AWS as new threats emerge.
#
#   2. Rate-based rule — caps requests per IP to 1000 per 5 min.
#      Protects against brute-force and low-rate DDoS without
#      requiring complex custom rules.
#
# SCOPE: "REGIONAL" means this WAF is for ALBs, API GW, etc. (not CloudFront).
# For CloudFront you'd use scope = "CLOUDFRONT" and deploy to us-east-1.

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.cluster_name}-waf"
  description = "WAF protecting the ecommerce ALB"
  scope       = "REGIONAL"

  # Default action if no rules match: ALLOW the request through.
  # Rules below only BLOCK on explicit matches.
  default_action {
    allow {}
  }

  # ── Rule 1: AWS Managed Common Rule Set ─────────────────────
  # Priority 1 = evaluated first. Lower number = higher priority.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # Use the rule group's own actions (block/count)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Override specific rules from COUNT to BLOCK if needed:
        # rule_action_override { ... }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 2: AWS Managed Known Bad Inputs ────────────────────
  # Catches Log4Shell (CVE-2021-44228), SSRF patterns, and invalid
  # host header values that could bypass routing logic.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 3: Rate-Based Limiting ──────────────────────────────
  # Blocks IPs that exceed 1000 requests in any 5-minute window.
  # The block is temporary — lifted once the rate drops below the threshold.
  #
  # WHY 1000/5min: enough for legitimate users (~3 req/sec) but stops
  # scrapers and brute-force attacks. Tune based on your traffic profile.
  rule {
    name     = "RateLimitPerIP"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        # AWS WAF counts requests in 5-minute rolling windows
        limit              = var.waf_rate_limit # default: 1000
        aggregate_key_type = "IP"               # count per source IP
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  # Visibility config for the entire WebACL (not just individual rules)
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-waf-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.cluster_name}-waf" }
}

# ── CloudWatch Logging ────────────────────────────────────────
# Send WAF logs to CloudWatch for forensics and alerting.
# Log group name MUST start with "aws-waf-logs-" (AWS requirement).
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.cluster_name}"
  retention_in_days = 30 # Keep 30 days of WAF logs; reduce to save costs

  tags = { Name = "${var.cluster_name}-waf-logs" }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}
