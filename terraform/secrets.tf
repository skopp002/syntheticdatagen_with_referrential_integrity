resource "random_password" "pgdb" {
  count = var.enable_rds ? 1: 0
  length = 16
  special          = false
  override_special = "/@"
}

resource "aws_secretsmanager_secret" "db_password" {
  count = var.enable_rds ? 1: 0
  name = "apg2-rds-primary-cluster-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "password" {
  count = var.enable_rds ? 1: 0
  secret_id = element(aws_secretsmanager_secret.db_password.*.id,count.index)
  secret_string = element(random_password.pgdb.*.result,count.index)
}