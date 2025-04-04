variable "pgdb_username" {
  default = "rds_user"
}

variable "pgdb_database_name" {
  default = "demo_postgresql_db"
}

variable "pgdb_identifier" {
  default = "demo-rds"
}
variable "dynamodb_table_name" {
  default = "employee_department_interactions"
}

variable "glue_database" {
  default = "syntheticdata_db"
}

variable "private_key" {
  description = "Path to the private key"
  default = "<>"
}

variable "public_key" {
  description = "Path to the public key"
  default = "<>"
}

variable "inbound_ssh_connection_cidr" {
  type = list
  default = ["<Specify your router IP>"]
}


variable "enable_rds" {
  default = false
}