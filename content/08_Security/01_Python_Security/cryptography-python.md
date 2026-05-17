---
title: 04 - Cryptography with Python
description: "Python's cryptography library provides high-level symmetric encryption (Fernet), asymmetric encryption and signing (RSA, ECDSA), and key derivation — knowing when to use each primitive and why bcrypt beats SHA-256 for passwords is essential applied cryptography."
tags: [cryptography, encryption, hashing, fernet, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Cryptography with Python

> The most dangerous thing in applied cryptography is using the right algorithm for the wrong purpose — SHA-256 for passwords or AES without authentication are common examples that look correct but fail badly in practice.

---

## Quick Reference

**Core idea:**
- `cryptography` library (PyPI: `cryptography`) is the standard for serious cryptographic operations — use it instead of `hashlib` for anything security-critical beyond simple checksums
- Fernet: symmetric authenticated encryption (AES-128-CBC + HMAC-SHA256) — suitable for encrypting data you need to decrypt later
- RSA / ECDSA: asymmetric algorithms for signing (prove origin/integrity without sharing a secret) and public key encryption
- bcrypt / Argon2: password hashing algorithms with intentional cost factors — slow by design to resist brute-force
- SHA-256 is fast and suitable for checksums/data integrity; it is not suitable for passwords because its speed makes brute-force practical

**Tricky points:**
- Fernet keys must be kept secret — they are symmetric (same key encrypts and decrypts) — losing the key means losing the data forever
- RSA encryption is slow and has a maximum message size; in practice, RSA encrypts an AES key (hybrid encryption) which then encrypts the actual data
- Never implement your own AES mode — raw AES-ECB (which `pycryptodome`'s basic API exposes) has deterministic output that leaks patterns; use authenticated encryption (AES-GCM or Fernet)
- ECDSA over P-256 (secp256k1 for Bitcoin, P-256 for TLS/JWT) is preferred over RSA-2048 for new systems — smaller keys, same security level
- `secrets` module (stdlib) generates cryptographically secure random bytes for tokens and nonces; `random` module is not cryptographically secure

---

## What It Is

Cryptography is the art of keeping secrets in the presence of adversaries. In software, it is the set of mathematical operations that allow you to: encrypt data so only the holder of the right key can read it, sign data so anyone can verify it came from you, and hash data so you can verify it has not changed. Python has two worlds for this: the standard library's `hashlib` and `secrets`, which handle basic operations, and the `cryptography` package from the Python Cryptographic Authority, which provides the full range of modern cryptographic primitives with safe defaults.

The critical concept in applied cryptography is that algorithms are purpose-specific. Choosing the wrong algorithm does not just make the system slower or less convenient — it can make it appear secure while providing no protection at all. SHA-256 is an excellent algorithm for computing a checksum that verifies file integrity. SHA-256 is a terrible algorithm for storing passwords because it is designed to be fast, and a fast hash function allows an attacker to test billions of password guesses per second on modern hardware. bcrypt exists precisely because it is slow — it performs thousands of internal iterations, making each hash computation expensive and brute-force attacks impractical even with dedicated hardware.

The `cryptography` library is structured around the principle of making dangerous things hard and safe things easy. Its "hazardous materials" layer (`cryptography.hazmat.primitives`) provides direct access to raw cryptographic primitives for cases where you know exactly what you are doing. Its high-level layer provides pre-assembled recipes like Fernet that choose safe parameters for you, handle key generation, and bundle authentication with encryption so you cannot accidentally use unauthenticated encryption.

---

## How It Actually Works

Fernet provides symmetric authenticated encryption with a single function call:

```python
from cryptography.fernet import Fernet

# Key generation — store this securely, never hardcode
key = Fernet.generate_key()  # Returns a 32-byte URL-safe base64 encoded key
f = Fernet(key)

# Encrypt
ciphertext = f.encrypt(b"sensitive data here")
# Returns: b'gAAAAABh...' — includes IV, ciphertext, and HMAC

# Decrypt — raises InvalidToken if the ciphertext was tampered with
plaintext = f.decrypt(ciphertext)
```

Fernet uses AES-128-CBC for encryption and HMAC-SHA256 for authentication. The authentication component is critical: without it, an attacker who modifies the ciphertext produces silently corrupted plaintext rather than an error. Fernet's `InvalidToken` exception means the data was either modified or encrypted with a different key — you never silently process tampered data.

For password hashing, the `cryptography` library defers to `bcrypt` (via the `bcrypt` package) or `argon2-cffi`:

```python
import bcrypt

# Hashing a password — bcrypt generates a random salt automatically
password = b"user-supplied-password"
hashed = bcrypt.hashpw(password, bcrypt.gensalt(rounds=12))
# rounds=12 means 2^12 = 4096 iterations — adjust based on acceptable latency

# Verification
if bcrypt.checkpw(password, hashed):
    print("Password matches")
```

The `rounds` parameter controls the cost factor. As hardware becomes faster, the cost can be increased so that a legitimate login still takes ~100ms while brute-force remains infeasible. SHA-256 at one hundred million hashes per second on a GPU versus bcrypt at a few hundred hashes per second per GPU is the practical difference between cracking a leaked password database in hours versus centuries.

For digital signatures — proving that a message came from a specific key holder — ECDSA with P-256 is the modern standard:

```python
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

# Generate key pair (do this once, store private key securely)
private_key = ec.generate_private_key(ec.SECP256R1())
public_key = private_key.public_key()

# Sign
message = b"The exact bytes to be signed"
signature = private_key.sign(message, ec.ECDSA(hashes.SHA256()))

# Verify — raises InvalidSignature if tampered
public_key.verify(signature, message, ec.ECDSA(hashes.SHA256()))
```

Digital signatures are used in JWTs (RS256, ES256 algorithms), code signing, and any protocol where one party needs to prove to another that a message is authentic without sharing a symmetric secret.

The `secrets` module generates cryptographically secure random values for tokens, nonces, and session identifiers — it reads from the OS's cryptographically secure random number generator (`/dev/urandom` on Linux, `CryptGenRandom` on Windows):

```python
import secrets

token = secrets.token_hex(32)       # 64-character hex string — suitable for API keys
url_token = secrets.token_urlsafe(32)  # URL-safe base64 — suitable for password reset links
```

Never use `random.random()` or `random.randint()` for security tokens — the standard library `random` module is a pseudorandom number generator seeded from the system clock, which is predictable.

---

## How It Connects

Hashing and passwords is a foundational topic that this note expands on — especially the distinction between general-purpose hash functions and password-specific algorithms.

[[hashing-and-passwords|Hashing and Passwords]]

JWT signing uses ECDSA or RSA — the asymmetric signing operations described here are what make JWT verification work.

[[jwt|JWT]]

---

## Common Misconceptions

Misconception 1: "I'm encrypting sensitive data with AES, so it's secure."
Reality: "AES" alone does not specify a complete scheme. AES-ECB (Electronic Codebook mode) is deterministic — encrypting the same plaintext always produces the same ciphertext. An attacker who sees two identical ciphertext blocks knows the underlying plaintexts are identical, leaking structural information. AES-CBC requires an initialization vector. AES-GCM provides authenticated encryption. The `cryptography` library's Fernet bundles all correct choices; using raw AES mode selection exposes dangerous decisions to the developer.

Misconception 2: "I hash passwords with SHA-256 and add a salt, which is secure."
Reality: A salt prevents rainbow table attacks (precomputed hash dictionaries), but salted SHA-256 is still vulnerable to brute-force because SHA-256 is extremely fast. Purpose-built password hashing algorithms (bcrypt, Argon2, scrypt) are intentionally slow — they apply the hash function thousands to millions of times internally. Against a leaked hash database, an attacker can test salted-SHA-256 hashes orders of magnitude faster than bcrypt hashes. Use bcrypt or Argon2 for passwords.

Misconception 3: "I can use the same Fernet key for all users' encrypted data."
Reality: A single key means that anyone with access to the key can decrypt any user's data. Depending on the threat model and data sensitivity, consider per-user keys (the key is derived from the user's password using PBKDF2 or Argon2, so even the server cannot decrypt the data without the user's password). This is the approach used by end-to-end encrypted systems.

---

## Why It Matters in Practice

The OWASP category "Cryptographic Failures" (A02, formerly "Sensitive Data Exposure") covers the practical consequences of misusing cryptography: using MD5 or SHA-1 for password hashing (both have been rainbow-tabled extensively), using unauthenticated encryption (AES-CBC without a MAC), transmitting sensitive data over HTTP instead of HTTPS, and using weak random number generation for session tokens. These are not theoretical weaknesses — each has been exploited in real breaches.

The LinkedIn 2012 breach exposed 117 million user passwords, all hashed with unsalted SHA-1. These were cracked within hours of publication using precomputed rainbow tables. The bcrypt algorithm existed and was well-known in 2012 — the failure was using a general-purpose hash function where a password hash function was needed.

---

## Interview Angle

Common question forms:
- "What is the difference between hashing and encryption?"
- "Why shouldn't you use SHA-256 for password storage?"
- "What is Fernet and when would you use it?"
- "What is the difference between symmetric and asymmetric encryption?"

Answer frame:
A strong answer distinguishes hashing (one-way, for verification), encryption (two-way, for confidentiality), and signing (asymmetric, for authenticity). It explains the password hashing answer in terms of speed — SHA-256 is fast by design, bcrypt is slow by design. It explains Fernet as safe symmetric encryption that handles all the error-prone details (IV generation, authentication) automatically. It names the `cryptography` package as the correct Python library.

---

## Related Notes

- [[hashing-and-passwords|Hashing and Passwords]]
- [[jwt|JWT]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[pickle-security|Pickle Security Risks]]
- [[bandit|Bandit (Python Security Linter)]]
