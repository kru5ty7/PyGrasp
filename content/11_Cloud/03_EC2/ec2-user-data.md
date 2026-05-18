---
title: EC2 User Data Scripts
description: User data is a script that runs once when an EC2 instance first launches — the standard mechanism for bootstrapping software installation, service configuration, and code deployment without manual SSH intervention.
tags: [aws, cloud, layer-11, ec2, user-data, bootstrap]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 User Data Scripts

> User data is the bootstrap mechanism for EC2 — it lets you convert a blank OS into a configured, running application automatically on first launch, which is the prerequisite for scalable and reproducible deployments.

---

## Quick Reference

**Core idea:**
- User data is a shell script (or cloud-init config) provided at launch time and run once by cloud-init as root on first boot
- Must start with `#!/bin/bash` on Amazon Linux and Ubuntu
- Execution log is written to `/var/log/cloud-init-output.log` on the instance
- Maximum size: 16KB — larger bootstrap scripts should be stored in S3 and downloaded by a small user data stub
- Does not re-run on stop/start — only on the very first boot of a new instance (unless cloud-init is explicitly configured otherwise)

**Tricky points:**
- User data runs as root — no need for `sudo` inside the script
- Errors in the user data script do not prevent the instance from starting — the instance reaches `running` state regardless of whether the script succeeded
- The `instance_status_ok` waiter confirms the OS is healthy but does not confirm user data completed successfully
- Environment variables set in user data are not available to interactive SSH sessions — they are set only in the context of the cloud-init run
- User data can be updated on a stopped instance, but the update only takes effect if cloud-init is configured to re-run or if you launch a new instance

---

## What It Is

Imagine buying a new laptop and, before you turn it on, leaving a sealed envelope inside the box with installation instructions. The moment the laptop boots for the first time, a helper program opens the envelope and runs every instruction in sequence: installs your applications, configures your settings, copies your files, and starts your services. By the time you sit down to use the laptop, it is fully configured. User data is that sealed envelope for EC2 instances.

Without user data, every new EC2 instance starts as a blank operating system. You would need to SSH in, run installation commands manually, configure services by hand, and only then would the instance be useful. This manual process does not scale — it is unrepeatable, error-prone, and incompatible with Auto Scaling Groups, where instances launch automatically without human intervention. User data replaces the manual process with a reproducible script.

The execution context of user data is important to understand. The script runs as the root user, before any application process is started, and without an interactive terminal. It runs once — the first time the instance boots after being launched from an AMI. If you stop the instance and start it again, the user data script does not run again. If you need configuration that runs on every boot, you must use systemd units, cron jobs configured within the user data, or a configuration management tool like AWS Systems Manager Run Command.

---

## How It Actually Works

When EC2 launches an instance with user data specified, the user data string (which must be base64-encoded — boto3 handles this automatically) is stored in the instance metadata service at `http://169.254.169.254/latest/user-data`. On first boot, the cloud-init service retrieves the user data, detects that it is a shell script (by checking the shebang line), and executes it as a subprocess under root. All output from the script (stdout and stderr) is captured to `/var/log/cloud-init-output.log`.

The script runs during the instance's boot sequence, which means it can take several minutes for a complex bootstrap. The instance enters the `running` state before the user data script completes. Applications that depend on user data finishing (like a load balancer health check) must handle the startup period gracefully — either via health check grace periods in Auto Scaling Groups or by using `cloud-init` status checks in a post-launch verification step.

For large bootstrap operations (installing many packages, downloading large files from S3), the 16KB size limit of user data is quickly reached. The standard pattern is a small user data script that downloads and executes a larger bootstrap script from S3, keeping the user data payload minimal.

```bash
# View user data on a running instance (from outside the instance)
aws ec2 describe-instance-attribute \
    --instance-id i-0123456789abcdef0 \
    --attribute userData \
    --query UserData.Value \
    --output text | base64 --decode

# From inside the instance — retrieve user data via metadata service (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/user-data

# Check cloud-init execution status from inside the instance
cloud-init status --wait   # waits for cloud-init to finish
cloud-init status          # reports: running / done / error

# View the user data execution log
tail -100 /var/log/cloud-init-output.log
```

