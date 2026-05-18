---
title: 32 - Deploying Python Apps on EC2
description: The production-grade pattern for running a Python web application on EC2 uses gunicorn as the WSGI server behind nginx as a reverse proxy, managed by systemd — understanding why each layer exists prevents common deployment failures.
tags: [aws, cloud, layer-11, ec2, deployment, python, gunicorn]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Deploying Python Apps on EC2

> Deploying a Python web application to EC2 means choosing a stack — gunicorn, nginx, systemd, virtualenv — where each component has a specific, non-interchangeable role, and getting the configuration right determines whether your application handles production traffic reliably.

---

## Quick Reference

**Core idea:**
- Stack: Ubuntu + virtualenv + gunicorn (WSGI server) + nginx (reverse proxy) + systemd (process manager)
- gunicorn runs the Python application workers; it cannot safely handle slow clients, TLS, or static files
- nginx sits in front of gunicorn: terminates HTTPS, serves static files, buffers slow clients, proxies dynamic requests to gunicorn via a Unix socket
- systemd manages gunicorn as a service: starts on boot, restarts on crash, logs to journald
- Environment variables (secrets, database URLs) must not be in code — use systemd `EnvironmentFile` or AWS Parameter Store / Secrets Manager

**Tricky points:**
- gunicorn workers must equal roughly `(2 * vCPUs) + 1` for CPU-bound workloads — too few means wasted CPU capacity, too many means memory pressure
- A Unix socket between nginx and gunicorn is faster and more secure than a TCP loopback port (no port collision, no TCP overhead)
- `gunicorn --timeout` defaults to 30 seconds — requests taking longer (ML inference, slow DB queries) need an increased timeout or async workers
- Static files served by gunicorn are a performance antipattern — nginx serves them 10-100x faster from disk without touching Python
- The virtualenv must be activated in the systemd unit with the full path — `ExecStart=/home/appuser/venv/bin/gunicorn`

---

## What It Is

Imagine a busy restaurant. The kitchen (gunicorn workers) processes orders — each worker handles one order at a time, producing the meal. But the kitchen cannot deal directly with customers: it cannot manage the front door, handle coat checks, or carry out all the preliminary customer management. A front-of-house team (nginx) manages all of that: greeting customers, handling the coat check (SSL), directing them to their tables, and relaying orders to the kitchen. The kitchen staff can focus entirely on cooking. If a customer sits down and orders but then spends 20 minutes deciding what to add to their order (a slow client), the front-of-house handles the wait — the kitchen worker does not stand idle waiting for them.

This separation of concerns — nginx handling the internet-facing work, gunicorn handling the Python-specific work — is the reason the two-layer architecture exists. Python's reference implementation (CPython) has the Global Interpreter Lock (GIL), which means a single Python process can only execute one thread at a time. gunicorn works around this by running multiple worker processes, each handling one request at a time. But those worker processes are expensive — each one holds a Python interpreter, your application's full in-memory state, and connection pool resources. You want gunicorn workers to spend their time executing Python code, not waiting for a slow network connection to receive the full HTTP request body.

nginx solves the slow-client problem by buffering. When a mobile client is uploading a large file slowly, nginx receives and buffers the entire request body before passing it to gunicorn in a single fast call. Without this buffering, a gunicorn worker would sit idle for the entire duration of the upload — unable to handle any other requests. With nginx in front, gunicorn workers are always busy processing complete requests and returning results, while nginx handles all the buffering and connection management.

---

## How It Actually Works

The deployment stack operates as a chain of processes. nginx listens on ports 80 and 443. For HTTPS requests, it terminates the TLS connection using a certificate from Let's Encrypt (via certbot) or AWS Certificate Manager (if the ALB handles TLS — then EC2 instances can use plain HTTP). After TLS termination, nginx evaluates the request: if it matches a static file location (`/static/`, `/media/`), nginx serves it directly from disk. If it matches the application location (`/`), nginx forwards the request to gunicorn via a Unix domain socket — a file-based IPC channel that is faster than a TCP loopback connection.

gunicorn receives the request on the Unix socket, passes it to a Python worker process as a WSGI environ dictionary, runs the application code, gets the response, and sends it back through the socket to nginx. nginx then sends the response to the client. systemd monitors the gunicorn process group — if gunicorn crashes (due to an uncaught exception that propagates all the way to the worker level, an out-of-memory kill, or a signal), systemd restarts it according to the `Restart=on-failure` policy in the service unit.

