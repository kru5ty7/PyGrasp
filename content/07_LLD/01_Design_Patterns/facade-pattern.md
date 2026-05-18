---
title: 09 - Facade Pattern
description: The Facade pattern provides a simplified interface to a complex subsystem, hiding the details of multiple interacting classes behind a single, easy-to-use entry point.
tags: [design-patterns, facade, structural, simplification, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Facade Pattern

> The Facade provides a simple interface to a complex subsystem, so that clients interact with one object instead of managing multiple interconnected components.

---

## Quick Reference

**Core idea:**
- A facade wraps a complex subsystem behind a **simple, unified interface**
- Clients call a few facade methods instead of orchestrating many subsystem objects
- The facade does not replace the subsystem - power users can still access subsystem classes directly
- Unlike Adapter (which translates interfaces), Facade **simplifies** a complex interface into an easier one
- Common in Python: `requests.get()` (facade over HTTP/connection/SSL), `logging.basicConfig()`, `pathlib.Path`

**Tricky points:**
- A facade that grows too large becomes a God class - split it or keep subsystem access available
- Facade is not an abstraction layer for swapping implementations - it is a convenience layer for reducing complexity
- Do not force all access through the facade if some clients need fine-grained subsystem control

---

## What It Is

Think of a hotel concierge. You want to plan an evening out - dinner, theater tickets, and a car service. Without a concierge, you call three different businesses, coordinate timing, manage reservations, and handle cancellations independently. With a concierge, you say "I want dinner and a show tonight" and they handle everything. The concierge is the facade. The restaurants, theaters, and car services are the subsystem. You interact with one person instead of three.

The Facade pattern applies this to code. A video conversion system might involve a `VideoCodec`, an `AudioCodec`, a `BitrateCalculator`, a `Muxer`, and a `FileWriter`. Instead of making every caller understand all five classes and their interactions, you create a `VideoConverter` facade with a single `convert(input, output, format)` method. The facade orchestrates the subsystem internally.

Python's standard library is full of facades. `requests.get(url)` hides connection pooling, SSL certificates, redirects, content decoding, and session management. `logging.basicConfig()` configures handlers, formatters, and loggers in one call. These facades do not prevent you from accessing the underlying classes when you need fine-grained control.

---

## How It Actually Works

A facade stores references to subsystem objects (or creates them internally) and provides high-level methods that orchestrate subsystem operations in the correct order with the correct parameters. The facade adds no new functionality - it only simplifies existing functionality.

```python
class VideoCodec:
    def extract(self, file: str) -> bytes:
        print(f"Extracting video from {file}")
        return b"video_data"

    def encode(self, data: bytes, format: str) -> bytes:
        print(f"Encoding video to {format}")
        return b"encoded_video"

class AudioCodec:
    def extract(self, file: str) -> bytes:
        print(f"Extracting audio from {file}")
        return b"audio_data"

    def encode(self, data: bytes, bitrate: int) -> bytes:
        print(f"Encoding audio at {bitrate}kbps")
        return b"encoded_audio"

class Muxer:
    def mux(self, video: bytes, audio: bytes, format: str) -> bytes:
        print(f"Muxing video+audio into {format}")
        return b"final_output"

class FileWriter:
    def write(self, data: bytes, path: str) -> None:
        print(f"Writing {len(data)} bytes to {path}")


# Facade: one method instead of coordinating four classes
class VideoConverter:
    """Simple interface for video conversion.
    
    Power users can still use VideoCodec, AudioCodec, etc. directly.
    """
    def __init__(self):
        self._video = VideoCodec()
        self._audio = AudioCodec()
        self._muxer = Muxer()
        self._writer = FileWriter()

    def convert(self, input_file: str, output_file: str,
                format: str = "mp4", audio_bitrate: int = 128) -> None:
        """Convert a video file. Handles all subsystem coordination."""
        video_data = self._video.extract(input_file)
        audio_data = self._audio.extract(input_file)

        encoded_video = self._video.encode(video_data, format)
        encoded_audio = self._audio.encode(audio_data, audio_bitrate)

        final = self._muxer.mux(encoded_video, encoded_audio, format)
        self._writer.write(final, output_file)
        print(f"Conversion complete: {output_file}")


# Client code is simple
converter = VideoConverter()
converter.convert("input.avi", "output.mp4")


# Real-world example: email sending facade
class SMTPConnection:
    def connect(self, host: str, port: int) -> None:
        print(f"Connected to {host}:{port}")
    def authenticate(self, user: str, password: str) -> None:
        print("Authenticated")
    def send_raw(self, from_addr: str, to_addr: str, data: str) -> None:
        print(f"Sent from {from_addr} to {to_addr}")
    def disconnect(self) -> None:
        print("Disconnected")

class MIMEBuilder:
    def build(self, subject: str, body: str, from_addr: str, to_addr: str) -> str:
        return f"Subject: {subject}\nFrom: {from_addr}\nTo: {to_addr}\n\n{body}"

class EmailFacade:
    def __init__(self, host: str, port: int, user: str, password: str):
        self._host = host
        self._port = port
        self._user = user
        self._password = password

    def send_email(self, to: str, subject: str, body: str) -> None:
        conn = SMTPConnection()
        mime = MIMEBuilder()
        conn.connect(self._host, self._port)
        conn.authenticate(self._user, self._password)
        message = mime.build(subject, body, self._user, to)
        conn.send_raw(self._user, to, message)
        conn.disconnect()

email = EmailFacade("smtp.company.com", 587, "noreply@co.com", "pass")
email.send_email("user@example.com", "Hello", "Welcome aboard!")
```

---

## How It Connects

Facade simplifies complex subsystems. Adapter translates incompatible interfaces. Both are structural patterns but solve different problems.

[[adapter-pattern|Adapter Pattern]]

[[design-patterns-overview|Design Patterns Overview]]

Facades often appear in SRP-compliant architectures: the subsystem classes each have one responsibility, and the facade orchestrates them for common use cases.

[[srp|Single Responsibility Principle]]

---

## Common Misconceptions

Misconception 1: "A Facade should be the only way to access the subsystem."
Reality: A Facade is an additional convenience, not a restriction. Power users should still be able to use subsystem classes directly when they need fine-grained control. The Facade handles the 80% case; the subsystem handles the 20%.

Misconception 2: "Facade and Adapter are the same thing."
Reality: Adapter changes an interface to match what a client expects. Facade simplifies a complex interface into an easier one. Adapter translates; Facade reduces complexity.

---

## Why It Matters in Practice

Well-designed APIs provide facade-level entry points for common tasks and low-level access for advanced use. `requests.get()` is a facade; `requests.Session()` with custom adapters is the subsystem. `logging.basicConfig()` is a facade; manually configuring handlers and formatters is the subsystem. Designing your own libraries with this dual-level access makes them approachable for beginners and powerful for experts.

---

## Interview Angle

Common question forms:
- "What is the Facade pattern?"
- "How is Facade different from Adapter?"
- "Give an example of a Facade in a Python library."

Answer frame:
Define Facade as a simplified entry point to a complex subsystem. Contrast with Adapter (simplification vs translation). Give the `requests.get()` example. Explain that facades do not replace subsystem access - they complement it.

---

## Related Notes

- [[adapter-pattern|Adapter Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[srp|Single Responsibility Principle]]
