resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name = "${var.project_name}-github-oidc"
  }
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.github_oidc_subject]
    }
  }
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "${var.project_name}-ecr-push"
  role = aws_iam_role.github_ecr.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

resource "aws_iam_role" "github_ecr" {
  name               = "${var.project_name}-github-ecr-role"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}


# Account and resource ARNs used by the GitHub Terraform policy
data "aws_caller_identity" "current" {}

locals {
  terraform_state_bucket = "vikunja-terraform-state-667998414355"
  terraform_state_key    = "vikunja/terraform.tfstate"

  cluster_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-cluster-example"
  node_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/node-role"

  cluster_arn = "arn:aws:eks:eu-west-2:${data.aws_caller_identity.current.account_id}:cluster/eks-cluster"

  nodegroup_arn = "arn:aws:eks:eu-west-2:${data.aws_caller_identity.current.account_id}:nodegroup/eks-cluster/*/*"
  addon_arn     = "arn:aws:eks:eu-west-2:${data.aws_caller_identity.current.account_id}:addon/eks-cluster/*/*"

  nodegroup_service_linked_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
  ebs_csi_role_arn                  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-ebs-csi-driver-role"
}

# GitHub Actions Terraform permissions
data "aws_iam_policy_document" "github_terraform" {

  # VPC and networking resources
  statement {
    sid    = "ManageVpcInfrastructure"
    effect = "Allow"

    actions = [
      "ec2:AllocateAddress",
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteNatGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteTags",
      "ec2:DeleteVpc",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNatGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:DisassociateRouteTable",
      "ec2:DetachInternetGateway",
      "ec2:ModifySubnetAttribute",
      "ec2:ReleaseAddress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeAddressesAttribute",
      "ec2:DisassociateAddress"
    ]

    resources = ["*"]
  }

  # EKS cluster creation and listing
  statement {
    sid    = "CreateAndListEksCluster"
    effect = "Allow"

    actions = [
      "eks:CreateCluster",
      "eks:ListClusters"
    ]

    resources = ["*"]
  }

  # Manage the named cluster
  statement {
    sid    = "ManageEksCluster"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
      "eks:DeleteCluster",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:ListTagsForResource",
      "eks:TagResource",
      "eks:UntagResource"
    ]

    resources = [local.cluster_arn]
  }

  # Managed node group operations
  statement {
    sid    = "ManageEksNodeGroup"
    effect = "Allow"

    actions = [
      "eks:CreateNodegroup",
      "eks:DescribeNodegroup",
      "eks:DeleteNodegroup",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateNodegroupVersion",
      "eks:ListNodegroups"
    ]

    resources = [
      local.cluster_arn,
      local.nodegroup_arn
    ]
  }

  # EKS add-on operations
  statement {
    sid    = "ManageEksAddons"
    effect = "Allow"

    actions = [
      "eks:CreateAddon",
      "eks:DescribeAddon",
      "eks:DeleteAddon",
      "eks:UpdateAddon",
      "eks:ListAddons"
    ]

    resources = [
      local.cluster_arn,
      local.addon_arn
    ]
  }

  # Manage only the cluster and node IAM roles used by this project
  statement {
    sid    = "ManageEksIamRoles"
    effect = "Allow"

    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:ListInstanceProfilesForRole",
      "iam:DeleteRole",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy"
    ]

    resources = [
      local.cluster_role_arn,
      local.node_role_arn,
      local.ebs_csi_role_arn,
      local.nodegroup_service_linked_role_arn
    ]
  }

  # Allow EKS to receive the two roles from Terraform
  statement {
    sid       = "PassEksRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.cluster_role_arn, local.node_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  # Manage EKS access entries and access policies
  statement {
    sid    = "ManageEksAccessEntries"
    effect = "Allow"

    actions = [
      "eks:CreateAccessEntry",
      "eks:DescribeAccessEntry",
      "eks:DeleteAccessEntry",
      "eks:ListAccessEntries",
      "eks:AssociateAccessPolicy",
      "eks:DisassociateAccessPolicy",
      "eks:ListAssociatedAccessPolicies"
    ]

    resources = ["*"]
  }

  # Access the remote Terraform state bucket
  statement {
    sid    = "AccessTerraformStateBucket"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${local.terraform_state_bucket}"
    ]
  }

  # Access state and its S3 lock file
  statement {
    sid    = "AccessTerraformStateObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::${local.terraform_state_bucket}/${local.terraform_state_key}",
      "arn:aws:s3:::${local.terraform_state_bucket}/${local.terraform_state_key}.tflock"
    ]
  }
}

resource "aws_iam_policy" "github_terraform" {
  name        = "${var.project_name}-github-terraform-policy"
  description = "Permissions for GitHub Actions to manage Vikunja EKS infrastructure"
  policy      = data.aws_iam_policy_document.github_terraform.json
}

resource "aws_iam_role" "github_terraform" {
  name               = "${var.project_name}-github-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "github_terraform" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform.arn
}
