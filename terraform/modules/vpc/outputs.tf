output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnets_ids" {
  value = [
    aws_subnet.public["public-subnet-1"].id,
    aws_subnet.public["public-subnet-2"].id
  ]
}

output "private_subnets_ids" {
  value = [
    aws_subnet.private["private-subnet-1"].id,
    aws_subnet.private["private-subnet-2"].id
  ]
}

# output "public_subnet_1_id" {
#   value = aws_subnet.public["public-subnet-1"].id
# }

# output "public_subnet_2_id" {
#   value = aws_subnet.public["public-subnet-2"].id
# }

# output "private_subnet_1_id" {
#   value = aws_subnet.private["private-subnet-1"].id
# }

# output "private_subnet_2_id" {
#   value = aws_subnet.private["private-subnet-2"].id
# }