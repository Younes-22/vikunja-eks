variable "private_subnet_ids" {
  description = "private subnets id"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID of the VPC hosting the EKS cluster"
  type        = string
}

variable "eks_viewer_principal_arn" {
  description = "IAM role ARN granted read-only access to Kubernetes resources"
  type        = string
  default     = null
}

variable "route53_zone_arn" {
  description = "ARN of the Route 53 hosted zone managed by ExternalDNS"
  type        = string
}