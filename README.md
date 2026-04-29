# AWS YouTube Data Pipeline

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E6.0-FF9900?logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

An end-to-end, serverless data pipeline that ingests YouTube API data, transforms it through a **Bronze → Silver → Gold** medallion architecture, and makes it queryable via Amazon Athena — all orchestrated by AWS Step Functions and fully provisioned with Terraform.

---

## Table of Contents

- [Architecture](#architecture)
- [Services Used](#services-used)
- [Pipeline Flow](#pipeline-flow)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Input Variables](#input-variables)
- [Outputs](#outputs)
- [Deployment](#deployment)
- [Teardown](#teardown)
- [Known Issues / Limitations](#known-issues--limitations)
- [License](#license)

---

## Architecture

```
                          ┌──────────────────────────────────────────────┐
                          │           AWS Step Functions                  │
                          │         YoutubeDataPipelineWorkflow           │
                          └───────┬──────────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────────────┐
          ▼                       ▼                               ▼
 ┌─────────────────┐   ┌──────────────────────┐     ┌───────────────────────┐
 │ Lambda          │   │ Lambda               │     │ Lambda                │
 │ youtube-api-    │   │ json-to-parquet       │     │ data-quality-lambda   │
 │ ingestion       │   │                      │     │                       │
 └────────┬────────┘   └────────────┬─────────┘     └──────────────┬────────┘
          │                         │                               │
          ▼                         ▼                               ▼
  ┌──────────────┐         ┌────────────────┐           ┌──────────────────┐
  │ S3           │         │ S3             │           │ S3               │
  │ bronze-bucket│ ──────► │ silver-bucket  │ ────────► │ gold-bucket      │
  └──────┬───────┘         └───────┬────────┘           └────────┬─────────┘
         │                         │                              │
         ▼                         ▼                              ▼
  ┌──────────────┐        ┌─────────────────┐          ┌──────────────────┐
  │ Glue Crawler │        │ Glue Job        │          │ Glue Job         │
  │ (bronze)     │        │ bronze_to_silver│          │ silver_to_gold   │
  └──────────────┘        └─────────────────┘          └────────┬─────────┘
                                                                 │
                          ┌──────────────────────────────────────┘
                          ▼
                  ┌───────────────┐        ┌──────────────────┐
                  │ Glue Data     │        │ Amazon Athena     │
                  │ Catalog       │◄──────►│ (athena-glue-wg)  │
                  │ silver-db     │        └──────────────────┘
                  │ gold-db       │
                  └───────────────┘

                          ┌───────────────────────────────┐
                          │  EventBridge                   │
                          │  job-state-change-rule         │
                          │  (MediaConvert state changes)  │
                          └──────────────┬────────────────┘
                                         ▼
                              ┌────────────────────┐
                              │ SNS                 │
                              │ yt-data-pipeline-   │
                              │ alerts (email)      │
                              └─────────────────────┘
```

---

## Services Used

| Service | Purpose |
|---|---|
| **Amazon S3** | Medallion storage layers (Bronze / Silver / Gold), Lambda deployment packages, Glue ETL scripts, Athena query results |
| **AWS Lambda** | YouTube API ingestion, JSON-to-Parquet conversion, data quality checks |
| **AWS Glue** | ETL jobs (`bronze_to_silver`, `silver_to_gold`), Glue Crawler, Data Catalog (`silver-db`, `gold-db`) |
| **AWS Step Functions** | End-to-end pipeline orchestration (`YoutubeDataPipelineWorkflow`) |
| **Amazon Athena** | Ad-hoc SQL querying over the Gold/Silver layers via Glue Data Catalog |
| **Amazon EventBridge** | Captures MediaConvert job state change events and routes to SNS |
| **Amazon SNS** | Email alerting for pipeline events |
| **Amazon VPC** | Isolated network with public/private subnets across 3 AZs |
| **AWS IAM** | Least-privilege roles for Lambda, Glue, and Step Functions |
| **AWS MediaConvert** | Video transcoding (monitored via EventBridge) |

---

## Pipeline Flow

1. **Ingestion** — `youtube-api-ingestion` Lambda polls the YouTube Data API and lands raw JSON into the **Bronze S3 bucket**.
2. **Glue Crawler** — A Glue Crawler scans the Bronze bucket and registers the schema in the Glue Data Catalog.
3. **JSON → Parquet** — `json-to-parquet` Lambda converts raw JSON to columnar Parquet format and writes to the **Silver S3 bucket**.
4. **Data Quality** — `data-quality-lambda` validates records before promotion to the Gold layer.
5. **Bronze → Silver ETL** — Glue Job `bronze_to_silver` applies cleansing and standardisation logic, outputting to `silver-db`.
6. **Silver → Gold ETL** — Glue Job `silver_to_gold` applies business aggregations, outputting to `gold-db`.
7. **Querying** — Athena workgroup `athena-glue-wg` exposes the Glue Catalog tables for ad-hoc SQL analysis; results land in a dedicated S3 results bucket.
8. **Alerting** — EventBridge monitors MediaConvert job state changes and routes notifications to SNS, delivering email alerts to the configured address.

---

## Repository Structure

```
.
├── main.tf                          # Root module — all resource and module declarations
├── variables.tf                     # Input variable definitions
├── outputs.tf                       # Output value definitions
├── provider.tf                      # AWS & random provider configuration
├── files/
│   ├── pipeline_orchestration.json  # Step Functions ASL definition (templatefile)
│   ├── json_to_parquet.zip          # Lambda deployment package
│   ├── youtube_api_ingestion.zip    # Lambda deployment package
│   └── data_quality_lambda.zip      # Lambda deployment package
├── src/
│   └── glue_jobs/
│       ├── bronze_to_silver.py      # Glue ETL script
│       └── silver_to_gold.py        # Glue ETL script
└── modules/
    ├── vpc/                         # VPC, subnets, IGW
    ├── s3/                          # S3 bucket with CORS, versioning, notifications
    ├── lambda/                      # Lambda function
    ├── iam/                         # IAM role + inline policy
    ├── sns/                         # SNS topic + subscriptions
    ├── eventbridge/                 # EventBridge rule + target
    └── step-function/               # Step Functions state machine
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.0`
- AWS CLI configured with credentials that have sufficient IAM permissions
- A YouTube Data API v3 key stored in AWS Secrets Manager or passed as an environment variable to the ingestion Lambda
- Lambda deployment packages (`*.zip`) built and placed in `./files/` before applying
- Glue ETL scripts (`bronze_to_silver.py`, `silver_to_gold.py`) present in `./src/glue_jobs/`

---

## Input Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `region` | `string` | `us-east-1` | AWS region to deploy into |
| `notification_email` | `string` | — | Email address for SNS pipeline alerts |
| `env` | `string` | `prod` | Deployment environment label |
| `public_subnets` | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` | Public subnet CIDRs |
| `private_subnets` | `list(string)` | `["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]` | Private subnet CIDRs |
| `azs` | `list(string)` | `["us-east-1a", "us-east-1b", "us-east-1c"]` | Availability Zones |

> **Note:** `notification_email` should be overridden via a `terraform.tfvars` file or `-var` flag rather than hardcoding in `variables.tf`.

---

## Outputs

> `outputs.tf` is currently a placeholder. Recommended outputs to add:

| Output | Description |
|---|---|
| `bronze_bucket_name` | Name of the Bronze S3 bucket |
| `silver_bucket_name` | Name of the Silver S3 bucket |
| `gold_bucket_name` | Name of the Gold S3 bucket |
| `step_function_arn` | ARN of the Step Functions state machine |
| `athena_workgroup_name` | Athena workgroup name |
| `sns_topic_arn` | ARN of the alerts SNS topic |

---

## Deployment

### 1. Clone the repository

```bash
git clone https://github.com/<your-org>/aws-youtube-data-pipeline.git
cd aws-youtube-data-pipeline
```

### 2. Build Lambda packages (if not pre-built)

```bash
# Example for youtube_api_ingestion
cd src/lambda/youtube_api_ingestion
pip install -r requirements.txt -t .
zip -r ../../../files/youtube_api_ingestion.zip .
cd ../../..
```

### 3. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum set notification_email
```

### 4. Initialise and apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 5. Confirm SNS subscription

Check the inbox for `notification_email` and confirm the SNS subscription to start receiving pipeline alerts.

### 6. Trigger the pipeline

```bash
aws stepfunctions start-execution \
  --state-machine-arn <step_function_arn> \
  --region us-east-1
```

---

## Teardown

```bash
terraform destroy
```

> All S3 buckets are created with `force_destroy = true`, so Terraform will empty and delete them on destroy. **Do not use this configuration for buckets holding data you need to retain.**

---

## Known Issues / Limitations

- **`force_destroy = true` on all S3 buckets** — intentional for dev/demo use. Remove this flag for production workloads with retention requirements.
- **IAM policies use broad wildcards** — `s3:*` on Lambda and `glue:*` on the crawler role should be tightened to specific actions for production.
- **No remote state backend** — add an S3 + DynamoDB backend block in `provider.tf` before sharing this across a team.
- **`notification_email` has a hardcoded default** — override via `tfvars`; never commit real email addresses to version control.
- **Duplicate resource block** — `aws_glue_catalog_table.silver_table` is declared twice in `main.tf` (lines 448 and 453); this will cause a Terraform error and needs to be resolved (rename one to `bronze_table`).
- **`target_arn` reference mismatch** — the EventBridge module references `module.sns.topic_arn` but the SNS module is named `yt_data_pipeline_alerts`; update to `module.yt_data_pipeline_alerts.topic_arn`.

---

## License

This project is licensed under the [MIT License](./LICENSE).
