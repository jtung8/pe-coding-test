# Platform Engineer Coding Test (PacerPro)

## Overview

This repo implements a monitoring + automation workflow to detect slow responses on `/api/data` and automatically remediate by rebooting an EC2 instance and notifying via SNS.

## Architecture

```
Sumo Logic (HTTP Source logs)
  -> Sumo Query (filter /api/data > 3s) + Alert (>5 in 10m)
  -> Webhook Connection (call Lambda Function URL)
  -> Lambda (validate token -> reboot EC2 -> publish SNS)
  -> CloudWatch Logs + SNS Notification
```

## Repository Structure

```
├── terraform/
│   ├── providers.tf    # AWS & archive provider config
│   ├── variables.tf    # Configurable inputs
│   ├── main.tf         # EC2, SNS, Lambda, IAM resources
│   └── outputs.tf      # Resource IDs and URLs
├── lambda_function/
│   └── lambda_function.py  # Remediation handler
├── sumo_logic_query.txt    # Sumo query for slow requests
└── README.md
```

## Assumptions / Deviations

- Logs are JSON with fields: `endpoint` and `response_time_ms`.
- "Response time exceeds 3 seconds" is implemented as `response_time_ms > 3000`.
- Lambda is invoked via Lambda Function URL (webhook) and validates a shared token before rebooting.
- Least privilege is implemented for the Lambda execution role (reboot only the created EC2 instance + publish only to the created SNS topic).

---

## Part 1: Sumo Logic Query and Alert

### Query

```
_sourceCategory="pe-coding-test/http"
| json "endpoint", "response_time_ms" as endpoint, response_time_ms nodrop
| where endpoint = "/api/data"
| where response_time_ms > 3000
| timeslice 10m
| count as slow_requests by _timeslice
```

### Alert Configuration

- **Trigger:** When `slow_requests > 5` within a 10-minute window
- **Action:** Webhook calls Lambda Function URL

### Webhook Payload

```json
{
  "token": "sumo-demo-token-123",
  "endpoint": "/api/data",
  "slow_count": "{{ResultsJSON.slow_requests}}",
  "window": "10m",
  "monitor_name": "{{Name}}",
  "trigger_condition": "{{TriggerCondition}}",
  "trigger_time": "{{TriggerTimeStart}}"
}
```

---

## Part 2: Lambda Function

The Lambda function performs the following:

1. **Validates webhook token** — rejects requests without valid token (401)
2. **Reboots EC2 instance** — calls `reboot_instances` on the target instance
3. **Logs to CloudWatch** — timestamps and context for each action
4. **Publishes to SNS** — notification with remediation details

### Test the Lambda

```bash
# Set the Lambda URL (after terraform apply)
export LAMBDA_URL=$(terraform output -raw lambda_function_url)

# Valid token test (should return 200)
curl -X POST "$LAMBDA_URL" \
  -H "Content-Type: application/json" \
  -d '{"token":"sumo-demo-token-123","endpoint":"/api/data","slow_count":6,"window":"10m"}'

# Invalid token test (should return 401)
curl -X POST "$LAMBDA_URL" \
  -H "Content-Type: application/json" \
  -d '{"token":"wrong-token","endpoint":"/api/data"}'
```

---

## Part 3: Terraform (IaC)

Terraform deploys:

- EC2 instance (Amazon Linux 2023)
- SNS topic (+ optional email subscription)
- Lambda function + Function URL
- **Least-privilege IAM policy** for Lambda role:
  - `ec2:RebootInstances` scoped to the specific instance ARN
  - `sns:Publish` scoped to the specific topic ARN
  - CloudWatch Logs permissions for Lambda logging

### Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Outputs

| Output | Description |
|--------|-------------|
| `ec2_instance_id` | Instance ID to be rebooted |
| `sns_topic_arn` | SNS topic for notifications |
| `lambda_function_url` | Webhook endpoint for Sumo |

### Optional: Email Notifications

To receive SNS email notifications, deploy with:

```bash
terraform apply -var="alert_email=your-email@example.com"
```

Then confirm the subscription in your email.

---

## Verification Checklist

- [x] Terraform creates EC2, Lambda, SNS with least-privilege IAM
- [x] Lambda validates token and rejects invalid requests
- [x] Lambda reboots instance and publishes SNS notification
- [x] Sumo query correctly identifies slow requests (>3s)
- [x] Sumo alert triggers when threshold exceeded (>5 in 10m)
- [x] Webhook successfully invokes Lambda

---

## Screen Recordings

- **Recording:** https://drive.google.com/file/d/1qUjuaAjNTLuFvudoxDfixHzpXFLNJ37Y/view?usp=sharing

---

## Cleanup

To avoid ongoing AWS costs, destroy all resources after evaluation:

```bash
cd terraform
terraform destroy
```
