---
title: 31 - Elastic Load Balancer
description: AWS Elastic Load Balancers distribute incoming traffic across multiple EC2 instances, perform health checks, terminate SSL, and enable zero-downtime deployments - the Application Load Balancer is the standard choice for Python web applications.
tags: [aws, cloud, layer-11, ec2, elb, load-balancing]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Elastic Load Balancer

> An Application Load Balancer sits in front of your EC2 instances, routes HTTP/HTTPS traffic by path and host, terminates SSL, and continuously health-checks your application - making it the standard entry point for any production Python web service.

---

## Quick Reference

**Core idea:**
- ALB (Application Load Balancer): HTTP/HTTPS, Layer 7, path and host routing, WebSocket, Lambda targets - use for web applications
- NLB (Network Load Balancer): TCP/UDP, Layer 4, extreme throughput, static IP, preserves client IP - use for non-HTTP or ultra-low latency
- CLB (Classic Load Balancer): legacy, pre-dates VPC-native design - avoid in new deployments
- ALB components: Listener (port 80/443) → Rules (routing conditions) → Target Groups (instances, IPs, or Lambda)
- SSL termination at the ALB: the ALB handles HTTPS; EC2 instances receive plain HTTP on a private port

**Tricky points:**
- Target group health checks must match what your application actually serves - a health check on `/` returning 200 is the minimum requirement
- Stickiness (session affinity) routes requests from the same client to the same instance - useful for stateful applications, but conflicts with horizontal scaling
- The ALB introduces a small latency (typically 1-5ms) - not usually significant, but relevant for sub-10ms SLA requirements (use NLB instead)
- ALB access logs are stored in S3 and are not enabled by default - enable them for production
- ALB has an idle timeout (default 60 seconds) - long-running HTTP connections (server-sent events, streaming responses) must account for this

---

## What It Is

Think of a load balancer as a traffic controller at a busy intersection. Cars arriving from the highway (internet traffic) must be distributed across several parallel lanes (EC2 instances) to prevent any single lane from becoming blocked. The traffic controller knows which lanes are open (healthy instances pass health checks) and which are closed (failed instances are marked unhealthy). It continuously monitors the lanes and stops sending traffic to any lane where cars are piling up or the road is blocked. It also handles the toll booth (SSL termination) at the entrance, so the cars on the individual lanes do not need to worry about it.

The Application Load Balancer operates at Layer 7 of the network stack - it understands HTTP. This means it can make routing decisions based on the request content: URL path, Host header, HTTP method, query string parameters, or custom headers. A request to `/api/v2/users` can be routed to the API service target group, while a request to `/static/logo.png` is routed to a CDN or a static asset server target group. Multiple microservices can sit behind a single ALB, differentiated by path prefix or hostname.

An ALB is built from three connected concepts. Listeners are the ports the ALB watches for incoming connections - typically port 80 for HTTP and port 443 for HTTPS. Rules are evaluated on each request to determine which target group should receive it - rules have conditions (path pattern, host header, etc.) and actions (forward, redirect, or return a fixed response). Target groups are collections of backend resources (EC2 instances, IP addresses, Lambda functions) that the ALB forwards traffic to. The ALB performs health checks on each target in the target group and only sends traffic to healthy targets.

---

## How It Actually Works

SSL termination at the ALB is the standard pattern for HTTPS. You attach an SSL certificate (from AWS Certificate Manager, which provides free certificates) to the HTTPS listener. The ALB handles the TLS handshake with the client - the client sees HTTPS. The connection between the ALB and the EC2 instances uses plain HTTP on a private port (typically 8000 or 8080 or whatever your application listens on). This is secure because the ALB-to-instance communication travels on AWS's internal network, not the public internet. The instance never sees TLS traffic, and you do not need to manage SSL certificates on your EC2 instances.

Health checks are configured per target group. You specify the protocol (HTTP), the path (e.g., `/health`), the port, and the threshold for healthy/unhealthy. The ALB sends an HTTP GET to each registered target every `HealthCheckIntervalSeconds` (default 30 seconds). A target is considered healthy if it returns an HTTP status code in the `HealthyThresholdCount` consecutive checks (default 5 checks = 2.5 minutes to be marked healthy). A target is marked unhealthy after `UnhealthyThresholdCount` consecutive failures (default 2 checks = 1 minute to be marked unhealthy and removed from rotation).

