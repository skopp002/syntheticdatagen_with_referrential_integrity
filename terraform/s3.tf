resource "aws_s3_bucket" "s3_glue_assets" {
  bucket = "aws-glue-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-apg"
  tags = {
    Name        = "aws-glue-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-apg"
    Environment = "Demo"
  }
}

//s3 bucket server side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_glue_assets_encryption" {
  bucket = aws_s3_bucket.s3_glue_assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "s3_datagen" {
  bucket = "synthetic-datagen-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-apg"
  tags = {
    Name        = "synthetic-datagen-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-apg"
    Environment = "Demo"
  }
}

//s3 bucket server side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_datagen_encryption" {
  bucket = aws_s3_bucket.s3_datagen.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "generator_config" {
  for_each = fileset("${path.root}/../src/config/", "*")
  bucket = aws_s3_bucket.s3_datagen.id
  key    = "generatorConfig/${each.value}"
  source = "${path.root}/../src/config/${each.value}"
  etag = filemd5("${path.root}/../src/config/${each.value}")
}

resource "aws_s3_object" "generator_config_schema" {
  for_each = fileset("${path.root}/../setup/schemafiles/", "*")
  bucket = aws_s3_bucket.s3_datagen.id
  key    = "generatorConfig/schema/${each.value}"
  source = "${path.root}/../setup/schemafiles/${each.value}"
  etag = filemd5("${path.root}/../setup/schemafiles/${each.value}")
}

resource "aws_s3_object" "generator_config_lib" {
  for_each = fileset("${path.root}/../libs/", "*")
  bucket = aws_s3_bucket.s3_datagen.id
  key    = "generatorConfig/libs/${each.value}"
  source = "${path.root}/../libs/${each.value}"
}

resource "aws_s3_object" "scripts" {
  for_each = fileset("${path.root}/../src/generators/", "*")
  bucket = aws_s3_bucket.s3_datagen.id
  key    = "scripts/${each.value}"
  source = "${path.root}/../src/generators/${each.value}"
}