---
title: 03 - Design a Notification System
description: "A walkthrough of designing a multi-channel notification system  -  fanout architecture, template rendering, delivery guarantees, and preference management."
tags: [system-design, case-study, notifications, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design a Notification System

> A notification system is deceptively simple on the surface  -  "just send a message"  -  but the combination of multiple channels, high volume, delivery guarantees, user preferences, and third-party provider failures makes it one of the more architecturally rich problems in a system design interview.

---

## Quick Reference

**Core idea:**
- Notifications flow through three stages: triggering event -> notification service -> channel delivery (email, push, SMS)
- Fanout: one triggering event produces many individual notifications (e.g., one post liked -> notify the author)
- Worker queues decouple the notification service from channel-specific delivery workers
- Each channel (email via SES/SendGrid, push via APNs/FCM, SMS via Twilio) has different throughput, latency, and cost characteristics
- User preferences determine which channels a user wants to receive which notification types on

**Key design decisions:**
- Separate queues per channel: an email queue, a push queue, an SMS queue  -  each with its own worker pool and retry logic
- Idempotency key per notification to prevent duplicate sends on retry
- Template service: store notification templates in the database, render at send time with dynamic variables
- Device token management: mobile push requires storing and invalidating device tokens; a token can become stale when a user uninstalls and reinstalls the app
- Rate limiting per user: prevent notification spam (e.g., max 5 emails per hour per user from any channel)

---

## What It Is

A notification system is a piece of infrastructure that other services use to communicate with users. When a user is mentioned in a comment, the comments service does not send the notification  -  it calls the notification service with an event, and the notification service determines who should be notified, on which channels, and then delivers the message. This separation matters because the notification service needs to enforce cross-cutting concerns that no individual product service should own: user preferences (do not email me, only push), rate limiting (do not send ten emails in a minute), deduplication (if the same event fires twice, do not send twice), and delivery tracking (did the email actually get delivered?).

The problem divides into four functional requirements and four non-functional ones. Functional: users can set notification preferences per channel and per notification type; the system supports email, SMS, and mobile push; other services can trigger notifications through an API; and the system tracks delivery status. Non-functional: high throughput (a social platform may need to send millions of notifications per day), low latency for push notifications (a message notification should arrive in seconds), at-least-once delivery guarantees (missed notifications are worse than duplicate ones), and graceful degradation when a third-party provider (SendGrid, FCM) is down.

The scale of a real notification system is dominated by the fanout problem. If a celebrity with 10 million followers posts a new video, and 30% of those followers have "new video from this creator" push notifications enabled, the system must enqueue 3 million push notifications within seconds of the event. The write amplification from fanout is the central scaling challenge.

---

## How It Actually Works

**Event ingestion** is the entry point. Other services publish notification events to a message queue or call the notification service directly. An event carries the triggering information: event type, actor, recipient (or list of recipients), and context data. The notification service enriches this with user preference lookups and template rendering before handing off to delivery workers.

**Fanout** for high-follower actors (celebrities, viral content) cannot be done synchronously. The standard pattern is to enqueue a fanout job that expands the recipient list asynchronously. For normal users, direct per-recipient enqueue is fine. For accounts with more than a threshold number of followers (say, 100,000), the fanout is offloaded to a dedicated high-volume fanout worker that pages through the follower list and enqueues individual notifications in batches.

**Channel routing** happens after preference lookup. The notification service checks the user's preferences for this notification type and this channel. If the user has disabled email for social notifications but enabled push, only a push notification is enqueued. The channel-specific queues isolate different delivery mechanisms  -  a backlog in the email queue (caused by a SendGrid outage) does not affect push delivery.

```python
from fastapi import FastAPI
from pydantic import BaseModel
from enum import Enum
import redis
import json

app = FastAPI()
r = redis.Redis(decode_responses=True)

class Channel(str, Enum):
    EMAIL = "email"
    PUSH = "push"
    SMS = "sms"

class NotificationEvent(BaseModel):
    event_type: str           # e.g., "comment_mention", "new_follower"
    actor_id: str             # who triggered the event
    recipient_ids: list[str]  # who should be notified
    context: dict             # template variables

@app.post("/notifications/trigger")
async def trigger_notification(event: NotificationEvent):
    """Receive event from internal services, fanout to per-channel delivery queues."""
    for recipient_id in event.recipient_ids:
        # Load user notification preferences from cache
        prefs_key = f"notif_prefs:{recipient_id}"
        prefs = r.hgetall(prefs_key)
        if not prefs:
            prefs = load_preferences_from_db(recipient_id)
            r.hset(prefs_key, mapping=prefs)
            r.expire(prefs_key, 3600)

        # Deduplicate: skip if already sent this notification
        dedup_key = f"notif_sent:{recipient_id}:{event.event_type}:{event.actor_id}"
        if r.set(dedup_key, "1", nx=True, ex=3600):  # NX = only set if not exists
            # Enqueue to per-channel queues based on preferences
            for channel in Channel:
                pref_key = f"{event.event_type}:{channel.value}"
                if prefs.get(pref_key, "1") == "1":  # default enabled
                    task = {
                        "recipient_id": recipient_id,
                        "event_type": event.event_type,
                        "channel": channel.value,
                        "context": event.context,
                        "idempotency_key": dedup_key
                    }
                    r.rpush(f"notif_queue:{channel.value}", json.dumps(task))

    return {"queued": len(event.recipient_ids)}

# Push notification delivery worker
import httpx

async def deliver_push_notification(task: dict):
    """
    Deliver push notification via FCM (Firebase Cloud Messaging).
    Handles: device token lookup, FCM API call, token invalidation on 404.
    """
    recipient_id = task["recipient_id"]
    device_tokens = get_device_tokens(recipient_id)  # from device_tokens table

    if not device_tokens:
        return  # user has no registered devices

    template = render_template(task["event_type"], task["context"])

    for token in device_tokens:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "https://fcm.googleapis.com/v1/projects/myapp/messages:send",
                headers={"Authorization": f"Bearer {FCM_ACCESS_TOKEN}"},
                json={
                    "message": {
                        "token": token,
                        "notification": {
                            "title": template["title"],
                            "body": template["body"]
                        },
                        "data": {"event_type": task["event_type"]}
                    }
                },
                timeout=10.0
            )
            if response.status_code == 404:
                # Device token is stale (app uninstalled)  -  remove it
                invalidate_device_token(recipient_id, token)
            elif response.status_code != 200:
                # Retry: re-enqueue with backoff
                requeue_with_backoff(task)

def render_template(event_type: str, context: dict) -> dict:
    """Load notification template from cache/DB and render with context variables."""
    template = get_template(event_type)  # e.g., {"title": "{{actor}} mentioned you", ...}
    return {
        "title": template["title"].format(**context),
        "body": template["body"].format(**context)
    }
```

**Delivery tracking** requires persisting delivery outcomes. For email, webhooks from SendGrid or SES confirm delivery, bounces, and opens. For push, FCM returns immediate success/failure per token. For SMS, Twilio provides delivery receipts asynchronously via webhook. These outcomes update a `notification_logs` table used for analytics and debugging.

**The three most important design decisions:** (1) Queue per channel  -  isolation prevents one slow channel from blocking others. (2) Idempotency on every notification  -  retry is the default behavior; deduplication prevents user-visible duplicates. (3) Async fanout for high-follower accounts  -  synchronous fanout would timeout; the notification service must detect when recipient count is large and hand off to a dedicated fanout worker.

---

## Why It Matters in Practice

Notification systems expose the tension between completeness and user experience. Over-notification drives users to disable all notifications and lose the value of the communication channel entirely. Under-notification means users miss important events. The preference system and notification type taxonomy (transactional vs. promotional vs. social) is as important as the delivery architecture. A well-designed notification system is one users trust to send exactly what they want, reliably.

---

## Interview Angle

Common question forms:
- "Design a notification system for a social media platform."
- "How do you handle fanout for celebrity accounts with millions of followers?"
- "How do you ensure push notifications are not sent twice on retry?"

Answer frame:
Requirements: multi-channel (email, push, SMS), user preferences, delivery guarantees. Fanout problem: single event -> many notifications -> separate fanout from delivery. Queue per channel for isolation. Preference lookup: user settings determine which channels fire for which event types. Idempotency key on each notification to handle retries. Device token management: stale tokens returned by FCM must be invalidated. Delivery tracking: webhook callbacks update notification_logs. Scale: separate worker pools per channel, high-volume accounts use async fanout workers.

---

## Related Notes

- [[message-queues|Message Queues]]
- [[pub-sub-pattern|Pub/Sub Pattern]]
- [[redis-data-structures|Redis Data Structures]]
- [[idempotency|Idempotency]]
- [[api-design-principles|API Design Principles]]
