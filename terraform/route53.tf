resource "aws_route53_zone" "labs" {
  name = "labs.younesblog.org"

  tags = {
    Name    = "vikunja-labs"
    Project = "vikunja-eks"
  }
}

output "labs_hosted_zone_id" {
  description = "Route 53 hosted zone ID for labs.younesblog.org"
  value       = aws_route53_zone.labs.zone_id
}

output "labs_name_servers" {
  description = "Name servers to configure in Cloudflare"
  value       = aws_route53_zone.labs.name_servers
}