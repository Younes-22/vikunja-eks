variable "project_name" {
  type = string
  #   default = "eks-app"
}

variable "github_oidc_subject" {
  description = "GitHub repository and branch permitted to assume the ECR publishing role"
  type        = string
}