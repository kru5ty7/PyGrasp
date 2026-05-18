---
title: EC2 Key Pairs and SSH
description: EC2 key pairs are RSA or ED25519 keypairs where AWS holds the public key and you hold the private key — the foundation of SSH access to Linux EC2 instances, with modern alternatives that avoid the risks of lost or shared key files.
tags: [aws, cloud, layer-11, ec2, ssh, key-pairs]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Key Pairs and SSH

> EC2 key pairs give you cryptographic SSH access to Linux instances — but losing the private key is unrecoverable, and SSM Session Manager is the production-grade alternative that requires no open ports or stored key files.

---

## Quick Reference

**Core idea:**
- A key pair is an RSA or ED25519 keypair — AWS stores the public key, you get the private key file (`.pem`) exactly once at creation time
- The private key file must have permission 400 on Unix: `chmod 400 key.pem` — SSH refuses to use a key that is group- or world-readable
- SSH command: `ssh -i key.pem ec2-user@<public-ip>` (Amazon Linux 2023), `ubuntu@<public-ip>` (Ubuntu)
- If you lose the private key, you cannot SSH into instances using that key pair — create a new key pair and launch new instances
- SSM Session Manager provides shell access without a key pair, without port 22 open, and without a public IP — recommended for production

**Tricky points:**
- Each AWS region has its own key pair registry — a key pair created in us-east-1 cannot be used to launch instances in eu-west-1
- The `.pem` file is only available for download immediately after creation — AWS never stores the private key and cannot provide it again
- On Windows, `.pem` file permissions are not enforced the same way — use PuTTY with a `.ppk` conversion, or better, use Windows Terminal with OpenSSH
- The default SSH username depends on the AMI: `ec2-user` (Amazon Linux), `ubuntu` (Ubuntu), `admin` (Debian), `centos` (CentOS), `root` (some older AMIs)
- You can upload your own existing public key to AWS and create a key pair from it — you do not have to use AWS-generated keys

---

## What It Is

A key pair works on the same principle as a padlock and key. The padlock is your public key — you can give it to anyone, and AWS attaches it to every instance you launch with that key pair. When the instance boots, it places the padlock (public key) in the `~/.ssh/authorized_keys` file inside the instance. The private key, which only you hold, is the key that opens the padlock. When you SSH to the instance, your SSH client presents the private key, the instance checks it against the authorised keys file, and if they match, access is granted — without any password.

This asymmetric cryptography means that compromising the public key (which AWS stores) gives an attacker nothing useful. The private key file — the `.pem` file you download — is the sensitive element. AWS does not store it after creation; there is no "download it again" button. Treating the `.pem` file like a password that cannot be reset is the correct mental model. If it is lost, the only recovery path is to create a new key pair and replace the running instances.

The practical limitations of key pairs in large-scale deployments are significant. Managing dozens of `.pem` files across team members, sharing them securely, and revoking access when someone leaves the team are operational burdens. AWS offers two modern alternatives that avoid these problems. EC2 Instance Connect lets you push a temporary public key to an instance for 60 seconds via the AWS API — you SSH in with that temporary key, and the authorised keys entry disappears automatically. SSM Session Manager provides an interactive shell over the AWS API itself — no key pair, no port 22 open, no public IP required — access is controlled entirely by IAM.

---

## How It Actually Works

When you launch an instance with a key pair specified, the EC2 service injects the associated public key into the instance's initial disk image. On Amazon Linux 2023 and Ubuntu, this injection is performed by `cloud-init`, which runs during the first boot and writes the public key to `/home/ec2-user/.ssh/authorized_keys` (Amazon Linux) or `/home/ubuntu/.ssh/authorized_keys` (Ubuntu). The SSH daemon (`sshd`) reads this file for every incoming connection attempt.

For SSM Session Manager to work, the instance must have the SSM Agent installed (pre-installed on Amazon Linux 2023 and Ubuntu 22.04+) and an IAM instance profile with the `AmazonSSMManagedInstanceCore` managed policy. No security group rules for SSH are needed — SSM communicates outbound over HTTPS (port 443) from the instance to the SSM endpoint, and your browser or CLI connects to that endpoint, not to the instance directly.

```bash
# Create a new key pair and save the private key
aws ec2 create-key-pair \
    --key-name my-project-key \
    --key-type ed25519 \
    --key-format pem \
    --query KeyMaterial \
    --output text > my-project-key.pem

# Set correct permissions (required by SSH client)
chmod 400 my-project-key.pem

# SSH into an Amazon Linux instance
ssh -i my-project-key.pem ec2-user@54.123.45.67

# SSH into an Ubuntu instance
ssh -i my-project-key.pem ubuntu@54.123.45.67

# Import an existing public key (use your own keypair)
aws ec2 import-key-pair \
    --key-name my-existing-key \
    --public-key-material fileb://~/.ssh/id_ed25519.pub

# SSM Session Manager — no key pair needed, no port 22 required
aws ssm start-session --target i-0123456789abcdef0

# EC2 Instance Connect — temporary SSH key valid for 60 seconds
aws ec2-instance-connect ssh --instance-id i-0123456789abcdef0
```