```bash
# On the EC2 instance (Ubuntu 22.04 — run via user data or manual SSH)

# 1. Update and install system packages
sudo apt-get update -y
sudo apt-get install -y python3.11 python3.11-venv nginx certbot python3-certbot-nginx

# 2. Create app user
sudo useradd -m -s /bin/bash appuser

# 3. Set up application directory and virtualenv
sudo -u appuser python3.11 -m venv /home/appuser/venv
sudo -u appuser /home/appuser/venv/bin/pip install gunicorn flask

# 4. Create systemd runtime directory for the Unix socket
sudo mkdir -p /run/gunicorn
sudo chown appuser:www-data /run/gunicorn

# 5. systemd service file
sudo tee /etc/systemd/system/gunicorn.service > /dev/null << 'EOF'
[Unit]
Description=Gunicorn instance for my Python application
After=network.target

[Service]
Type=notify
User=appuser
Group=appuser
WorkingDirectory=/home/appuser/app
EnvironmentFile=/home/appuser/app/.env
ExecStart=/home/appuser/venv/bin/gunicorn \
    --workers 5 \
    --worker-class sync \
    --timeout 120 \
    --bind unix:/run/gunicorn/gunicorn.sock \
    --access-logfile /var/log/gunicorn/access.log \
    --error-logfile /var/log/gunicorn/error.log \
    wsgi:app
RuntimeDirectory=gunicorn
RuntimeDirectoryMode=0755
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /var/log/gunicorn
sudo chown appuser:appuser /var/log/gunicorn
sudo systemctl daemon-reload
sudo systemctl enable gunicorn
sudo systemctl start gunicorn

# 6. nginx configuration
sudo tee /etc/nginx/sites-available/myapp > /dev/null << 'EOF'
upstream gunicorn {
    server unix:/run/gunicorn/gunicorn.sock fail_timeout=0;
}

server {
    listen 80;
    server_name myapp.example.com;
    # Redirect HTTP to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name myapp.example.com;

    ssl_certificate /etc/letsencrypt/live/myapp.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myapp.example.com/privkey.pem;

    # Static files served directly by nginx (no Python involved)
    location /static/ {
        alias /home/appuser/app/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # All other requests go to gunicorn
    location / {
        proxy_pass http://gunicorn;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp
sudo nginx -t && sudo systemctl reload nginx
```

```python
# wsgi.py — the entry point gunicorn calls
from myapp import create_app

app = create_app()

if __name__ == "__main__":
    app.run()

# .env file (referenced by systemd EnvironmentFile) — never commit this
# DATABASE_URL=postgresql://user:password@rds-host:5432/mydb
# SECRET_KEY=your-secret-key-here
# AWS_DEFAULT_REGION=eu-west-1
# ENVIRONMENT=production

# Deployment update script — pull new code and restart gunicorn
import subprocess, sys

def deploy_update():
    # Pull latest code from S3 or git
    subprocess.run(["aws", "s3", "sync",
                    "s3://my-deployment-bucket/app/latest/",
                    "/home/appuser/app/"], check=True)

    # Install any new dependencies
    subprocess.run(["/home/appuser/venv/bin/pip", "install", "-r",
                    "/home/appuser/app/requirements.txt"], check=True)

    # Graceful restart — gunicorn workers finish their current requests
    # before being replaced (send SIGHUP to master process)
    subprocess.run(["sudo", "systemctl", "reload", "gunicorn"], check=True)
    print("Deployment complete")

# Calculate appropriate worker count
import os
vcpus = os.cpu_count() or 1
# Sync workers: 2 * vCPUs + 1 (standard formula)
worker_count = (2 * vcpus) + 1
# Async workers (gevent/uvicorn): can use more workers since they don't block
```

---

## How It Connects

Environment variables — database passwords, secret keys, API tokens — must never be hardcoded in application code or the systemd unit file. The recommended pattern is to store secrets in AWS Secrets Manager or Parameter Store and retrieve them at application startup or inject them via the systemd `EnvironmentFile`.

[[secret-management|Secret Management]] — how to store and retrieve secrets from AWS Secrets Manager or Parameter Store, and how to inject them into a Python application running under systemd.

For production deployments serving real traffic, the EC2 instance should sit behind an Application Load Balancer rather than being directly internet-exposed. The ALB handles SSL termination (removing the need for nginx to manage certificates) and provides health-check-based traffic routing.

