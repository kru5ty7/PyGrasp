---
title: 26 - EC2 Security Groups
description: A security group is a stateful virtual firewall attached to an EC2 instance that controls which inbound and outbound traffic is allowed — misconfigured security groups are the most common cause of EC2 connectivity failures.
tags: [aws, cloud, layer-11, ec2, security-groups, networking]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Security Groups

> Security groups are the network boundary around your EC2 instances — understanding their stateful nature, their allow-only model, and how to reference other security groups instead of IP ranges is essential for building secure, maintainable AWS network configurations.

---

## Quick Reference

**Core idea:**
- A security group is attached to an EC2 instance (or other AWS resources) and defines allowed inbound and outbound traffic
- Rules specify: protocol (TCP/UDP/ICMP/all), port range, and source/destination (CIDR block or security group ID)
- Stateful: inbound rules automatically permit the corresponding outbound response — you do not need a separate outbound rule for responses
- Default behaviour: deny all inbound, allow all outbound — you only need to add inbound rules for traffic you want to permit
- Security groups are permissive-only — you can only add Allow rules, never Deny rules

**Tricky points:**
- Security groups can reference other security groups as the source (for inbound rules) or destination (for outbound rules) — this is more maintainable than CIDR ranges for inter-service communication
- A security group belongs to a VPC and can only be applied to resources in that VPC
- You can attach up to 5 security groups to a single instance (and up to 50 inbound rules per security group)
- NACL (Network ACL) is a separate, stateless subnet-level firewall — security groups and NACLs are evaluated independently; both must permit the traffic
- Removing the 0.0.0.0/0 outbound rule prevents all outbound traffic — this breaks software updates, DNS lookups, and HTTPS calls to AWS APIs

---

## What It Is

Think of a security group as a strict doorman working the entrance to your instance's building. The doorman has a whitelist. Any visitor whose credentials match an entry on the whitelist gets in; everyone else is turned away without explanation. Critically, the doorman only has a whitelist — there is no blacklist. You cannot instruct the doorman to reject a specific IP while allowing all others; you can only specify who is allowed in. The default list is empty for inbound visitors, so without any rules, nobody gets in.

The stateful nature of security groups is one of their most important characteristics. When your EC2 instance initiates a connection outbound — for example, making an HTTPS request to download a package — the response traffic is automatically allowed back in, even if there is no inbound rule for port 443 from that server's IP. The security group tracks the connection state and recognises the incoming packets as part of an established outbound session. This is the difference between stateful firewalls (like security groups) and stateless packet filters (like NACLs) — stateful firewalls track sessions, stateless packet filters evaluate each packet independently.

The most powerful feature of security groups in practice is the ability to reference other security groups as the traffic source, rather than CIDR blocks. Instead of writing "allow port 5432 from 10.0.1.5/32" (which breaks when the IP changes), you write "allow port 5432 from the security group attached to my application servers." AWS evaluates this rule dynamically — any instance with that security group attached is allowed to connect, regardless of IP address. This makes security group rules durable and self-maintaining as instances are replaced in Auto Scaling Groups.

---

## How It Actually Works

Security groups are evaluated at the virtual network interface level — before traffic reaches the instance's OS. This means there is no way to bypass a security group using OS-level firewall rules on the instance. Conversely, security groups do not replace OS-level firewall configuration — for defence in depth, both should be configured appropriately.

Each security group rule consists of a protocol (TCP, UDP, ICMP, or All), a port range (a single port or a range), and a source for inbound rules (or destination for outbound rules). The source/destination can be a CIDR block (e.g., `10.0.0.0/8`, `0.0.0.0/0`), a prefix list ID, or another security group ID. When a security group is used as the source, traffic is allowed from any resource that has that security group attached — within the same VPC (or across VPCs with peering, using the full account and SG ID).

```bash
# Create a security group
aws ec2 create-security-group \
    --group-name my-web-server-sg \
    --description "Web server security group" \
    --vpc-id vpc-0123456789abcdef0

# Allow HTTP and HTTPS from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 443 --cidr 0.0.0.0/0

# Allow SSH only from a specific IP (replace with your actual IP)
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 22 --cidr 203.0.113.42/32

# Allow PostgreSQL connections from the application security group
aws ec2 authorize-security-group-ingress \
    --group-id sg-db-0abcdef1234567890 \
    --protocol tcp --port 5432 \
    --source-group sg-0123456789abcdef0

# Describe current security group rules
aws ec2 describe-security-group-rules \
    --filters Name=group-id,Values=sg-0123456789abcdef0
```