```python
import boto3
import os

ec2 = boto3.client("ec2")

# Create a key pair and save the private key to a file
response = ec2.create_key_pair(
    KeyName="my-project-key",
    KeyType="ed25519",
    KeyFormat="pem",
    TagSpecifications=[{
        "ResourceType": "key-pair",
        "Tags": [{"Key": "Project", "Value": "my-app"}],
    }],
)
private_key_material = response["KeyMaterial"]
key_path = os.path.expanduser("~/.ssh/my-project-key.pem")
with open(key_path, "w") as f:
    f.write(private_key_material)
os.chmod(key_path, 0o400)  # equivalent to chmod 400
print(f"Key pair created. Private key saved to: {key_path}")

# Import an existing public key
with open(os.path.expanduser("~/.ssh/id_ed25519.pub"), "rb") as f:
    public_key = f.read()
ec2.import_key_pair(
    KeyName="my-imported-key",
    PublicKeyMaterial=public_key,
)

# List all key pairs
response = ec2.describe_key_pairs()
for kp in response["KeyPairs"]:
    print(kp["KeyName"], kp["KeyType"], kp.get("KeyFingerprint", ""))

# Delete a key pair (does not affect running instances — they still work with the injected key)
ec2.delete_key_pair(KeyName="old-key-pair")

# Send a temporary public key via Instance Connect (for temporary SSH access)
ic = boto3.client("ec2-instance-connect")
with open(os.path.expanduser("~/.ssh/id_ed25519.pub")) as f:
    public_key_body = f.read()
ic.send_ssh_public_key(
    InstanceId="i-0123456789abcdef0",
    InstanceOSUser="ec2-user",
    SSHPublicKey=public_key_body,
    AvailabilityZone="eu-west-1a",
)
# Now SSH immediately — the key is valid for 60 seconds
# ssh -i ~/.ssh/id_ed25519 ec2-user@<public-ip>
```

---

## How It Connects

SSM Session Manager is the preferred modern alternative to SSH key pairs for production access. It requires an IAM instance profile with the SSM managed policy, which means understanding IAM instance profiles is a prerequisite for using it correctly.

[[iam-instance-profile|IAM Instance Profile]] — the instance profile must include `AmazonSSMManagedInstanceCore` for SSM Session Manager to work; without this policy, the SSM agent cannot establish the connection.

Key pairs are specified at instance launch time. The `KeyName` parameter in `run_instances` is optional — if omitted, no key pair is injected and SSH key-based access is not configured (though you can add keys manually or use SSM).

[[ec2-launch|Launching EC2 Instances]] — the `KeyName` parameter in `run_instances` connects a key pair to an instance at creation time; understanding launch parameters as a whole ensures key pair handling is part of a consistent configuration.

---

## Common Misconceptions

Misconception 1: Deleting a key pair from AWS removes SSH access to all instances launched with it.
Reality: Deleting the key pair from AWS removes the name from the AWS key pair registry, but the public key that was injected into running instances at launch time remains in those instances' `authorized_keys` files. SSH access using the original private key file continues to work. Deleting the key pair from AWS only prevents it from being used for new instance launches — it has no effect on existing instances.

Misconception 2: If I lose the `.pem` file, I can recover it from AWS.
Reality: AWS stores only the public key. The private key is generated once, returned in the API response, and never stored by AWS. If the `.pem` file is lost, there is no way to recover it from AWS. The only remediation for existing instances is to mount the root EBS volume on another instance, add a new public key to the `authorized_keys` file manually, remount, and restart — a complex and error-prone process. The practical recommendation is to use SSM Session Manager for production access and keep key pairs only as an emergency last resort.

---

## Why It Matters in Practice

Key pair management is a real operational burden that scales poorly. A team of 10 developers each needing SSH access to 5 environments means 10 private keys in rotation, each needing to be securely distributed and revoked when a developer leaves. SSM Session Manager solves this entirely — access is controlled by IAM, so onboarding and offboarding SSH access is the same as managing IAM permissions. Access is logged to CloudTrail, session output can be streamed to CloudWatch, and no private key files are distributed at all.

The file permission requirement (`chmod 400`) catches many developers on Windows or when deploying from CI/CD pipelines. An SSH client that encounters a key file with loose permissions will refuse to use it with a "Permissions too open" error message that looks mysterious to developers unfamiliar with Unix file permissions.

---

## What Breaks in Production

**SSH connection refused because port 22 is not open in the security group.** The error message "Connection refused" or a timeout with no response both indicate a network-level block, not an authentication failure.

```bash
# Verify security group allows SSH
aws ec2 describe-security-groups \
    --group-ids sg-0123456789abcdef0 \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\`]"

# Add SSH access from your IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 22 --cidr "${MY_IP}/32"
```

**Permission denied (publickey) because the wrong username is used.** Amazon Linux uses `ec2-user`, not `root` or `ubuntu`. Ubuntu uses `ubuntu`. Using the wrong username causes the server to look for the public key in the wrong user's `authorized_keys` file.

```bash
# Amazon Linux 2023
ssh -i key.pem ec2-user@<ip>

# Ubuntu
ssh -i key.pem ubuntu@<ip>

# Check which user the AMI expects — look at cloud-init config
# or check the AMI description in the console
```

---

## Interview Angle

Common question forms:
- "What happens if you lose your EC2 private key file?"
- "What is the difference between EC2 Instance Connect and SSM Session Manager?"
- "How would you set up SSH access to EC2 for a team of 10 developers?"

Answer frame:
For lost key: AWS cannot recover it; for existing instances, mount the EBS volume elsewhere and manually add a new authorized key. For Instance Connect vs SSM: Instance Connect temporarily injects a key for 60 seconds; SSM provides a shell over HTTPS via the SSM agent, no port 22, no key required. For team access: use SSM Session Manager controlled by IAM permissions — no key distribution, access logging, and easy revocation.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-security-groups|EC2 Security Groups]]
- [[iam-instance-profile|IAM Instance Profile]]
