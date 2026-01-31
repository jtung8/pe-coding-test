import os
import json
import boto3
from datetime import datetime, timezone

ec2 = boto3.client("ec2")
sns = boto3.client("sns")


def _utc_now():
    """Return current UTC timestamp in ISO format."""
    return datetime.now(timezone.utc).isoformat()

def _parse_payload(event):
    """
    Function URL invokes Lambda with event["body"] as a string.
    Console tests might send a dict directly.
    Return a dict either way.
    """
    if isinstance(event, dict) and "body" in event and event["body"] is not None:
        body = event["body"]
        if isinstance(body, str):
            try:
                return json.loads(body)
            except json.JSONDecodeError:
                return {"raw_body": body}
        if isinstance(body, dict):
            return body
    return event if isinstance(event, dict) else {"raw_event": str(event)}

def _unauthorized(msg):
    """Return 401 response and log the reason."""
    print(f"[{_utc_now()}] UNAUTHORIZED: {msg}")
    return {"statusCode": 401, "body": json.dumps({"error": msg})}

def lambda_handler(event, context):
    # Get configuration from environment
    instance_id = os.environ.get("INSTANCE_ID")
    topic_arn = os.environ.get("SNS_TOPIC_ARN")
    expected_token = os.environ.get("WEBHOOK_TOKEN")

    # Validate environment
    if not instance_id or not topic_arn:
        msg = "Missing env vars INSTANCE_ID or SNS_TOPIC_ARN"
        print(f"[{_utc_now()}] ERROR: {msg}")
        return {"statusCode": 500, "body": msg}

    # Parse incoming payload
    payload = _parse_payload(event)

    # Validate webhook token
    provided_token = payload.get("token")
    if expected_token and provided_token != expected_token:
        return _unauthorized("Invalid webhook token")

    # Extract alert context for logging
    endpoint = payload.get("endpoint", "/api/data")
    slow_count = payload.get("slow_count", payload.get("count", "unknown"))
    window = payload.get("window", "10m")

    now = _utc_now()
    print(f"[{now}] Trigger received. endpoint={endpoint}, slow_count={slow_count}, window={window}")

    # 1) Reboot EC2 instance
    print(f"[{now}] Rebooting EC2 instance: {instance_id}")
    ec2.reboot_instances(InstanceIds=[instance_id])

    # 2) Publish SNS notification
    message = (
        f"Remediation executed.\n"
        f"Time (UTC): {now}\n"
        f"Endpoint: {endpoint}\n"
        f"Slow requests (>3s): {slow_count}\n"
        f"Window: {window}\n"
        f"Action: reboot_instances({instance_id})\n"
    )
    sns.publish(
        TopicArn=topic_arn,
        Subject="Sumo Alert: EC2 Reboot Triggered",
        Message=message
    )

    print(f"[{now}] SNS notification published to: {topic_arn}")

    return {
        "statusCode": 200,
        "body": json.dumps({"status": "ok", "instance_id": instance_id})
    }
