# ### RDS
resource "aws_db_instance" "postgresql" {
  count = var.enable_rds ? 1: 0
  allocated_storage       = 20 # gigabytes
  backup_retention_period = 7 # in days
  engine                  = "postgres"
  engine_version          = "15.7"
  identifier              = var.pgdb_identifier
  db_name                 = var.pgdb_database_name
  instance_class          = "db.m5.large"
  multi_az                = false
  username                = var.pgdb_username
  password                = element(data.aws_secretsmanager_secret_version.password.*.secret_string, count.index) #random_password.pgdb.result
  port                    = 5432
  publicly_accessible     = false
  storage_encrypted       = true
  skip_final_snapshot = true
  db_subnet_group_name = element(aws_db_subnet_group.pg_subnet_group.*.name, count.index)
  depends_on = [ aws_secretsmanager_secret_version.password ]
}

resource "aws_db_subnet_group" "pg_subnet_group" {
  count = var.enable_rds ? 1: 0
  name       = "demo-rds-subnet-apg"
  subnet_ids = element(module.vpc.*.database_subnets,count.index)

  tags = {
    Name = "Demo RDS subnet"
  }
}