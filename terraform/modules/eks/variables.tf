variable "private_subnet_ids" {
  description = "private subnets id"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID of the VPC hosting the EKS cluster"
  type        = string
}