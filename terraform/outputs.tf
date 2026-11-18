output "vpc_id" {
  description = "VPC ID. Copy into kubernetes/argo-cd/aws-load-balancer-controller.yml after each build"
  value       = module.vpc.vpc_id
}
