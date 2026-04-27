# -------------------------------------------------------------------------
# VPC Configuration
# -------------------------------------------------------------------------
module "vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "youtube-data-pipeline-vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  database_subnets        = []
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = false
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  tags = {
    Name      = "youtube-data-pipeline-vpc"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -------------------------------------------------------------------------
# SNS Configuration
# -------------------------------------------------------------------------
module "sns" {
  source     = "./modules/sns"
  topic_name = "job-status-change-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
  tags = {
    Name      = "job-status-change-topic"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -------------------------------------------------------------------------
# EventBridge Rule
# -------------------------------------------------------------------------
module "eventbridge_rule" {
  source           = "./modules/eventbridge"
  rule_name        = "job-state-change-rule"
  rule_description = "It monitors the media convert job state change event"
  event_pattern = jsonencode({
    source = [
      "aws.mediaconvert"
    ]
    detail-type = [
      "MediaConvert Job State Change"
    ]
  })
  target_id  = "MediaConvertJobStateChange"
  target_arn = module.sns.topic_arn
  tags = {
    Name      = "mediaconvert-job-state-change-rule"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "bronze_bucket" {
  source             = "./modules/s3"
  bucket_name        = "bronze-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "silver_bucket" {
  source             = "./modules/s3"
  bucket_name        = "silver-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "gold_bucket" {
  source             = "./modules/s3"
  bucket_name        = "gold-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "json_to_parquet_function_code" {
  source      = "./modules/s3"
  bucket_name = "json-to-parquet-function-code-${random_id.id.hex}"
  objects = [
    {
      key    = "json_to_parquet.zip"
      source = "./files/json_to_parquet.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "youtube_api_ingestion_function_code" {
  source      = "./modules/s3"
  bucket_name = "youtube-api-ingestion-function-code-${random_id.id.hex}"
  objects = [
    {
      key    = "youtube_api_ingestion.zip"
      source = "./files/youtube_api_ingestion.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "data_quality_lambda_function_code" {
  source      = "./modules/s3"
  bucket_name = "data-quality-lambda-function-code-${random_id.id.hex}"
  objects = [
    {
      key    = "data_quality_lambda.zip"
      source = "./files/data_quality_lambda.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "etl_scripts" {
  source      = "./modules/s3"
  bucket_name = "etl-scripts-${random_id.id.hex}"
  objects = [
    {
      key  = "scripts/bronze_to_silver.py"
      path = "${path.module}/../src/glue_jobs/bronze_to_silver.py"
    },
    {
      key  = "scripts/silver_to_gold.py"
      path = "${path.module}/../src/glue_jobs/silver_to_gold.py"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

# -----------------------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------------------
module "lambda_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "lambda-function-iam-role"
  role_description   = "lambda-function-iam-role"
  policy_name        = "lambda-function-iam-policy"
  policy_description = "lambda-function-iam-policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:*"
                ],
                "Resource": [
                    "${module.bronze_bucket.arn}",
                    "${module.bronze_bucket.arn}/*",
                    "${module.silver_bucket.arn}",
                    "${module.silver_bucket.arn}/*",
                    "${module.gold_bucket.arn}",
                    "${module.gold_bucket.arn}/*"
                ]
            }
        ]
    }
    EOF
}

module "step_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "start-step-function-iam-role"
  role_description   = "start-step-function-iam-role"
  policy_name        = "start-step-function-iam-policy"
  policy_description = "start-step-function-iam-policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "states:StartExecution"
                ],
                "Resource": "${module.step_function.arn}"
            }
        ]
    }
    EOF
}

module "json_to_parquet" {
  source                  = "./modules/lambda"
  function_name           = "json-to-parquet"
  role_arn                = module.lambda_function_iam_role.arn
  permissions             = []
  env_variables           = {}
  timeout                 = 60
  handler                 = "lambda.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.json_to_parquet_function_code.bucket
  s3_key                  = "json_to_parquet.zip"
  code_signing_config_arn = ""
  layers                  = []
  depends_on              = [module.json_to_parquet_function_code]
}

module "youtube_api_ingestion" {
  source                  = "./modules/lambda"
  function_name           = "youtube-api-ingestion"
  role_arn                = module.lambda_function_iam_role.arn
  permissions             = []
  timeout                 = 60
  env_variables           = {}
  handler                 = "lambda.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.youtube_api_ingestion_function_code.bucket
  s3_key                  = "youtube_api_ingestion.zip"
  code_signing_config_arn = ""
  layers                  = []
  depends_on              = [module.youtube_api_ingestion_function_code]
}

module "data_quality_lambda" {
  source                  = "./modules/lambda"
  function_name           = "data-quality-lambda"
  role_arn                = module.lambda_function_iam_role.arn
  permissions             = []
  timeout                 = 60
  env_variables           = {}
  handler                 = "lambda.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.data_quality_lambda_function_code.bucket
  s3_key                  = "data_quality_lambda.zip"
  code_signing_config_arn = ""
  layers                  = []
  depends_on              = [module.data_quality_lambda_function_code]
}

# ----------------------------------------------------------------------
# Glue configuration (Crawler & Data catalog)
# ----------------------------------------------------------------------
resource "aws_glue_catalog_database" "silver_catalog_db" {
  name        = "silver-catalog-db"
  description = "Glue database for Silver layer"
}

resource "aws_glue_catalog_database" "gold_catalog_db" {
  name        = "gold-catalog-db"
  description = "Glue database for Gold layer"
}

resource "aws_glue_catalog_table" "silver_table" {
  name          = "silver-table"
  database_name = aws_glue_catalog_database.silver_catalog_db.name
}

resource "aws_glue_catalog_table" "gold_table" {
  name          = "gold-table"
  database_name = aws_glue_catalog_database.gold_catalog_db.name
}

module "bronze_glue_crawler_role" {
  source             = "./modules/iam"
  role_name          = "glue-crawler-role-${random_id.id.hex}"
  role_description   = "IAM role for Glue crawler"
  policy_name        = "glue-crawler-role-policy-${random_id.id.hex}"
  policy_description = "IAM policy for Glue crawler"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "glue.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            },
            {
                  "Effect"   : "Allow",
                  "Action"   : [
                    "glue:*"
                  ],
                  "Resource" : "*"
            },
            {
                  "Effect"   : "Allow",
                  "Action"   : [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                  ],
                  "Resource" : [
                    "${module.bronze_bucket.arn}",
                    "${module.bronze_bucket.arn}/*"
                  ]
            }
        ]
    }
    EOF
}

resource "aws_glue_crawler" "bronze_glue_crawler" {
  database_name = aws_glue_catalog_database.silver_catalog_db.name
  name          = "bronze-glue-crawler"
  role          = module.bronze_glue_crawler_role.arn
  s3_target {
    path = "s3://${module.bronze_bucket.bucket}"
  }
}

# -----------------------------------------------------------------------------------------
# Glue Job Configuration
# -----------------------------------------------------------------------------------------
resource "aws_iam_role" "glue_job_role" {
  name = "my-glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

# Attach the standard Glue Service policy
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_glue_job" "bronze_to_silver" {
  name     = "bronze-to-silver"
  role_arn = aws_iam_role.glue_job_role.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${module.etl_scripts.bucket}/scripts/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/logs-v2/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
  }
}

resource "aws_glue_job" "silver_to_gold" {
  name     = "silver-to-gold"
  role_arn = aws_iam_role.glue_job_role.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${module.etl_scripts.bucket}/scripts/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/logs-v2/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
  }
}

# -----------------------------------------------------------------------------------------
# Step Function Configuration
# -----------------------------------------------------------------------------------------
module "step_function" {
  source   = "./modules/step-function"
  name     = "InvoiceProcessingWorkflow"
  role_arn = module.step_function_iam_role.arn
  definition = templatefile("${path.module}/files/pipeline_orchestration.json", {
    table_sanity_check_function_arn = module.table_sanity_check_function.arn
    extract_table_data_function_arn = module.extract_table_data_function.arn
    invalid_invoice_error_topic_arn = module.invalid_invoice_error_topic.topic_arn
    data_storage_failure_topic_arn  = module.data_storage_failure_topic.topic_arn
  })
}
