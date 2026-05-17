---
title: 03 - JWT
description: "JSON Web Token (JWT) is a compact, self-contained token format — three base64url-encoded parts (header.payload.signature) signed with HMAC or RSA; the server verifies the signature without database lookup; claims like `sub` (subject), `exp` (expiry), and custom data live in the payload."
tags: [jwt, JSON-Web-Token, bearer-token, HS256, RS256, claims, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# JWT

> JSON Web Token (JWT) is a compact, self-contained token format — three base64url-encoded parts (header.payload.signature) signed with HMAC or RSA; the server verifies the signature without database lookup; claims like `sub` (subject), `exp` (expiry), and custom data live in the payload.

---

## Quick Reference

**Core idea:**
- JWT structure: `header.payload.signature` — each part is base64url-encoded JSON
- `header`: algorithm (`alg: HS256` or `RS256`) and token type (`typ: JWT`)
- `payload`: claims — `sub` (subject/user ID), `exp` (expiry timestamp), `iat` (issued at), custom data
- `signature`: `HMAC(base64(header) + "." + base64(payload), secret_key)` for HS256
- Verification: re-compute the signature; if it matches, the payload is authentic and unmodified

**Tricky points:**
- JWT payload is base64url-encoded, NOT encrypted — anyone can decode and read it; never put sensitive data (passwords, PII) in the payload
- `exp` claim is checked by the library during `decode()` — an expired token raises `ExpiredSignatureError`; always set `exp`
- `HS256` uses a shared secret (symmetric) — both signing and verification use the same key; not suitable for multi-service architectures where the verifier shouldn't be able to issue tokens
- `RS256` uses a private key to sign and a public key to verify — the auth service holds the private key; other services hold the public key (asymmetric; better for microservices)
- Token revocation is the main drawback of stateless JWT — there's no built-in way to invalidate a token before it expires; use a token blocklist (Redis) for revocation

---

## What It Is

JWT solves the stateless authentication problem: the server needs to know who made a request without maintaining a session store. By signing the token, the server guarantees the payload hasn't been tampered with. Any server that knows the secret (HS256) or has the public key (RS256) can verify the token independently.

Think of it as a signed government ID card. The card contains your information (payload). The signature is the official seal — anyone with the verification tools can confirm the card is genuine. The ID doesn't need to be checked against a central database for every use.

---

## How It Actually Works

Creating and verifying JWTs with `python-jose` (PyJWT is also common):
```python
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError

SECRET_KEY = "your-secret-key"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

def create_access_token(user_id: int, extra_claims: dict = {}) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
        **extra_claims,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
```

FastAPI login endpoint:
```python
@app.post("/auth/login")
async def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter_by(email=credentials.email).first()
    if not user or not verify_password(credentials.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    token = create_access_token(user.id, extra_claims={"role": user.role})
    return {"access_token": token, "token_type": "bearer"}
```

Decoding reveals (but not verifying) the payload:
```python
import base64, json

token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiIsInJvbGUiOiJ1c2VyIn0.xxxxx"
header_b64, payload_b64, sig = token.split(".")
payload = json.loads(base64.urlsafe_b64decode(payload_b64 + "=="))
# {"sub": "42", "role": "user"}  ← anyone can read this without the secret
```

---

## How It Connects

JWT is the most common authentication mechanism in FastAPI — the `get_current_user` dependency decodes the JWT from the `Authorization: Bearer` header.
[[authentication-vs-authorization|Authentication vs Authorization]]

OAuth2 uses JWT as the access token format — the `oauth2_scheme` in FastAPI extracts the bearer token.
[[oauth2|OAuth2]]

---

## Common Misconceptions

Misconception 1: "JWT is encrypted."
Reality: JWT is signed, not encrypted. The payload is base64url-encoded (trivially reversed) and visible to anyone with the token. To encrypt the payload, use JWE (JSON Web Encryption) — a separate standard. Standard JWT does NOT hide the payload contents.

Misconception 2: "JWTs can be revoked by deleting them."
Reality: There is no central store to delete from. A JWT is valid until it expires, regardless of what the server does. Revocation requires either: short expiry times (5-15 min) + refresh tokens, or a blocklist stored in Redis keyed by the JWT `jti` (JWT ID) claim.

---

## Why It Matters in Practice

Refresh token pattern:
```
1. Login → access_token (short-lived: 15 min) + refresh_token (long-lived: 7 days)
2. Access token in every request header: Authorization: Bearer <access_token>
3. When access_token expires (401) → client sends refresh_token to /auth/refresh
4. Server verifies refresh_token (may be stored in DB for revocation) → issues new access_token
5. Logout → revoke refresh_token in DB
```

This balances security (short-lived tokens are useless when stolen) with UX (no frequent re-logins).

---

## Interview Angle

Common question forms:
- "How does JWT authentication work?"
- "What are the parts of a JWT?"

Answer frame: JWT = `header.payload.signature` (base64url). Header: algorithm. Payload: claims (`sub`, `exp`, custom). Signature: HMAC of header+payload with secret. Verification: recompute signature — if match, payload is authentic. NOT encrypted — don't put sensitive data in payload. Expiry via `exp` claim — check automatically on `decode()`. Revocation problem: use short expiry + refresh tokens or Redis blocklist.

---

## Related Notes

- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[oauth2|OAuth2]]
- [[fastapi-security|Security in FastAPI]]
- [[hashing-and-passwords|Hashing and Passwords]]
