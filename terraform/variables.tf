variable "eks_viewer_principal_arn" {
  description = "Optional IAM role ARN for read-only Kubernetes console access"
  type        = string
  default     = null
}