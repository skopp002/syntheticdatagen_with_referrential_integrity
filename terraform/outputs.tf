output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ec2_pgsql_public_fqdn" {
    value = aws_instance.ec2_psql.*.public_dns
}

output "rds_endpoint" {
    value = aws_db_instance.postgresql.*.endpoint
}

output "syn_public_key" {
    value = file(var.public_key)
}

output "rds_az" {
    value = aws_db_instance.postgresql.*.availability_zone
}

