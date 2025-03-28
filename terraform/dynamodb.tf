module "dynamodb_table" {
  source   = "git::https://github.com/terraform-aws-modules/terraform-aws-dynamodb-table.git?ref=0e806ea531c58517efc75b69a15951fca78b82c7"

  name     = var.dynamodb_table_name
  hash_key = "PK"
  range_key = "SK"

  attributes = [
    {
      name = "PK"
      type = "S"
    },
    {
      name = "SK"
      type = "S"
    }
  ]
  point_in_time_recovery_enabled = true
  server_side_encryption_enabled = true
  billing_mode                  = "PAY_PER_REQUEST"
  tags = {
    Terraform   = "true"
    Environment = "Example-APG"
  }
}