```bash
# Create a target group
aws elbv2 create-target-group \
    --name my-app-targets \
    --protocol HTTP \
    --port 8000 \
    --vpc-id vpc-0123456789abcdef0 \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --target-type instance

# Create the ALB
aws elbv2 create-load-balancer \
    --name my-app-alb \
    --subnets subnet-abc123 subnet-def456 subnet-ghi789 \
    --security-groups sg-0123456789abcdef0 \
    --type application

# Create HTTP listener that redirects to HTTPS
aws elbv2 create-listener \
    --load-balancer-arn arn:aws:elasticloadbalancing:... \
    --protocol HTTP --port 80 \
    --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'

# Create HTTPS listener with SSL certificate
aws elbv2 create-listener \
    --load-balancer-arn arn:aws:elasticloadbalancing:... \
    --protocol HTTPS --port 443 \
    --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
    --certificates CertificateArn=arn:aws:acm:eu-west-1:123456789012:certificate/abc123 \
    --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...

# Register an instance with a target group
aws elbv2 register-targets \
    --target-group-arn arn:aws:elasticloadbalancing:... \
    --targets Id=i-0123456789abcdef0,Port=8000

# Check target health
aws elbv2 describe-target-health \
    --target-group-arn arn:aws:elasticloadbalancing:...
```

```python
import boto3

elbv2 = boto3.client("elbv2")

# Create a target group for a Python web application
tg_response = elbv2.create_target_group(
    Name="my-app-targets",
    Protocol="HTTP",
    Port=8000,
    VpcId="vpc-0123456789abcdef0",
    HealthCheckProtocol="HTTP",
    HealthCheckPath="/health",
    HealthCheckIntervalSeconds=30,
    HealthyThresholdCount=2,
    UnhealthyThresholdCount=2,
    Matcher={"HttpCode": "200"},
    TargetType="instance",
)
target_group_arn = tg_response["TargetGroups"][0]["TargetGroupArn"]

# Create the Application Load Balancer
alb_response = elbv2.create_load_balancer(
    Name="my-app-alb",
    Subnets=["subnet-abc123", "subnet-def456", "subnet-ghi789"],
    SecurityGroups=["sg-alb-0123456789abcdef0"],
    Scheme="internet-facing",
    Type="application",
    IpAddressType="ipv4",
    Tags=[{"Key": "Environment", "Value": "production"}],
)
alb_arn = alb_response["LoadBalancers"][0]["LoadBalancerArn"]
alb_dns = alb_response["LoadBalancers"][0]["DNSName"]
print(f"ALB DNS: {alb_dns}")

# Add a path-based routing rule - send /api/* to the API target group
# (after creating the HTTPS listener)
elbv2.create_rule(
    ListenerArn="arn:aws:elasticloadbalancing:...",
    Priority=10,
    Conditions=[
        {"Field": "path-pattern", "Values": ["/api/*"]},
    ],
    Actions=[
        {"Type": "forward", "TargetGroupArn": target_group_arn},
    ],
)

# Check health of all targets in a target group
health_response = elbv2.describe_target_health(TargetGroupArn=target_group_arn)
for target in health_response["TargetHealthDescriptions"]:
    tid = target["Target"]["Id"]
    state = target["TargetHealth"]["State"]  # healthy | unhealthy | initial | draining
    reason = target["TargetHealth"].get("Reason", "")
    print(f"{tid}: {state} {reason}")

# Deregister a target (for graceful removal during deployment)
elbv2.deregister_targets(
    TargetGroupArn=target_group_arn,
    Targets=[{"Id": "i-0123456789abcdef0"}],
)
# Wait for the target to finish draining (default: 300 seconds deregistration delay)
waiter = elbv2.get_waiter("target_deregistered")
waiter.wait(
    TargetGroupArn=target_group_arn,
    Targets=[{"Id": "i-0123456789abcdef0"}],
)
```

---

## How It Connects