[[ec2-elb|Elastic Load Balancer]] — when the ALB handles TLS termination, nginx does not need SSL certificates; EC2 instances receive plain HTTP from the ALB on the application port; the nginx configuration simplifies to proxying without SSL.

---

## Common Misconceptions

Misconception 1: `flask run` or Django's development server is fine for production.
Reality: The Flask development server (`app.run()`) and Django's `python manage.py runserver` are single-threaded servers designed for development. They handle one request at a time, do not buffer clients, have no worker management, and do not restart on crashes. Running them in production means your application cannot handle concurrent requests, is one exception away from going offline, and has no graceful restart capability. gunicorn (or uWSGI, or uvicorn for async frameworks) is the correct WSGI/ASGI server for production.

Misconception 2: More gunicorn workers always means better performance.
Reality: Each gunicorn worker is a full Python process with its own memory footprint. A Flask application with 500MB of in-memory state running 20 workers on a 2GB instance will exhaust memory, causing the OS to swap and performance to collapse. The standard formula — `(2 * vCPUs) + 1` for CPU-bound workloads — is a starting point, but the actual limit is constrained by available memory. Profile your worker memory usage and size your instance and worker count together.

---

## Why It Matters in Practice

The gunicorn + nginx + systemd stack is the foundation of EC2-based Python deployments across thousands of production applications. Understanding why each layer exists prevents two categories of mistakes: deploying without nginx (gunicorn handles slow clients directly, exhausting workers under load) and deploying without systemd (process crashes cause permanent downtime until someone SSH's in and restarts manually).

The deployment update process is equally important. Rolling updates — deploying new code to one instance at a time while the others remain in service — require the ability to gracefully restart gunicorn (`systemctl reload gunicorn` sends SIGHUP to the master, which starts new workers with the new code and waits for old workers to finish their current requests before killing them). Abrupt restarts (`systemctl restart gunicorn`) cause brief downtime as all workers are killed simultaneously.

---

## What Breaks in Production

**gunicorn timeout killing long-running requests.** The default 30-second worker timeout kills any request that takes longer than 30 seconds, including legitimate ML inference calls, complex report generation, or slow database queries.

```bash
# Increase timeout in the gunicorn start command
ExecStart=/home/appuser/venv/bin/gunicorn \
    --workers 5 \
    --timeout 300 \    # 5 minutes — adjust for your slowest legitimate request
    --bind unix:/run/gunicorn/gunicorn.sock \
    wsgi:app

# Or use async workers (gevent) for I/O-bound workloads — no timeout on waiting
ExecStart=/home/appuser/venv/bin/gunicorn \
    --workers 5 \
    --worker-class gevent \
    --bind unix:/run/gunicorn/gunicorn.sock \
    wsgi:app
```

**nginx proxy_read_timeout shorter than gunicorn timeout, causing 504 Gateway Timeout before gunicorn even kills the worker.**

```nginx
# nginx.conf — must be longer than or equal to gunicorn --timeout
location / {
    proxy_pass http://gunicorn;
    proxy_read_timeout 300s;   # must be >= gunicorn timeout
    proxy_send_timeout 300s;
    proxy_connect_timeout 10s;
}
```

**Deploying new code with `systemctl restart gunicorn` instead of `reload`, causing a brief outage as all workers restart simultaneously.**

```bash
# Bad — kills all workers immediately, brief downtime
sudo systemctl restart gunicorn

# Good — sends SIGHUP; master starts new workers before killing old ones
sudo systemctl reload gunicorn

# Verify gunicorn supports graceful restart (it does for sync workers)
sudo kill -HUP $(cat /var/run/gunicorn/gunicorn.pid)
```

---

## Interview Angle

Common question forms:
- "How would you deploy a Flask application to a production EC2 instance?"
- "Why do you need nginx in front of gunicorn?"
- "How do you handle environment-specific secrets in a systemd-managed Python application?"

Answer frame:
For deployment: virtualenv, gunicorn as WSGI server, nginx as reverse proxy, systemd as process manager, EnvironmentFile for secrets. For nginx: buffers slow clients so gunicorn workers stay busy; serves static files without touching Python; handles SSL; provides gzip, caching, rate limiting. For secrets: systemd EnvironmentFile pointing to a file with restricted permissions, or fetch from Parameter Store at application startup using boto3 with instance profile credentials.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-user-data|EC2 User Data Scripts]]
- [[ec2-elb|Elastic Load Balancer]]
- [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
- [[secret-management|Secret Management]]
- [[logging-production|Logging in Production]]
