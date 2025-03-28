variable "pgdb_username" {
  default = "rds_user_apg"
}

variable "pgdb_database_name" {
  default = "demo_postgresql_db"
}

variable "pgdb_identifier" {
  default = "demo-rds-apg"
}
variable "dynamodb_table_name" {
  default = "employee_department_interactions_apg"
}

variable "glue_database" {
  default = "syntheticdataapg_db"
}

variable "private_key" {
  description = "Path to the private key"
  default = "/Users/aaneja/.ssh/aaneja_apg"
}

variable "public_key" {
  description = "Path to the public key"
  default = "/Users/aaneja/.ssh/aaneja_apg.pub"
}

variable "inbound_ssh_connection_cidr" {
  type = list
  default = ["45.17.187.96/32"]
}

variable "sql_file_path" {
  type = string
  default = "sqls/weather_table.sql"
}

variable "enable_rds" {
  default = false
}