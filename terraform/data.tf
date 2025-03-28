## data
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  count = var.enable_rds ? 1: 0
  state = "available"
}

data "aws_secretsmanager_secret" "db_password" {
  count = var.enable_rds ? 1: 0
  name = "apg2-rds-primary-cluster-password"
  depends_on = [ aws_secretsmanager_secret_version.password ]
}

data "aws_secretsmanager_secret_version" "password" {
  count = var.enable_rds ? 1: 0
  secret_id = element(data.aws_secretsmanager_secret.db_password.*.id,count.index)
}

data "aws_subnet" "database_subnet" {
  count = var.enable_rds ? 1: 0
  filter {
    name   = "tag:Name"
    values = ["${element(module.vpc.*.name,count.index)}-db-${element(aws_db_instance.postgresql.*.availability_zone, count.index)}"]
  }
  depends_on = [ module.vpc ]
}

