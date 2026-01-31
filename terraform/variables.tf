variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "alert_email" {
  type        = string
  description = "Optional: email to subscribe to SNS topic"
  default     = ""
}

variable "webhook_token" {
  type        = string
  description = "Shared token that Sumo webhook sends; Lambda validates before rebooting"
  default     = "sumo-demo-token-123"
}