```python
import boto3

ec2 = boto3.client("ec2")

# Create a security group for a web application
web_sg = ec2.create_security_group(
    GroupName="web-server-sg",
    Description="Security group for web application servers",
    VpcId="vpc-0123456789abcdef0",
    TagSpecifications=[{
        "ResourceType": "security-group",
        "Tags": [{"Key": "Name", "Value": "web-server-sg"}],
    }],
)
web_sg_id = web_sg["GroupId"]

# Allow HTTP and HTTPS from the internet
ec2.authorize_security_group_ingress(
    GroupId=web_sg_id,
    IpPermissions=[
        {
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "HTTP from internet"}],
            "Ipv6Ranges": [{"CidrIpv6": "::/0", "Description": "HTTP from internet IPv6"}],
        },
        {
            "IpProtocol": "tcp",
            "FromPort": 443,
            "ToPort": 443,
            "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
            "Ipv6Ranges": [{"CidrIpv6": "::/0"}],
        },
    ],
)

# Create a database security group that only accepts connections from web servers
db_sg = ec2.create_security_group(
    GroupName="database-sg",
    Description="Security group for RDS PostgreSQL",
    VpcId="vpc-0123456789abcdef0",
)
db_sg_id = db_sg["GroupId"]

# Allow PostgreSQL only from the web server security group
ec2.authorize_security_group_ingress(
    GroupId=db_sg_id,
    IpPermissions=[
        {
            "IpProtocol": "tcp",
            "FromPort": 5432,
            "ToPort": 5432,
            "UserIdGroupPairs": [
                {
                    "GroupId": web_sg_id,
                    "Description": "PostgreSQL from web servers",
                }
            ],
        }
    ],
)

# Describe rules for a security group
rules = ec2.describe_security_group_rules(
    Filters=[{"Name": "group-id", "Values": [web_sg_id]}]
)
for rule in rules["SecurityGroupRules"]:
    direction = "Outbound" if rule["IsEgress"] else "Inbound"
    print(f"{direction}: {rule['IpProtocol']} {rule.get('FromPort', '*')}-"
          f"{rule.get('ToPort', '*')} {rule.get('CidrIpv4', rule.get('CidrIpv6', 'SG'))}")
```

---

## How It Connects

Security groups are the network boundary that protects EC2 instances. They work in conjunction with IAM — IAM controls what the instance can do (API permissions), security groups control what can reach the instance (network access). Both must be configured correctly for a production deployment.

[[ec2-launch|Launching EC2 Instances]] — security group IDs are a required parameter in `run_instances`; the security group must exist before launch and determines connectivity from the first moment the instance is running.

The Application Load Balancer has its own security group. The pattern for HTTPS web applications is: ALB security group allows 443 from 0.0.0.0/0; EC2 security group allows the application port (e.g. 8000) from the ALB security group only — the EC2 instances are never directly exposed to the internet.

[[ec2-elb|Elastic Load Balancer]] — the ALB and EC2 instances each have their own security groups; the EC2 security group should only allow traffic from the ALB's security group, not from the internet directly.

---

## Common Misconceptions

Misconception 1: Security groups are like traditional firewalls — I can add Deny rules to block specific IPs.
Reality: Security groups are allow-only. You cannot add a rule that denies traffic from a specific IP while allowing everything else. If you need to block specific IPs, you must use a NACL (Network ACL), which supports both allow and deny rules and is applied at the subnet level. Alternatively, WAF (Web Application Firewall) can block specific IPs at the HTTP layer.

Misconception 2: Adding an inbound rule for port 443 also requires an outbound rule for port 443 responses.
Reality: Security groups are stateful. Inbound rules automatically permit the corresponding response traffic outbound. The default allow-all outbound rule does not need to explicitly cover port 443 responses — even if you restrict outbound rules, response traffic for established inbound connections is still permitted. The stateful tracking happens at the network interface level, below the rule evaluation logic.

---

## Why It Matters in Practice

Security groups are the most frequently misconfigured security control in AWS environments. The most common mistake is opening SSH (port 22) to 0.0.0.0/0 (the entire internet) rather than restricting it to a specific IP or CIDR. This exposes the instance to brute-force attacks and vulnerability scanners. The correct production approach is either to allow SSH only from a bastion host security group, use EC2 Instance Connect (which temporarily adds your public key without a persistent open port), or use SSM Session Manager (which requires no open port 22 at all).

The security group referencing pattern — using a security group ID as the source rather than a CIDR — is the key to maintainable multi-tier network security. Database security groups that only allow traffic from application security groups mean new application instances automatically get database access without any manual security group rule changes.

---

## What Breaks in Production

**Removing the default all-outbound rule without adding replacement outbound rules.** This silently breaks DNS resolution, HTTPS calls to AWS APIs, and package manager updates.

```bash
# If you restrict outbound rules, ensure these are still allowed
# DNS — UDP/TCP port 53 to VPC DNS resolver (169.254.169.253 or VPC base+2)
# HTTPS — TCP port 443 to 0.0.0.0/0 for AWS API calls
# NTP — UDP port 123 to 0.0.0.0/0 for time synchronisation
aws ec2 authorize-security-group-egress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 443 --cidr 0.0.0.0/0
```

**Not restricting SSH access to a known IP range.** Port 22 open to the internet attracts brute-force login attempts within minutes of instance launch.

```bash
# Bad — open SSH to the world
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 22 --cidr 0.0.0.0/0

# Better — restrict to your IP, or remove SSH entirely and use SSM Session Manager
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
    --group-id sg-0123456789abcdef0 \
    --protocol tcp --port 22 --cidr "${MY_IP}/32"
```

---

## Interview Angle

Common question forms:
- "What is a security group and how does it differ from a NACL?"
- "How would you configure security groups for a three-tier web application?"
- "Why is it better to reference a security group as a source rather than an IP CIDR?"

Answer frame:
For SG vs NACL: SGs are stateful, instance-level, allow-only; NACLs are stateless, subnet-level, allow and deny. For three-tier: ALB SG allows 80/443 from internet; App SG allows app port from ALB SG only; DB SG allows 5432 from App SG only. For SG referencing: dynamic — automatically covers new instances added to the referenced SG without rule changes; CIDR breaks when IPs change.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-elb|Elastic Load Balancer]]
- [[ec2-python|Managing EC2 with Python (boto3)]]
- [[iam-overview|IAM Overview]]
