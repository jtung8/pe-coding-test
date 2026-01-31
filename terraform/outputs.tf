output "ec2_instance_id" {
  value = aws_instance.web.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "lambda_function_url" {
  value = aws_lambda_function_url.remediate_url.function_url
}
