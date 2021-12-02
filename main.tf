# need to provide the region
provider "aws" {
  region = var.bolt_hive_location
}

# Random id to be added to the end of the resource names to make it unique
resource "random_id" "id" {
	  byte_length = 4
}


resource "aws_iam_role" "iam_for_bolt_hive_step_care_taker" {
  name = "iam_for_bolt_hive_step_care_taker-${random_id.id.hex}"

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
}

resource "aws_iam_policy" "hive-care-taker-policy" {
  name        = "bolt-hive-care-taker-policy-${random_id.id.hex}"
  description = "Bolt Hive Care Taker policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
                "s3:ListBucket",
                "s3:PutObject",
                "s3:GetObject",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "elasticmapreduce:AddJobFlowSteps",
                "elasticmapreduce:CancelSteps",
                "elasticmapreduce:DescribeCluster",
                "elasticmapreduce:DescribeJobFlows",
                "elasticmapreduce:DescribeStep",
                "elasticmapreduce:ListSteps"           
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach-policies-to-hive-lambda" {
  role       = aws_iam_role.iam_for_bolt_hive_step_care_taker.name
  policy_arn = aws_iam_policy.hive-care-taker-policy.arn
}


resource "aws_lambda_function" "bolt_hive_step_care_taker" {
  filename      = "Archive_bolt_hive_step_care_taker_lambda.zip"
  function_name = "bolt_hive_step_care_taker_lamdba_function-${random_id.id.hex}"
  description   = "Bolt integration for EMR Hive Lambda function"
  role          = aws_iam_role.iam_for_bolt_hive_step_care_taker.arn
  handler       = "app.lambda_handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("Archive_bolt_hive_step_care_taker_lambda.zip")
  timeout     = 840
  memory_size = 10000
  runtime = "python3.8"
    environment {
      variables = {
        BOLT_API_URL = var.bolt_api_end_point
        BOLT_STAGE_BUCKET = var.bolt_hive_stage_bucket_name
    }
  }

}


# Create a CloudWatch Event Rule to capture Hive Step alerts
resource "aws_cloudwatch_event_rule" "capture-bolt-hive-step-events" {
  name        = "capture-bolt-hive-step-events-${random_id.id.hex}"
  description = "Capture EMR Hive Step events for Bolt integration"

  event_pattern = <<EOF
{
  "source": [
    "aws.emr"
  ],
  "detail-type": [
    "EMR Step Status Change"
  ],
  "detail": {
    "state": [
      "PENDING"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "bolt-hive-lambda-target" {
  rule      = aws_cloudwatch_event_rule.capture-bolt-hive-step-events.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.bolt_hive_step_care_taker.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_events" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bolt_hive_step_care_taker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.capture-bolt-hive-step-events.arn
}
