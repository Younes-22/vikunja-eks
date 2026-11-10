
# IAM policy containing the Route 53 permissions required by ExternalDNS
data "aws_iam_policy_document" "external_dns" {
  # Allow ExternalDNS to discover hosted zones
  statement {
    sid    = "ListHostedZones"
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName"
    ]

    resources = ["*"]
  }

  # Allow ExternalDNS to manage DNS records only in our labs hosted zone
  statement {
    sid    = "ManageLabsDnsRecords"
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]

    resources = [var.route53_zone_arn]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${aws_eks_cluster.this.name}-external-dns"
  description = "Permissions for ExternalDNS to manage records in the labs Route 53 hosted zone"

  policy = data.aws_iam_policy_document.external_dns.json
}

# Trust policy allowing EKS Pod Identity to assume this role
data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

# IAM role used by ExternalDNS
resource "aws_iam_role" "external_dns" {
  name               = "${aws_eks_cluster.this.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json
}

# Attach Route 53 permissions to the role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# Connect the IAM role to ExternalDNS's Kubernetes service account
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}
