---
title: 02 - Hashing and Passwords
description: "Password hashing converts a password to an irreversible digest using algorithms like bcrypt or Argon2 — the original password cannot be recovered; `passlib` with `bcrypt` context is the standard Python choice; salting prevents rainbow table attacks; never store plaintext passwords."
tags: [hashing, passwords, bcrypt, argon2, passlib, salt, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Hashing and Passwords

> Password hashing converts a password to an irreversible digest using algorithms like bcrypt or Argon2 — the original password cannot be recovered; `passlib` with `bcrypt` context is the standard Python choice; salting prevents rainbow table attacks; never store plaintext passwords.

---

## Quick Reference

**Core idea:**
- `CryptContext(schemes=["bcrypt"])` — `passlib` context using bcrypt
- `pwd_context.hash(password)` — hash a password; includes a random salt; each call produces a different hash
- `pwd_context.verify(plain_password, hashed_password)` — compare plain text against stored hash; returns `bool`
- bcrypt cost factor: `rounds=12` is the default (2^12 iterations); increase to slow down brute-force as hardware improves
- Never use MD5 or SHA for passwords — they're fast hash functions; password hashing must be intentionally slow

**Tricky points:**
- `bcrypt` outputs a string like `$2b$12$salt22chars...hash31chars` — the hash includes the algorithm, cost, and salt encoded together; no need to store salt separately
- `verify()` is constant-time — it takes the same time for matching and non-matching passwords; prevents timing attacks
- bcrypt has a 72-byte input limit — passwords longer than 72 bytes are silently truncated; use `bcrypt` + `sha256` pre-hash if you must support very long passwords
- Migrating algorithms: `passlib`'s `CryptContext(deprecated=["md5_crypt"])` marks old hashes as deprecated and re-hashes on next successful login
- Cost factor tuning: target ~100-300ms per hash on your production hardware — fast enough for UX, slow enough to make brute-force impractical

---

## What It Is

Passwords are stored as hashes — not the original password. When a user logs in, you hash their input and compare it to the stored hash. If the database is leaked, attackers get hashes, not passwords. A strong hash function (bcrypt, Argon2) makes brute-forcing hashes computationally expensive.

Salting (adding random data before hashing) ensures that two users with the same password have different hashes — this defeats precomputed rainbow tables where attackers pre-hash common passwords.

MD5 and SHA-256 are NOT password hash functions — they're designed to be fast (for checksums), which makes brute-forcing trivial. Use bcrypt, Argon2, or scrypt which are deliberately slow.

---

## How It Actually Works

Setup with `passlib`:
```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

User creation and login:
```python
@app.post("/users", status_code=201)
async def create_user(user: UserCreate, db: Session = Depends(get_db)):
    if db.query(User).filter_by(email=user.email).first():
        raise HTTPException(409, "Email already registered")
    
    db_user = User(
        email=user.email,
        password_hash=hash_password(user.password),  # never store user.password
    )
    db.add(db_user)
    db.commit()
    return UserResponse.from_orm(db_user)

@app.post("/auth/token")
async def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter_by(email=form.username).first()
    
    # Verify hash — constant-time comparison
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(401, "Invalid credentials")
    
    return {"access_token": create_access_token(user.id), "token_type": "bearer"}
```

Comparing hashes (what's happening internally):
```python
import bcrypt

salt = bcrypt.gensalt(rounds=12)
hashed = bcrypt.hashpw(b"password", salt)
# b'$2b$12$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'

bcrypt.checkpw(b"password", hashed)   # True
bcrypt.checkpw(b"wrong", hashed)      # False
```

---

## How It Connects

Password hashing is the mechanism that makes authentication credentials safe to store — used in the login and registration flows.
[[authentication-vs-authorization|Authentication vs Authorization]]

JWT authentication begins after successful password verification — the access token is issued only after `verify_password()` returns True.
[[jwt|JWT]]

---

## Common Misconceptions

Misconception 1: "SHA-256 is secure enough for passwords."
Reality: SHA-256 can compute billions of hashes per second on modern GPUs. Bcrypt at rounds=12 computes ~4 hashes/second per GPU core. For password storage, slowness is a feature. Use bcrypt, Argon2, or scrypt.

Misconception 2: "Salting is a separate step you have to implement."
Reality: bcrypt (and most password hash functions) automatically generate and embed a unique random salt in the hash output. The `$2b$12$...` string contains the salt. You don't need to store the salt separately.

---

## Why It Matters in Practice

Checklist for secure password handling:
1. Hash with bcrypt/Argon2 before storing — never store plaintext
2. Use `verify()` (constant-time) — never `==` comparison
3. Set cost factor for ~100-300ms on production hardware
4. Consider minimum password length + complexity requirements (enforced in Pydantic validators)
5. Rate-limit login attempts to prevent online brute-forcing
6. Use HTTPS — plaintext password sent over HTTP is leaked regardless of hashing

---

## Interview Angle

Common question forms:
- "How do you securely store passwords?"
- "Why not use SHA-256 for passwords?"

Answer frame: Hash with bcrypt (intentionally slow) — never store plaintext. `passlib.CryptContext(schemes=["bcrypt"])` — `.hash(pwd)` to store, `.verify(plain, hashed)` to check (constant-time). Salt is automatic and embedded in the hash output. SHA-256/MD5 are too fast — attackers can brute-force billions of attempts/sec. bcrypt target: ~100-300ms/hash for practical brute-force resistance.

---

## Related Notes

- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[jwt|JWT]]
- [[fastapi-security|Security in FastAPI]]
- [[oauth2|OAuth2]]