The ALB and Auto Scaling Group are designed to work together. The ALB health check results feed into the ASG's health monitoring - instances failing ALB health checks are terminated and replaced. The ASG registers new instances with the ALB target group automatically when they launch.

[[ec2-auto-scaling|EC2 Auto Scaling Groups]] - ASGs attach to ALB target groups; the ALB health check type in the ASG configuration means failing an ALB health check triggers replacement, not just an EC2-level check.

Security groups for the ALB and the EC2 instances must be configured to work together. The ALB has its own security group allowing inbound 80 and 443 from the internet; the EC2 instances' security group should allow the application port only from the ALB's security group.

[[ec2-security-groups|EC2 Security Groups]] - the recommended pattern is to reference the ALB's security group as the source in the EC2 instances' security group rule for the application port, so EC2 instances are never directly accessible from the internet.

---

## Common Misconceptions

Misconception 1: The ALB forwards the client's original IP address in the standard `REMOTE_ADDR` or `X-Forwarded-For` header transparently.
Reality: Because the ALB terminates the TCP connection and creates a new one to the backend, the EC2 instance sees the ALB's private IP as the client address, not the original browser's IP. The original client IP is added to the `X-Forwarded-For` HTTP header by the ALB. Your Flask or Django application must read `request.headers.get("X-Forwarded-For")` for the real client IP - and strip the ALB's IP from the header if there are multiple entries.

Misconception 2: A target group showing the instance as "healthy" means the application is fully functional.
Reality: The health check only validates what you configured it to check - typically an HTTP GET to `/health` returning 200. A health check can pass even if the database is down, the cache is unavailable, or most application endpoints are throwing 500 errors. The health check path should perform a minimal liveness check (application process is running), and you should rely on separate monitoring and alerting for deeper application health.

---

## Why It Matters in Practice

The ALB is the production standard for Python web applications on EC2 or ECS. It handles SSL termination, removing the need to manage certificates on individual instances. It handles path-based routing, enabling clean multi-service architectures behind a single domain. Its health checks provide automatic traffic cutover when an instance becomes unhealthy. And its integration with Auto Scaling Groups makes it the control plane for instance replacement and scaling.

The deregistration delay (default 300 seconds) is a critical production feature. When the ALB deregisters a target (during ASG scale-in or a rolling deployment), it allows existing connections to complete before the instance is terminated. Without this delay, in-flight requests would be abruptly terminated. Setting an appropriate deregistration delay - long enough for your longest requests to complete, short enough that deployments are not unnecessarily slow - is part of production ALB tuning.

---

## What Breaks in Production

**Python application not reading `X-Forwarded-For` for the real client IP, leading to broken IP-based rate limiting or geo-blocking.**

```python
# Flask - get the real client IP when behind an ALB
from flask import request

def get_client_ip():
    # X-Forwarded-For may contain multiple IPs: client, proxy1, proxy2
    # The first IP is the original client
    xff = request.headers.get("X-Forwarded-For", "")
    if xff:
        return xff.split(",")[0].strip()
    return request.remote_addr

# For production Flask apps, use ProxyFix middleware
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
```

**Health check path returning a non-200 status when the application is starting, causing premature replacement.**

```python
# Create a dedicated, lightweight health check endpoint
# Do NOT perform database checks in the health endpoint - keep it fast
@app.route("/health")
def health():
    return {"status": "ok"}, 200

# If you need database health checks, use a separate /health/deep endpoint
# and do not use it for the ALB target group health check
```

---

## Interview Angle

Common question forms:
- "What is the difference between an ALB and an NLB?"
- "How does SSL termination work with an ALB?"
- "How would you route `/api/*` to one service and `/web/*` to another behind a single ALB?"

Answer frame:
For ALB vs NLB: ALB is Layer 7 HTTP/HTTPS with path/host routing; NLB is Layer 4 TCP/UDP with extreme throughput and static IP. For SSL: certificate at ACM, attached to HTTPS listener; ALB handles TLS; instances receive HTTP on private port. For path routing: two target groups, two rules on the HTTPS listener with path-pattern conditions forwarding to the appropriate target group.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
- [[ec2-security-groups|EC2 Security Groups]]
- [[ec2-python-deployment|Deploying Python Apps on EC2]]
- [[load-balancing|Load Balancing]]