```python
import boto3
import base64

ec2 = boto3.client("ec2")

# User data script — runs as root on first boot
user_data = """#!/bin/bash
set -euo pipefail   # exit on error, undefined variable, or pipe failure
exec > /var/log/bootstrap.log 2>&1   # redirect all output to a log file

echo "=== Bootstrap started at $(date) ==="

# Update system packages
dnf update -y

# Install Python 3.11 and nginx
dnf install -y python3.11 python3.11-pip nginx git

# Create app user (do not run the app as root)
useradd -m -s /bin/bash appuser

# Download application code from S3
aws s3 cp s3://my-deployment-bucket/app/latest/app.tar.gz /home/appuser/
tar xzf /home/appuser/app.tar.gz -C /home/appuser/
chown -R appuser:appuser /home/appuser/app/

# Create virtualenv and install dependencies
sudo -u appuser python3.11 -m venv /home/appuser/venv
sudo -u appuser /home/appuser/venv/bin/pip install -r /home/appuser/app/requirements.txt

# Configure gunicorn as a systemd service
cat > /etc/systemd/system/gunicorn.service << 'EOF'
[Unit]
Description=Gunicorn instance to serve my app
After=network.target

[Service]
User=appuser
Group=appuser
WorkingDirectory=/home/appuser/app
EnvironmentFile=/home/appuser/app/.env
ExecStart=/home/appuser/venv/bin/gunicorn \
    --workers 4 \
    --bind unix:/run/gunicorn/gunicorn.sock \
    wsgi:app

RuntimeDirectory=gunicorn
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gunicorn
systemctl start gunicorn

# Configure nginx
cat > /etc/nginx/conf.d/myapp.conf << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://unix:/run/gunicorn/gunicorn.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

nginx -t && systemctl enable nginx && systemctl start nginx

echo "=== Bootstrap complete at $(date) ==="
"""

# Launch instance with user data
# boto3 accepts the script as a plain string — it handles base64 encoding internally
response = ec2.run_instances(
    ImageId="ami-0abcdef1234567890",
    InstanceType="t3.micro",
    KeyName="my-key",
    SecurityGroupIds=["sg-0123456789abcdef0"],
    SubnetId="subnet-0123456789abcdef0",
    MinCount=1,
    MaxCount=1,
    UserData=user_data,
    IamInstanceProfile={"Name": "AppInstanceProfile"},
)

instance_id = response["Instances"][0]["InstanceId"]

# Pattern: S3-based bootstrap (for scripts larger than 16KB)
small_user_data = """#!/bin/bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/region)
aws s3 cp s3://my-deployment-bucket/bootstrap/install.sh /tmp/install.sh --region $REGION
chmod +x /tmp/install.sh
/tmp/install.sh
"""
```

---

## How It Connects

User data scripts typically download application code or configuration from S3. The EC2 instance must have an IAM instance profile with S3 read access for these downloads to succeed — making IAM instance profiles a prerequisite for any non-trivial user data script.

[[iam-instance-profile|IAM Instance Profile]] — without an instance profile granting `s3:GetObject` on the deployment bucket, the `aws s3 cp` commands in the user data script will fail with access denied.

User data is the starting point for deploying Python applications on EC2. The complete deployment pattern — gunicorn, nginx, systemd — that user data sets up is described in detail in the Python deployment note.

[[ec2-python-deployment|Deploying Python Apps on EC2]] — the full gunicorn + nginx + systemd pattern that user data automates, including how to structure the service file and handle environment variables securely.

---

## Common Misconceptions

Misconception 1: If the user data script fails, the instance fails to launch.
Reality: User data script failures do not prevent the instance from reaching the `running` state. The instance starts normally; the cloud-init process runs the script in the background. If the script exits with a non-zero status, cloud-init records the failure in `/var/log/cloud-init-output.log`, but the instance continues running with whatever configuration was applied before the failure. Silent partial bootstrap is a real production risk — always use `set -euo pipefail` and verify bootstrap completion independently.

Misconception 2: User data runs every time the instance starts.
Reality: By default, cloud-init runs user data scripts only once — during the first boot of a new instance. Stopping and starting the instance does not re-run the user data. If you update the user data of a stopped instance (via `aws ec2 modify-instance-attribute`), the updated script will not run unless you also reconfigure cloud-init to allow re-execution, or launch a new instance from the updated launch template.

---

## Why It Matters in Practice

User data is the mechanism that makes Auto Scaling Groups possible. When an ASG launches a new instance in response to increased traffic, there is no operator available to SSH in and configure it. The instance must bootstrap itself from zero to serving requests entirely automatically. Without reliable user data scripts, Auto Scaling cannot be trusted — new instances might launch but not serve traffic, creating outages during scale-out events.

The `set -euo pipefail` idiom at the top of user data scripts is not optional for production. Without it, a failed package installation or a missing file will be silently ignored and the script will continue, potentially leaving the instance in a partially configured state that passes health checks but exhibits subtle bugs.

---

## What Breaks in Production

**Not logging user data output to a file, making bootstrap failures invisible.** The default cloud-init log is verbose and mixed with other cloud-init messages — redirecting to a dedicated log file makes debugging much faster.

```bash
#!/bin/bash
exec > /var/log/bootstrap.log 2>&1  # all output goes here
set -euo pipefail
echo "Bootstrap start: $(date)"
# ... rest of script ...
# On failure: ssh in and check /var/log/bootstrap.log
```

**User data downloading from S3 but the IAM instance profile not having S3 permissions.** The `aws s3 cp` command fails with "Access Denied" but the instance reaches `running` state, so automated monitoring does not detect the failure.

```bash
# Verify the instance profile has s3:GetObject before launch
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::123456789012:role/AppInstanceRole \
    --action-names s3:GetObject \
    --resource-arns arn:aws:s3:::my-deployment-bucket/bootstrap/install.sh \
    --query "EvaluationResults[0].EvalDecision"
# Expected output: "allowed"
```

---

## Interview Angle

Common question forms:
- "How do you automatically configure an EC2 instance when it launches?"
- "What happens if the user data script fails?"
- "How do you handle a user data script that exceeds 16KB?"

Answer frame:
For auto-configuration: user data script runs once via cloud-init on first boot as root; installs packages, starts services. For failures: instance still reaches `running` state; failure is logged to `/var/log/cloud-init-output.log`; application health checks are the right detection mechanism. For 16KB limit: store the full script in S3, use a minimal user data stub that downloads and executes it.

---

## Related Notes

- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-overview|EC2 Overview]]
- [[iam-instance-profile|IAM Instance Profile]]
- [[ec2-python-deployment|Deploying Python Apps on EC2]]
- [[s3-python|S3 with Python (boto3)]]
