# ---------------------------- VPC Flow Logs Setup ----------------------------

# Fetch VPC info from Terraform Remote State
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state-vpc"
    key    = "vpc/terraform.tfstate"
    region = "eu-north-1"
  }
}

# S3 Bucket for storing VPC Flow Logs
resource "aws_s3_bucket" "flow_log_bucket" {
  bucket = "vpc-flow-logs-scanner"

  lifecycle {
    prevent_destroy = true
  }

  force_destroy = false

  tags = {
    Name = "For AI Scanner"
  }
}

# Configure S3 Bucket Ownership
resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.flow_log_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Set S3 ACL to Private
resource "aws_s3_bucket_acl" "acl" {
  depends_on = [aws_s3_bucket_ownership_controls.ownership]
  bucket     = aws_s3_bucket.flow_log_bucket.id
  acl        = "private"
}

# Enable VPC Flow Logs to S3
resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = aws_s3_bucket.flow_log_bucket.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = data.terraform_remote_state.vpc.outputs.vpc_id
}

# IAM Role for Flow Logs to Write to S3
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "flow_logs_role" {
  name               = "vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "flow_logs_policy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_log_bucket.arn}/*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_attachment" {
  name   = "vpc-flow-logs-policy"
  role   = aws_iam_role.flow_logs_role.id
  policy = data.aws_iam_policy_document.flow_logs_policy.json
}

# ---------------------------- Athena And Glue Setup ----------------------------

# https://nocode.autify.com/blog/optimizing-cloud-application-log-management
# https://signoz.io/guides/vpc-flow-logs/

# S3 Bucket for Athena query results
resource "aws_s3_bucket" "athena_results_bucket" {
  bucket = "vpc-flow-logs-athena-querylogs-results"
}

# AWS Glue Database for Athena
resource "aws_glue_catalog_database" "flow_logs_db" {
  name = "vpc_flow_logs_db"
}

# Glue Table for Athena to Access Flow Logs
resource "aws_glue_catalog_table" "flow_logs_table" {
  name          = "vpc_flow_logs_table"
  database_name = aws_glue_catalog_database.flow_logs_db.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.flow_log_bucket.id}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "FALSE",
        "mapping.timestamp"     = "start_time",
        "mapping.srcaddr"       = "srcaddr",
        "mapping.dstaddr"       = "dstaddr",
        "mapping.srcport"       = "srcport",
        "mapping.dstport"       = "dstport",
        "mapping.protocol"      = "protocol",
        "mapping.packets"       = "packets",
        "mapping.bytes"         = "bytes",
        "mapping.action"        = "action",
        "mapping.log_status"    = "log_status"
      }
    }

    columns {
      name = "version"
      type = "string"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "interface_id"
      type = "string"
    }
    columns {
      name = "srcaddr"
      type = "string"
    }
    columns {
      name = "dstaddr"
      type = "string"
    }
    columns {
      name = "srcport"
      type = "int"
    }
    columns {
      name = "dstport"
      type = "int"
    }
    columns {
      name = "protocol"
      type = "int"
    }
    columns {
      name = "packets"
      type = "bigint"
    }
    columns {
      name = "bytes"
      type = "bigint"
    }
    columns {
      name = "start_time"
      type = "bigint"
    }
    columns {
      name = "end_time"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "log_status"
      type = "string"
    }
  }
}

# Athena Workgroup for Query Execution
resource "aws_athena_workgroup" "flow_logs_workgroup" {
  name          = "vpc_flow_logs_workgroup"
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results_bucket.id}/athena-results/"
    }
  }
}

# Athena Query to Detect Suspicious Traffic (DDoS, SSH Bruteforce)
resource "aws_athena_named_query" "detect_ddos" {
  name        = "detect_ddos_attacks"
  database    = aws_glue_catalog_database.flow_logs_db.name
  description = "Detects high packet count connections (DDoS-like behavior)"
  query       = <<EOT
                SELECT srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes
                FROM vpc_flow_logs_table
                WHERE packets > 10000
                ORDER BY packets DESC
                LIMIT 100;
                EOT
}

# IAM Policy for Athena to Read from S3
resource "aws_iam_policy" "athena_s3_access" {
  name        = "AthenaS3AccessPolicy"
  description = "Allows Athena to read VPC Flow Logs from S3"
  policy      = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "${aws_s3_bucket.flow_log_bucket.arn}",
        "${aws_s3_bucket.flow_log_bucket.arn}/*"
      ]
    }
  ]
}
EOT
}

resource "aws_iam_role_policy_attachment" "attach_athena_s3" {
  role       = aws_iam_role.flow_logs_role.name
  policy_arn = aws_iam_policy.athena_s3_access.arn
}
