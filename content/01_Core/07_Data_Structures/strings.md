---
title: 05 - Strings
description: "Python strings are immutable sequences of Unicode code points using PEP 393 flexible representation — selecting one of three internal encodings based on the widest character, with interning for efficiency."
tags: [strings, unicode, pep-393, flexible-string, interning, encoding, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Strings

> Python strings are immutable sequences of Unicode code points — not bytes — and CPython automatically chooses the most compact internal encoding for each string so that simple ASCII text never wastes memory on multi-byte characters.

---

## Quick Reference

**Core idea:**
- `str` objects store Unicode code points (not UTF-8 bytes); internal encoding chosen per-string by PEP 393
- Three compact representations: Latin-1 (1 byte/char, U+0000–U+00FF), UCS-2 (2 bytes/char, up to U+FFFF), UCS-4 (4 bytes/char, full Unicode)
- Short strings and identifier-shaped strings are interned automatically; `sys.intern(s)` forces interning for any string
- `+` concatenation in a loop is O(n²) because each `+` creates a new string object — use `"".join(parts)`
- `str.encode(encoding)` → `bytes`; `bytes.decode(encoding)` → `str`; codec must match data

**Tricky points:**
- `len("😀")` returns 1 (one code point), not 4 (the UTF-8 byte count) — `len` counts code points, not bytes
- `"abc" is "abc"` may be `True` (interned), but never rely on `is` for string equality — use `==`
- String slicing is O(k) — a new string object is created for every slice
- `str.find()` returns -1 on failure; `str.index()` raises `ValueError` — they are not interchangeable
- f-string expressions are evaluated at runtime, not at definition — `f"{x!r}"` calls `repr(x)` when the line executes

---

## What It Is

Imagine a book printed in different languages. A book of pure English needs only 26 letters and some punctuation — you could represent each character in a single byte. A book that mixes English with accented French or Spanish characters needs a slightly wider alphabet — a byte and a bit or two, encoded cleverly. A book mixing English with Chinese ideographs needs multiple bytes per character. A librarian who wants to store all these books efficiently would choose the paper size based on the widest character in each specific book, not on the worst-case across all possible books.

Python does exactly this. Each string object chooses its internal storage width based on the widest code point it contains. A string containing only ASCII characters (U+0000–U+007F) or Latin-1 characters (U+0000–U+00FF) stores one byte per character. A string containing a character up to U+FFFF uses two bytes per character. A string that contains even a single emoji or rare CJK character uses four bytes per character. This is PEP 393's flexible string representation, and it means that the vast majority of Python strings — which are pure ASCII identifiers, log messages, file paths — pay the minimum one-byte-per-character price.

Strings in Python are not byte sequences. When you type `"hello"`, you get a sequence of five Unicode code points, not five bytes. The distinction matters because one code point does not always equal one byte. The string `"café"` has four code points and four characters in `len()`, but its UTF-8 encoding produces five bytes. This separation between the text layer (strings, code points) and the binary layer (bytes, encodings) is what allows Python to handle every human language correctly without the encoding-corruption bugs that plague languages which conflate the two.

---

## How It Actually Works

PEP 393 (CPython 3.3+) defines `PyUnicodeObject` with a flexible layout controlled by the `interned` and `kind` fields packed into a state bitfield. The `kind` field indicates which of the four compact encodings is in use: `PyUnicode_1BYTE_KIND` (Latin-1, one byte per character), `PyUnicode_2BYTE_KIND` (UCS-2, two bytes), or `PyUnicode_4BYTE_KIND` (UCS-4, four bytes). There is also a "compact ASCII" subtype that is slightly smaller than full Latin-1 for pure-ASCII strings.

```python
import sys
s1 = "hello"       # compact ASCII, 1 byte/char
s2 = "héllo"       # Latin-1, still 1 byte/char
s3 = "h中llo"  # contains CJK, UCS-2, 2 bytes/char
s4 = "h\U0001F600" # contains emoji (> U+FFFF), UCS-4, 4 bytes/char
print(sys.getsizeof(s1))  # ~54 bytes
print(sys.getsizeof(s4))  # ~80 bytes — larger due to UCS-4
```

String interning is implemented by storing a reference to the interned string in a global dictionary (`interned` in `unicodeobject.c`). When a string is interned, the global dict holds a strong reference, preventing the string from being garbage-collected. CPython automatically interns strings that look like Python identifiers (no spaces, only alphanumeric and `_`) when they appear as string literals or are created by operations like attribute lookup. `sys.intern(s)` exposes this mechanism for application code. Two interned strings can be compared with `is` because they are guaranteed to be the same object — but only because interning was explicitly confirmed, never assumed.

The O(n²) concatenation trap arises because Python strings are immutable. Each `result = result + new_part` allocates a new string of length `len(result) + len(new_part)` and copies both. Over n iterations with parts of average length k, the total bytes copied is `0 + k + 2k + 3k + ... + nk = k*n*(n+1)/2` — O(n²). `"".join(parts)` avoids this by first computing the total length of all parts in a single pass, then allocating one string of exactly that size and filling it.

---

## How It Connects

The relationship between `str` and `bytes` is the encode/decode boundary. Every time Python crosses that boundary, a codec is applied. Mismatches between the codec used to encode and the one used to decode produce `UnicodeDecodeError` — one of the most common Python errors in I/O-heavy code.

[[bytes-and-bytearray|Bytes and Bytearray]]

String interning shares its mechanism with the small integer cache and other object-level caching strategies that CPython uses to avoid redundant allocations. The interning dictionary is one of CPython's few globally shared caches.

[[interning|Interning]]

Strings implement the sequence protocol — they support indexing, slicing, iteration, and `len()`. This protocol is the same one that lists and tuples implement, and it is defined through Python's data model.

[[python-data-model|Python Data Model]]

---

## Common Misconceptions

Misconception 1: "`len(s)` returns the number of bytes in the string."
Reality: `len(s)` returns the number of Unicode code points (characters). For strings containing only ASCII, code points and bytes happen to coincide. For strings with multi-byte characters (emoji, CJK), `len(s)` will be smaller than `len(s.encode('utf-8'))`.

Misconception 2: "String interning means all equal strings are the same object."
Reality: Only explicitly interned strings or strings that CPython interns automatically (short identifier-shaped literals) are guaranteed to share identity. `"hello world" is "hello world"` may be `True` at module level (constant folding) but should never be assumed. Always use `==` for equality.

Misconception 3: "Python 3 strings are UTF-8 internally."
Reality: CPython strings use Latin-1, UCS-2, or UCS-4 internally based on the widest character, not UTF-8. UTF-8 encoding is used when crossing the text/binary boundary via `str.encode('utf-8')`, but the internal representation is a fixed-width format for O(1) index access.

---

## Why It Matters in Practice

The encode/decode boundary is where the vast majority of `UnicodeDecodeError` and `UnicodeEncodeError` exceptions originate. Understanding that `str` is code points and `bytes` is raw bytes — and that a codec is always required to convert between them — makes these errors predictable and fixable rather than mysterious. The rule is: decode bytes to str as early as possible when reading input, encode str to bytes as late as possible when writing output, and name the codec explicitly every time.

The O(n²) join pattern affects any code that builds strings in a loop. Log formatters, template renderers, report generators, and serializers are all potential victims. The fix is always to collect parts into a list and call `"".join()` once. This is idiomatic Python and is the pattern the standard library itself uses internally.

---

## Interview Angle

Common question forms:
- "Why is string concatenation in a loop slow in Python?"
- "What is the difference between `str` and `bytes`?"
- "How does Python store strings internally?"

Answer frame:
Strings are immutable sequences of Unicode code points. Each `+` creates a new object and copies both operands, making loop concatenation O(n²); `join()` does one allocation and one fill, O(n). Internally, PEP 393 selects Latin-1/UCS-2/UCS-4 based on the widest character, giving O(1) random access. `bytes` stores raw 0–255 integers; `str.encode()` and `bytes.decode()` cross the boundary using a named codec.

---

## Related Notes

- [[bytes-and-bytearray|Bytes and Bytearray]]
- [[interning|Interning]]
- [[python-data-model|Python Data Model]]
- [[mutability|Mutability]]
- [[everything-is-an-object|Everything Is an Object]]
