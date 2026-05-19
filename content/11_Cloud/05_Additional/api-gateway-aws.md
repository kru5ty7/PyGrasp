---
title: 47 - AWS API Gateway
description: API Gateway is AWS's managed HTTP API service - it handles routing, authentication, throttling, and the Lambda proxy integration that turns an HTTP request into a Lambda invocation and back.
tags: [aws, cloud, layer-11, api-gateway, rest, lambda]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# AWS API Gateway

> API Gateway sits between your HTTP clients and your Lambda functions - it handles TLS termination, authentication, rate limiting, and request routing so your function only has to implement business logic.

---

## Quick Reference

**Core idea:**
- Two main types: REST API (feature-rich, older, ~$3.50/million requests) and HTTP API (simpler, cheaper, ~$1/million requests - use this for Lambda integrations)
- Lambda Proxy Integration: API Gateway passes the full HTTP request as the `event` dict and returns the function's response dict to the client
- Routes: `METHOD /path` (e.g. `POST /orders`, `GET /orders/{id}`)
- Authentication options: Lambda authoriser (custom logic), Cognito JWT authoriser, API keys
- Throttling: per-route rate limits (requests/second + burst)
- Custom domain names with ACM TLS certificates

**Tricky points:**
- REST API timeout: 29 seconds; HTTP API timeout: 30 seconds - Lambda functions used with API Gateway must complete within this window
- API Gateway returns `502 Bad Gateway` when the Lambda function returns `null` or a malformed response dict (missing `statusCode`)
- CORS must be configured on API Gateway AND may need CORS headers in the Lambda response
- HTTP API does not support API keys, usage plans, or request/response transformation - use REST API if you need those features
- Deploying a REST API requires an explicit "Deploy" action to make changes live; HTTP API changes are deployed automatically

---

## What It Is

API Gateway is the bouncer at the entrance to your serverless application. Every HTTP request from a client must pass through the bouncer before reaching the Lambda function inside. The bouncer checks credentials (authentication), enforces entry limits (throttling), records who came in and when (logging), and translates the outside world's HTTP vocabulary into the internal format your Lambda function expects (Lambda Proxy Integration). The function inside does not need to know anything about HTTP infrastructure - it receives a structured Python dict and returns a structured Python dict.

The choice between REST API and HTTP API is primarily a features-vs-cost trade. REST API is the original product: it supports request/response transformation using mapping templates, API key management, usage plans, private integrations, and edge-optimised endpoints via CloudFront. HTTP API is a redesigned, streamlined product launched in 2020 for the most common use case - routing HTTP requests to Lambda functions. HTTP API is 70–80% cheaper and has lower latency than REST API but lacks API key management, request/response transformation, and usage plans. For a Python backend where Lambda handles the business logic, HTTP API is almost always the right choice.

The Lambda Proxy Integration is the configuration option that makes API Gateway a transparent pass-through rather than an active transformer. With proxy integration enabled, API Gateway sends the full HTTP request to Lambda as a structured `event` dict: method, path, headers, query string parameters, path parameters, and the body as a string. The Lambda function returns a dict with `statusCode`, `headers`, and `body` (as a JSON string), and API Gateway translates that back into an HTTP response for the client. The entire HTTP request-response cycle passes through Lambda without API Gateway transforming any of it.

---

## How It Actually Works

Configuring an HTTP API with a Lambda integration and a JWT authoriser involves creating the API, creating the Lambda integration, creating the authoriser, and creating routes that reference both. The AWS CLI flow below demonstrates the essential steps.

```bash
# Create an HTTP API
API_ID=$(aws apigatewayv2 create-api \
    --name my-python-api \
    --protocol-type HTTP \
    --cors-configuration AllowOrigins='["https://myapp.com"]',AllowMethods='["GET","POST"]',AllowHeaders='["Content-Type","Authorization"]' \
    --query "ApiId" --output text)

# Create the Lambda integration
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id $API_ID \
    --integration-type AWS_PROXY \
    --integration-uri arn:aws:lambda:us-east-1:123456789012:function:my-api-function \
    --payload-format-version "2.0" \
    --query "IntegrationId" --output text)

# Create a JWT authoriser (using Cognito)
AUTHORIZER_ID=$(aws apigatewayv2 create-authorizer \
    --api-id $API_ID \
    --authorizer-type JWT \
    --identity-source '$request.header.Authorization' \
    --name cognito-authorizer \
    --jwt-configuration Audience=["my-client-id"],Issuer="https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXX" \
    --query "AuthorizerId" --output text)

# Create routes
aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "POST /orders" \
    --target "integrations/$INTEGRATION_ID" \
    --authorization-type JWT \
    --authorizer-id $AUTHORIZER_ID

aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "GET /orders/{orderId}" \
    --target "integrations/$INTEGRATION_ID" \
    --authorization-type JWT \
    --authorizer-id $AUTHORIZER_ID

# Deploy the API (creates a $default stage)
aws apigatewayv2 create-stage \
    --api-id $API_ID \
    --stage-name production \
    --auto-deploy

# Grant API Gateway permission to invoke the Lambda function
aws lambda add-permission \
    --function-name my-api-function \
    --statement-id apigw-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:apigatewayv2:us-east-1:123456789012:/apis/$API_ID/*"
```

Lambda handler for HTTP API v2 payload format:

