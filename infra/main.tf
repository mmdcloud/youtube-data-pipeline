# -------------------------------------------------------------------------
# VPC Configuration
# -------------------------------------------------------------------------
module "vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "vpc-${var.env}"
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
    Name      = "vpc-${var.env}-${var.region}"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -------------------------------------------------------------------------
# SNS Configuration
# -------------------------------------------------------------------------
module "sns" {
  source     = "./modules/sns"
  topic_name = "job-status-change-topic-${var.env}"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
  tags = {
    Name      = "job-status-change-topic-${var.env}"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -------------------------------------------------------------------------
# EventBridge Rule
# -------------------------------------------------------------------------
module "eventbridge_rule" {
  source           = "./modules/eventbridge"
  rule_name        = "job-state-change-rule-${var.env}"
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
    Name      = "mediaconvert-job-state-change-rule-${var.env}"
    ManagedBy = "terraform"
    Project   = "youtube data pipeline"
  }
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "invoices_bucket" {
  source             = "./modules/s3"
  bucket_name        = "invoices-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue = []
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
                    "textract:AnalyzeDocument"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:*"
                ],
                "Resource": [
                    "${module.invoices_bucket.arn}",
                    "${module.invoices_bucket.arn}/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query"
                ],
                "Resource": "${module.invoice_records_dynamodb.arn}"
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
                    "sqs:DeleteMessage",
                    "sqs:GetQueueAttributes",
                    "sqs:ReceiveMessage"
                ],
                "Resource": "${module.document_event_queue.arn}"
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
  handler                 = "table_sanity_check.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.table_sanity_check_function_code.bucket
  s3_key                  = "table_sanity_check.zip"
  code_signing_config_arn = ""
  layers                  = []
  depends_on              = [module.table_sanity_check_function_code]
}

module "youtube_api_integration" {
  source                  = "./modules/lambda"
  function_name           = "youtube-api-integration"
  role_arn                = module.lambda_function_iam_role.arn
  permissions             = []
  timeout                 = 60
  env_variables           = {}
  handler                 = "extract_table_data.lambda_handler"
  runtime                 = "python3.12"
  s3_bucket               = module.extract_table_data_function_code.bucket
  s3_key                  = "extract_table_data.zip"
  code_signing_config_arn = ""
  layers                  = []
  depends_on              = [module.extract_table_data_function_code]
}

# ----------------------------------------------------------------------
# Glue configuration (Crawler & Data catalog)
# ----------------------------------------------------------------------
resource "aws_glue_catalog_database" "database" {
  name        = var.glue_database_name
  description = "Glue database for incremental load"
}

resource "aws_glue_catalog_table" "table" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.database.name
}

module "glue_crawler_role" {
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
                    "${module.curated_bucket.arn}",
                    "${module.curated_bucket.arn}/*"
                  ]
            },
            {
                  "Effect"   : "Allow",
                  "Action"   : [
                    "s3:PutObject"
                  ],
                  "Resource" : "${module.athena_results.arn}"
            }
        ]
    }
    EOF
}

resource "aws_glue_crawler" "crawler" {
  database_name = aws_glue_catalog_database.database.name
  name          = var.glue_crawler_name
  role          = module.glue_crawler_role.arn
  s3_target {
    path = "s3://${module.raw_bucket.bucket}"
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
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/scripts/bronze_to_silver.py"
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
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/scripts/silver_to_gold.py"
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