provider "aws" {
  region = "eu-west-1"
}

provider "archive" {}

// Config Rule
resource "aws_config_config_rule" "s3_bucket_versioning" {
  name = "s3_bucket_versioning_enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
  }

  depends_on = ["aws_config_configuration_recorder.recorder"]
}

resource "aws_config_configuration_recorder" "recorder" {
  name     = "recorder"
  role_arn = "${aws_iam_role.recorder.arn}"
}

resource "aws_config_configuration_recorder_status" "status" {
  name       = "${aws_config_configuration_recorder.recorder.name}"
  is_enabled = true
  depends_on = ["aws_config_delivery_channel.s3"]
}

resource "aws_config_delivery_channel" "s3" {
  name           = "example"
  s3_bucket_name = "${aws_s3_bucket.config.bucket}"
}

resource "aws_s3_bucket" "config" {
  bucket = "awsconfig-storage"
}

resource "aws_iam_role" "recorder" {
  name = "my-awsconfig-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "policy" {
  name = "awsconfig-recorder-policy"
  role = "${aws_iam_role.recorder.id}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Action": "config:Put*",
        "Effect": "Allow",
        "Resource": "*"

    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "s3" {
  name = "awsconfig-delivery"
  role = "${aws_iam_role.recorder.id}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.config.arn}",
        "${aws_s3_bucket.config.arn}/*"
      ]
    }
  ]
}
POLICY
}

// Lambda
data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = "${data.aws_iam_policy_document.policy.json}"
}

resource "aws_iam_policy" "policy" {
  name        = "lambda-sns-publish"
  description = "Allow to publish to sns"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${aws_sns_topic.config_changes.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attachment" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.policy.arn}"
}

data "archive_file" "code" {
  type        = "zip"
  source_file = "config_changes.py"
  output_path = "config_changes_payload.zip"
}

resource "aws_lambda_function" "config_changes" {
  function_name = "config_changes"
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  handler       = "config_changes.lambda_handler"

  filename         = "${data.archive_file.code.output_path}"
  source_code_hash = "${data.archive_file.code.output_base64sha256}"

  runtime = "python3.8"

  environment {
    variables = {
      SNS_TOPIC_ARN = "${aws_sns_topic.config_changes.arn}"
    }
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.config_changes.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.console.arn}"
}

// Event Rule
resource "aws_cloudwatch_event_rule" "console" {
  name        = "capture-aws-config-compliance-changes"
  description = "Capture each AWS Config compliance change"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.config"
  ],
  "detail-type": [
    "Config Rules Compliance Change"
  ]
}
PATTERN
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = "${aws_cloudwatch_event_rule.console.name}"
  target_id = "SendToLambda"
  arn       = "${aws_lambda_function.config_changes.arn}"
}

// SNS
resource "aws_sns_topic" "config_changes" {
  name = "aws-config-changes"
}
