# Create the IAM role for Glue to RDS connection
resource "aws_iam_role" "glue_connection_role" {
  name = "glue_connection_role_apg"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "glue_connection_role"
    Purpose = "Allow Glue Jobs to connect to AWS resources"
  }
}

# Attach the AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_connection_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}


# IAM policy to allow a GLUE ETL jobs to access an RDS instance where the ARN of the RDS instance is 
# arn:aws:rds:us-east-1:354050063238:db:demo-rds-apg
resource "aws_iam_policy" "glue_rds_access" {
  count = var.enable_rds ? 1: 0
  name        = "GlueRDSAccessPolicy"
  path        = "/"
  description = "IAM policy for Glue to access RDS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:ExecuteStatement",
          "rds-data:RollbackTransaction"
        ]
        Resource = [
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.pgdb_identifier}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [ element(aws_secretsmanager_secret.db_password.*.arn,count.index)]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_rds_access" {
  count = var.enable_rds ? 1: 0
  role       = aws_iam_role.glue_connection_role.name
  policy_arn = element(aws_iam_policy.glue_rds_access.*.arn,count.index)
}


resource "aws_iam_policy" "glue_cloudwatch_logs_policy" {
  name        = "GlueCloudWatchLogsPolicy"
  path        = "/"
  description = "IAM policy for Glue to access CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:AssociateKmsKey"
        ]
        Resource = [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/glue_security_config_common-role/glue_connection_role_apg/error:log-stream:*",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/glue_security_config_common-role/glue_connection_role_apg/output:log-stream:*",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/logs-v2-glue_security_config_common:*"
      ]

      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_cloudwatch_logs_policy_attachment" {
  role       = aws_iam_role.glue_connection_role.name
  policy_arn = aws_iam_policy.glue_cloudwatch_logs_policy.arn
} 

// Customer manager policy dynamodb_synthetic_dataGen 
resource "aws_iam_policy" "dynamodb_synthetic_dataGen" {
  name        = "dynamodb_synthetic_dataGen"
  description = "DynamoDB Policy for Synthetic Data Generation"


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "dynamodb:*"
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables",
          "dynamodb:ListGlobalTables",
          "dynamodb:DescribeGlobalTable"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}/index/*"
        ]
      }
    ]
  })
}


// Attach dynamodb_synthetic_dataGen IAM policy to the glue_connection_role role
resource "aws_iam_role_policy_attachment" "dynamodb_synthetic_dataGen_attachment" {
  role       = aws_iam_role.glue_connection_role.name
  policy_arn = aws_iam_policy.dynamodb_synthetic_dataGen.arn
}


// Customer managed IAM policy s3access
resource "aws_iam_policy" "s3access" {
  name        = "s3access"
  description = "S3 Access Policy"

  policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
                  "s3:ListBucket",
                  "s3:GetObject",
                  "s3:PutObject",
                  "s3:DeleteObject"
          ]
          Resource = [
                  "arn:aws:s3:::${aws_s3_bucket.s3_datagen.id}",
                  "arn:aws:s3:::${aws_s3_bucket.s3_datagen.id}/*",
                  "arn:aws:s3:::${aws_s3_bucket.s3_glue_assets.id}",
                  "arn:aws:s3:::${aws_s3_bucket.s3_glue_assets.id}/*"
          ]
        }
      ]
  })
}

// Attach the s3access policy to the glue_connection_role role
resource "aws_iam_role_policy_attachment" "s3access_attachment" {
  role       = aws_iam_role.glue_connection_role.name
  policy_arn = aws_iam_policy.s3access.arn
}