
# IAM policy containing the permissions required by the AWS Load Balancer Controller
resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${aws_eks_cluster.this.name}-load-balancer-controller"
  description = "Permissions for the AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

# Trust policy allowing EKS Pod Identity to assume this role
data "aws_iam_policy_document" "load_balancer_controller_assume_role" {
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

# IAM role used by the controller
resource "aws_iam_role" "load_balancer_controller" {
  name               = "${aws_eks_cluster.this.name}-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.load_balancer_controller_assume_role.json
}

# Attach the permissions to the role
resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

# Connect the IAM role to the controller's Kubernetes service account
resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn
}