```python
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    HTTP API v2.0 payload format handler.
    The event shape for HTTP API is slightly different from REST API.
    """
    # HTTP API v2 provides these fields directly
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("requestContext", {}).get("http", {}).get("path", "/")
    path_params = event.get("pathParameters") or {}
    query_params = event.get("queryStringParameters") or {}

    # JWT claims are available when using a JWT authoriser
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    user_id = claims.get("sub")

    logger.info(json.dumps({
        "method": method,
        "path": path,
        "user_id": user_id,
        "request_id": context.aws_request_id,
    }))

    # Route on method and path
    if method == "POST" and path == "/orders":
        return handle_create_order(event, user_id)
    elif method == "GET" and "/orders/" in path:
        order_id = path_params.get("orderId")
        return handle_get_order(order_id, user_id)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}


def handle_create_order(event, user_id):
    body = json.loads(event.get("body") or "{}")
    # ... business logic ...
    return {
        "statusCode": 201,
        "body": json.dumps({"order_id": "new-order-123", "user_id": user_id}),
        "headers": {"Content-Type": "application/json"},
    }


def handle_get_order(order_id, user_id):
    # ... fetch order ...
    return {
        "statusCode": 200,
        "body": json.dumps({"order_id": order_id, "status": "processing"}),
        "headers": {"Content-Type": "application/json"},
    }
```

---

## How It Connects

API Gateway is the front door for Lambda functions exposed as HTTP endpoints. It is the primary way a Python FastAPI-style backend is deployed serverlessly on AWS - but with the handler contract instead of ASGI middleware.

[[lambda-handlers|Lambda Handlers]] - the Lambda handler's required return format (`statusCode`, `headers`, `body`) is defined by the API Gateway proxy integration contract; the two are tightly coupled.

API Gateway authentication with JWT authorisers requires understanding the IAM and Cognito identity model. Lambda authorisers are an alternative where custom Python code makes the authorisation decision.

[[iam-roles|IAM Roles]] - API Gateway can use IAM-based authentication (`AWS_IAM` authorisation type), in which callers must sign requests with SigV4; this integrates with the IAM roles model described in the IAM notes.

---

## Common Misconceptions

Misconception 1: API Gateway automatically retries Lambda invocations on failure.
Reality: API Gateway does not retry. If a Lambda function returns a 5xx response or throws an unhandled exception (which causes a 502), the error is returned to the client immediately. Retries are the client's responsibility for synchronous API calls. This differs from asynchronous trigger patterns (SQS, S3) where Lambda's retry behaviour is configurable.

Misconception 2: You need to use REST API to get features like JWT authentication.
Reality: HTTP API supports JWT authorisers natively and is significantly cheaper than REST API. The cases where REST API is genuinely required are: API key management with usage plans, per-request request/response transformation using mapping templates, private API endpoints (inside a VPC without a public endpoint), and edge-optimised endpoints via CloudFront. For the vast majority of serverless Python backends, HTTP API is sufficient.

---

## Why It Matters in Practice

API Gateway is the canonical way to expose Lambda functions as HTTP services without running a web server. Understanding the Lambda Proxy Integration response format is mandatory - a function that does not return the correct shape produces a 502 for every request, and the error message from API Gateway (`{"message": "Internal Server Error"}`) gives no indication of what the function returned. Developers who internalise the `statusCode + headers + body` response contract, understand the CORS configuration requirements, and know the timeout ceiling (29/30 seconds) build API-integrated Lambda functions that work reliably from the first deploy.

---

## What Breaks in Production

**Scenario 1: 502 from missing statusCode**

```python
# Mistake: handler returns a Python dict without statusCode
def handler(event, context):
    return {"message": "success"}  # API Gateway requires statusCode → 502 Bad Gateway

# Fix: always include statusCode
def handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "success"}),
        "headers": {"Content-Type": "application/json"},
    }
```

**Scenario 2: CORS preflight fails because CORS is configured on API Gateway but not in Lambda response headers**

```python
# Situation: API Gateway has CORS configured, but some browsers still show CORS errors
# Cause: for Lambda proxy integration, the Lambda function must include CORS headers in its response

def handler(event, context):
    # The event may be an OPTIONS preflight request
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "https://myapp.com",
                "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type,Authorization",
            },
            "body": "",
        }

    # Include CORS headers in all responses
    return {
        "statusCode": 200,
        "body": json.dumps({"data": "response"}),
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "https://myapp.com",
        },
    }
```

---

## Interview Angle

Common question forms:
- "What is the Lambda Proxy Integration and why do you need it?"
- "What is the difference between REST API and HTTP API in API Gateway?"
- "How would you add authentication to an API Gateway endpoint backed by Lambda?"

Answer frame:
Explain Lambda Proxy Integration as the pass-through mode where API Gateway sends the full HTTP request as a Lambda event and uses the function's return dict as the HTTP response. Distinguish REST API (full features, higher cost) from HTTP API (simpler, cheaper, correct for most Lambda use cases). For authentication: JWT authoriser for standards-based token auth, Lambda authoriser for custom logic, IAM auth for service-to-service calls.

---

## Related Notes

- [[lambda-handlers|Lambda Handlers]]
- [[lambda-python|Lambda with Python]]
- [[lambda-iam|Lambda IAM Execution Role]]
- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[fastapi|FastAPI]]
