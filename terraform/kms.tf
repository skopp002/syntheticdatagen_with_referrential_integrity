module "kms" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=c20bffd41ce9716140cb9938faf0aa147b38ca2a"

  description         = "KMS key for glue security config"
  enable_key_rotation = false
  create_external     = false
  key_usage           = "ENCRYPT_DECRYPT"

  # assign users to manage and use the key
  key_owners         = []
  key_administrators = []
  key_users          = []
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.glue_connection_role.arn,
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        },
        Action = [
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ],
        Resource = "*"
      }
    ]
  })
  
  # each key can have multiple aliases with different permissions
  aliases                 = []
  aliases_use_name_prefix = true
}