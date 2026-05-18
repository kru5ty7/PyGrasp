---
title: 06 - Insecure Deserialization
description: "Insecure deserialization occurs when untrusted data is passed to a deserializer that can reconstruct arbitrary objects or execute code during the deserialization process  -  Python's pickle module is the canonical example."
tags: [deserialization, pickle, rce, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Insecure Deserialization

> Deserializing untrusted data with Python's pickle module is equivalent to executing arbitrary code  -  the attacker controls what Python runs, not just what data is loaded.

---

## Quick Reference

**Core idea:**
- Serialization converts an object to bytes; deserialization reconstructs an object from bytes
- Insecure deserialization: deserializing data from an untrusted source using a format that supports arbitrary code execution during reconstruction
- Python's `pickle` executes arbitrary Python code during `pickle.loads()`  -  this is by design, not a bug
- Safe alternatives for untrusted data: JSON, MessagePack, Protocol Buffers  -  formats that cannot encode executable behavior
- When pickle is necessary (ML model persistence), sign the payload with HMAC and verify the signature before loading

**Tricky points:**
- The vulnerability is in `pickle.loads()` of attacker-controlled bytes, not in pickling your own objects
- `__reduce__` is the pickle protocol hook that enables code execution  -  any class can define it to control what happens during unpickling
- The exploit works even if the server never calls any function explicitly  -  the code runs implicitly when the serialized bytes are loaded
- JSON is safe because it only encodes strings, numbers, booleans, arrays, and objects  -  it has no mechanism to call functions
- `shelve`, `marshal`, `jsonpickle`, and `dill` all share pickle's code execution risk in various ways

---

## What It Is

Imagine mailing a box to a warehouse with instructions saying "when you open this box, do exactly what the note inside says." A trusted colleague mailing supplies is fine  -  the note probably says "put this on shelf 7." But if an attacker intercepts the mail system and swaps the box, their note might say "open the back door and let me in." The warehouse worker does not question the instructions  -  they just follow them. That is insecure deserialization: the deserializer follows embedded instructions without verifying they are safe.

Python's `pickle` module is exactly this warehouse. When you call `pickle.loads(data)`, Python does not just reconstruct data  -  it executes a miniature program encoded in the pickle byte stream. This is intentional. Pickle was designed to reconstruct arbitrary Python objects, including objects whose classes define custom behavior during construction. The `__reduce__` method lets any Python class specify exactly what happens when it is unpickled: "to reconstruct me, call this function with these arguments." Normally `__reduce__` returns something like `(MyClass, (arg1, arg2))`. An attacker's pickle payload can return `(os.system, ("rm -rf /",))`.

The insecurity is not a bug in pickle  -  it is the nature of pickle. The module's own documentation warns: "The pickle module is not secure. Only unpickle data you trust." The problem is that "only unpickle data you trust" is much harder to guarantee than it sounds. User-uploaded files, data from external APIs, values from Redis caches (if the Redis instance is shared), and JWT or cookie payloads that use pickle encoding are all potential sources of untrusted pickle data that have appeared in real production Python applications.

---

## How It Actually Works

The `__reduce__` exploit is straightforward to understand. A malicious class defines its pickle representation as a function call to a dangerous built-in:

```python
import pickle
import os

class Exploit:
    def __reduce__(self):
        return (os.system, ("id > /tmp/pwned",))

# Attacker generates this payload
payload = pickle.dumps(Exploit())
# payload is a byte string that encodes "call os.system('id > /tmp/pwned')"

# On the victim server:
pickle.loads(payload)
# Python calls os.system("id > /tmp/pwned")  -  the OS command executes
```

The bytes in `payload` encode an instruction set. When `pickle.loads()` processes them, it reaches the instruction "call `os.system` with the argument `'id > /tmp/pwned'`" and executes it. No code in the victim application's source called `os.system`  -  it was called by the pickle interpreter following the attacker's embedded instructions.

In practice, attackers use `subprocess.Popen` or the `exec` built-in to get a reverse shell rather than a simple command. A common real-world attack vector is a Python web application that stores session data in a Redis cache or a signed cookie, using pickle to serialize the session object. If the attacker can modify the cached or cookie data  -  even a signed cookie whose signature they have forged or bypassed  -  they can inject a malicious pickle payload.

The safe serialization alternatives work because they separate data from behavior. JSON can represent `{"action": "login", "user_id": 42}` but has no syntax for "call this function." An attacker-controlled JSON string that the application deserializes with `json.loads()` can only result in Python dicts, lists, strings, numbers, and booleans  -  none of which execute code on construction. MessagePack and Protocol Buffers have the same property.

When pickle genuinely cannot be avoided  -  loading a trained scikit-learn model, for example  -  the defense is to sign the pickle bytes with HMAC before storing them and verify the signature before loading:

```python
import pickle
import hmac
import hashlib

SECRET_KEY = b"your-secret-key"

def safe_dump(obj) -> bytes:
    data = pickle.dumps(obj)
    sig = hmac.new(SECRET_KEY, data, hashlib.sha256).hexdigest()
    return sig.encode() + b":" + data

def safe_load(signed_data: bytes):
    sig_hex, data = signed_data.split(b":", 1)
    expected = hmac.new(SECRET_KEY, data, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig_hex.decode(), expected):
        raise ValueError("Pickle signature invalid")
    return pickle.loads(data)
```

This ensures that even if an attacker can write to the storage location, they cannot produce a valid signature without the secret key  -  so the forged payload will be rejected before `pickle.loads` executes.

---

## How It Connects

Insecure deserialization is OWASP A08 Software and Data Integrity Failures  -  understanding the broader category frames where pickle security fits.

[[owasp-top-10|OWASP Top 10]]

The pickle-specific security risks are deep enough to warrant a dedicated note, covering the `__reduce__` mechanism in full detail.

[[pickle-security|Pickle Security Risks]]

---

## Common Misconceptions

Misconception 1: "I use pickle to load a model file that I control, so there's no risk."
Reality: The risk is about the attack surface, not the current use case. If the file path or storage location for the model is ever influenced by user input, if the model file is served from a shared storage system that other parties can write to, or if the application accepts model files as uploads, the "I control the file" assumption can be violated. Additionally, supply chain attacks against ML model repositories have demonstrated that "I downloaded this from a trusted source" is also not always safe.

Misconception 2: "I can validate the pickle bytes before loading them to check for dangerous patterns."
Reality: Pickle is a bytecode format, and analyzing it for dangerous patterns before executing it is equivalent to solving the halting problem in the general case. Attackers use obfuscation, encoding tricks, and multi-stage payloads to evade naive pattern-matching on pickle bytes. The only safe approach is to not call `pickle.loads()` on untrusted data  -  validation of pickle bytes is not a reliable defense.

Misconception 3: "JSON is vulnerable to the same issue because attackers can put malicious values in it."
Reality: JSON's data model fundamentally cannot encode function calls or class instantiation. `json.loads('{"__class__": "os.system", "args": "rm -rf /"}')` returns a Python dictionary  -  it does not call `os.system`. The library would need to explicitly do something dangerous with that dictionary's contents. JSON deserialization only produces passive data structures; pickle deserialization executes a program.

---

## Why It Matters in Practice

The Python machine learning ecosystem relies heavily on pickle for model persistence. scikit-learn's `joblib.dump()`, PyTorch's `torch.save()`, and many other ML frameworks use pickle as the underlying serialization format. This creates a widespread pattern in Python data science and ML engineering where pickle files are treated as data artifacts and loaded without suspicion. When these models are shared publicly on platforms like Hugging Face, loaded from user uploads, or pulled from external sources, pickle-based RCE becomes a genuine threat to production ML systems.

Beyond ML, any Python application that stores session state in a serialized format  -  common in older Flask and Django applications using signed cookies or Redis sessions with pickle encoding  -  has historically been vulnerable to deserialization attacks. Flask's secret key protects session cookies from forgery, but an application that migrated from pickle to JSON-based sessions and still has old pickle sessions in its Redis cache, or an application that shares a Redis instance between services with different trust levels, can expose pickle deserialization to attacker-controlled data.

---

## Interview Angle

Common question forms:
- "Why is Python's pickle module dangerous?"
- "What is insecure deserialization?"
- "How would you safely persist a machine learning model?"

Answer frame:
A strong answer explains that pickle executes code during deserialization by design, not by accident  -  specifically via `__reduce__`. It mentions `os.system` or `subprocess` as what an attacker's `__reduce__` would call. It distinguishes pickle from JSON by explaining that JSON only encodes data, not behavior. For the ML model question, it names the HMAC signing pattern and acknowledges that for truly untrusted models, sandboxing or format conversion (ONNX, SafeTensors) is the correct approach.

---

## Related Notes

- [[owasp-top-10|OWASP Top 10]]
- [[pickle-security|Pickle Security Risks]]
- [[sql-injection|SQL Injection]]
- [[bandit|Bandit (Python Security Linter)]]
