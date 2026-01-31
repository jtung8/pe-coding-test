data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "pe-test-ec2-sg"
  description = "Minimal SG for coding test"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "pe-coding-test-ec2"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "pe-coding-test-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "pe-coding-test-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "pe-coding-test-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowRebootThisInstance"
        Effect   = "Allow"
        Action   = ["ec2:RebootInstances"]
        Resource = [aws_instance.web.arn]
      },
      {
        Sid      = "AllowPublishToThisTopic"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.alerts.arn]
      },
      {
        Sid    = "AllowLambdaLogging"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "remediate" {
  function_name = "pe-coding-test-remediate"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID    = aws_instance.web.id
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      WEBHOOK_TOKEN  = var.webhook_token
    }
  }
}

resource "aws_lambda_function_url" "remediate_url" {
  function_name      = aws_lambda_function.remediate.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_url_invoke" {
 statement_id           = "AllowFunctionUrlInvoke"
 action                 = "lambda:InvokeFunctionUrl"
 function_name          = aws_lambda_function.remediate.function_name
 principal              = "*"
 function_url_auth_type = "NONE"
}


resource "aws_lambda_permission" "allow_invoke" {
 statement_id  = "AllowPublicInvoke"
 action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.remediate.function_name
 principal     = "*"
}
