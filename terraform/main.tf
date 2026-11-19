module "vpc" {
  source = "./modules/vpc"
}

module "eks" {
  source                   = "./modules/eks"
  vpc_cidr                 = module.vpc.vpc_cidr
  private_subnet_ids       = module.vpc.private_subnets_ids
  eks_viewer_principal_arn = var.eks_viewer_principal_arn
  route53_zone_arn         = aws_route53_zone.labs.arn
}