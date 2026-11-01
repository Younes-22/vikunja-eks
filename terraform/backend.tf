terraform {
  backend "s3" {
    bucket       = "vikunja-terraform-state-469465348568"
    key          = "vikunja/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}