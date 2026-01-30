# Platform Engineer Coding Test (PacerPro)

## Overview

This repo implements a monitoring + automation workflow to detect slow responses on `/api/data` and automatically remediate by rebooting an EC2 instance and notifying via SNS.

## Architecture

Sumo Logic (HTTP Source logs)

  -> Sumo Query (filter /api/data > 3s) + Alert (>5 in 10m)

  -> Webhook Connection (call Lambda Function URL)

  -> Lambda (validate token -> reboot EC2 -> publish SNS)

  -> CloudWatch Logs + SNS Notification

## Assumptions / Deviations

- Logs are JSON with fields: `endpoint` and `response_time_ms`.

- “Response time exceeds 3 seconds” is implemented as `response_time_ms > 3000`.  

- Lambda is invoked via Lambda Function URL (webhook) and validates a shared token before rebooting.

- Least privilege is implemented for the Lambda execution role (reboot only the created EC2 instance + publish only to the created SNS topic).  

## Part 3: Terraform (IaC)

Terraform deploys:

- EC2 instance

- SNS topic (+ optional email subscription)

- Lambda function + Function URL

- Least-privilege IAM policy for Lambda role

### Deploy

cd terraform

terraform init

terraform apply
