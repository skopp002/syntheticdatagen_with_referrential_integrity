//Create AWS Glue Database 
resource "aws_glue_catalog_database" "aws_glue_catalog_database" {
  name = var.glue_database
  location_uri = "s3://${aws_s3_bucket.s3_datagen.id}/aws-glue/"
}


resource "aws_glue_job" "datagenerator" {
    name     = "datagenerator.py"
    role_arn = aws_iam_role.glue_connection_role.arn
    glue_version = "4.0"
    worker_type  = "G.1X"
    number_of_workers=10
    max_retries = 0
    timeout = 2880
    security_configuration = aws_glue_security_configuration.glue_security_config_common.name

  command {
    script_location = "s3://${aws_s3_bucket.s3_datagen.id}/scripts/datagenerator.py"
  }

  default_arguments = {
    "--enable-job-insights" = "false"
    "--enable-metrics" = "true"
    "--enable-observability-metrics" = "true"
    "--enable-spark-ui" = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog" = "true"
    "--TempDir" = "s3://${aws_s3_bucket.s3_glue_assets.id}/temporary/"
    "--appname" = "remotegenerator"
    "--config_bucket" = "${aws_s3_bucket.s3_datagen.id}"
    "--config_file" = "generatorConfig/datagenerator_config.yaml"
    "--dbschema" = "syntheticdata"
    "--rowcount" =  10000
    "--secretname" ="' '"
    "--secretregion" = "''"
    "--startingid" = 500
    "--version" = 1
    "--extra-py-files" = "s3://${aws_s3_bucket.s3_datagen.id}/generatorConfig/libs/dbldatagen-0.4.0.post1-py3-none-any.whl"
  }
}


resource "aws_glue_job" "dynamodb_generator" {
    name     = "dynamodb_generator.py"
    role_arn = aws_iam_role.glue_connection_role.arn
    glue_version = "4.0"
    worker_type  = "G.1X"
    number_of_workers=10
    max_retries = 0
    timeout = 2880
    security_configuration = aws_glue_security_configuration.glue_security_config_common.name

  command {
    script_location = "s3://${aws_s3_bucket.s3_datagen.id}/scripts/dynamodb_generator.py"
  }

  default_arguments = {
    "--enable-job-insights" = "false"
    "--enable-metrics" = "true"
    "--enable-observability-metrics" = "true"
    "--enable-spark-ui" = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog" = "true"
    "--TempDir" = "s3://${aws_s3_bucket.s3_glue_assets.id}/temporary/"
    "--config_bucket" = "${aws_s3_bucket.s3_datagen.id}"
    "--config_file" = "generatorConfig/dynamodb_generator.yaml"
    "--dynamodb_table" = var.dynamodb_table_name
    "--keyfilepath" = "s3://${aws_s3_bucket.s3_datagen.id}/datageneratorkeys/remotegenerator/version=1"
    "--extra-py-files" = "s3://${aws_s3_bucket.s3_datagen.id}/generatorConfig/libs/nested_lookup-0.2.25-py3-none-any.whl"
  }
}

resource "aws_glue_security_configuration" "glue_security_config_common" {
  name = "glue_security_config_common"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn = module.kms.key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn = module.kms.key_arn
    }

    s3_encryption {
      kms_key_arn = module.kms.key_arn
      s3_encryption_mode = "SSE-KMS"
    }
  }
}

