output "ecr_repository_url" {
  description = "URL of the Vikunja ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "github_ecr_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_ecr.arn
}

output "github_terraform_role_arn" {
  description = "IAM role assumed by GitHub Actions to deploy Terraform infrastructure"
  value       = aws_iam_role.github_terraform.arn
}