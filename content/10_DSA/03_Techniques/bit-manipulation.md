---
title: 42 - Bit Manipulation
description: Direct operation on the binary representation of integers using bitwise operators to achieve constant-time tricks that would otherwise require arithmetic or data structures.
tags: [dsa, layer-10, bits, bitwise-operators]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Bit Manipulation

> Bit manipulation operates directly on the binary representation of integers to perform checks, masks, and transformations in O(1) time - developers at companies where performance-critical code matters must know the core tricks because they appear in systems programming, cryptography, competitive programming, and interview problems.

---

## Quick Reference

**Core idea:**
- Operators: `&` (AND), `|` (OR), `^` (XOR), `~` (NOT/complement), `<<` (left shift), `>>` (right shift)
- Check if bit k is set: `n & (1 << k)`
- Set bit k: `n | (1 << k)`
- Clear bit k: `n & ~(1 << k)`
- Toggle bit k: `n ^ (1 << k)`
- Check power of two: `n > 0 and (n & (n - 1)) == 0`
- Clear lowest set bit: `n & (n - 1)` - removes the rightmost 1 bit
- Isolate lowest set bit: `n & (-n)` - keeps only the rightmost 1 bit
- XOR trick: `x ^ x == 0`, so XOR of a paired array leaves the unique element

**Tricky points:**
- Python integers have arbitrary precision - no integer overflow, but no fixed bit-width either
- When emulating 32-bit unsigned arithmetic, mask results with `& 0xFFFFFFFF`
- `~n` in Python is `-(n + 1)`, not the unsigned complement - a common source of confusion from C backgrounds
- Left shift by k is equivalent to multiplying by 2^k; right shift by k is equivalent to floor-dividing by 2^k
- XOR is its own inverse: `a ^ b ^ b == a`, useful for swapping without a temp variable

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Any single bitwise operation | O(1) | O(1) |
| Counting set bits (naive loop) | O(log n) | O(1) |
| Counting set bits (Brian Kernighan's trick) | O(number of set bits) | O(1) |
| Finding single unpaired element via XOR | O(n) | O(1) |

---

## What It Is

Every integer in a computer is stored as a sequence of binary digits - bits that are either 0 or 1. Bit manipulation treats these individual digits as directly addressable switches rather than as an opaque numeric value. Think of a row of light switches on a panel: each switch is either on (1) or off (0). The AND operation (`&`) turns a switch off if either panel has it off; it models "both must be on." The OR operation (`|`) turns a switch on if either panel has it on; it models "at least one must be on." The XOR operation (`^`) turns a switch on if exactly one panel has it on; it models "they must differ." These are not abstract mathematical operations - they map directly to logic gates in hardware and execute in a single clock cycle.

The power of bit manipulation comes from the ability to encode and test multiple boolean conditions simultaneously in a single integer. Rather than maintaining an array of 32 boolean flags, you can pack them into a single 32-bit integer and test any flag with a single AND operation. This is how file permissions work in Unix: the permission bits `rwxr-xr--` are stored as a 9-bit integer, and checking whether the owner has write permission is a single `&` with the appropriate mask. It is also how many game AI engines represent board states - an entire chessboard can be encoded in a few 64-bit integers (bitboards), and all moves can be computed as bitwise operations rather than loops over arrays.

XOR has a remarkable algebraic property that makes it disproportionately useful. Since `x ^ x == 0` for any value x, XOR-ing a value with itself cancels it out. And since `x ^ 0 == x`, XOR-ing with zero is a no-op. This means that if you XOR together all elements in an array where every element appears exactly twice except for one, all the paired elements cancel out and only the unique element remains. No extra memory, no counting, no sorting - just one linear pass with a running XOR accumulator. This is the kind of O(n) time, O(1) space insight that bit manipulation enables.

---

## How It Actually Works

The core bit tricks are mechanical and should be memorised as patterns. Each has an intuitive derivation from the behavior of AND, OR, XOR, and shifts, but in practice they are applied from memory during implementation.

Python's arbitrary-precision integers mean you never deal with overflow, but they also mean you must be explicit when you want fixed-width behavior. If you are implementing a hash function or simulating a 32-bit processor, mask every result with `& 0xFFFFFFFF` to keep only the low 32 bits. When Python's `~` operator gives unexpected negative results (because Python integers have no fixed sign bit), substitute `n ^ mask` where mask is all ones for the bit width you care about.

```python
# =========================================================
# Core Bit Tricks Reference
# =========================================================

def check_bit(n: int, k: int) -> bool:
    """True if bit k (0-indexed from LSB) is set."""
    return bool(n & (1 << k))

def set_bit(n: int, k: int) -> int:
    """Return n with bit k set to 1."""
    return n | (1 << k)

def clear_bit(n: int, k: int) -> int:
    """Return n with bit k cleared to 0."""
    return n & ~(1 << k)

def toggle_bit(n: int, k: int) -> int:
    """Return n with bit k flipped."""
    return n ^ (1 << k)

def is_power_of_two(n: int) -> bool:
    """True if n is a positive power of two."""
    return n > 0 and (n & (n - 1)) == 0

def clear_lowest_set_bit(n: int) -> int:
    """Remove the rightmost 1 bit from n."""
    return n & (n - 1)

def isolate_lowest_set_bit(n: int) -> int:
    """Return an integer with only the rightmost 1 bit of n set."""
    return n & (-n)

def count_set_bits(n: int) -> int:
    """Count 1 bits using Brian Kernighan's trick - O(number of set bits)."""
    count = 0
    while n:
        n = clear_lowest_set_bit(n)   # each iteration removes one set bit
        count += 1
    return count


# =========================================================
# Classic Interview Problems
# =========================================================

def find_unique(nums: list[int]) -> int:
    """Find the single element in an array where all others appear twice.
    XOR cancels paired elements; only the unique one remains."""
    result = 0
    for num in nums:
        result ^= num
    return result

def swap_without_temp(a: int, b: int) -> tuple[int, int]:
    """Swap two integers using XOR - no temporary variable needed."""
    a ^= b
    b ^= a   # b = original a
    a ^= b   # a = original b
    return a, b

def get_subsets_bitmask(nums: list) -> list:
    """Generate all 2^n subsets using bit masks to select elements."""
    n = len(nums)
    result = []
    for mask in range(1 << n):     # iterate over all 2^n bitmasks
        subset = []
        for i in range(n):
            if mask & (1 << i):    # if bit i is set, include nums[i]
                subset.append(nums[i])
        result.append(subset)
    return result

# 32-bit unsigned arithmetic emulation
def add_no_overflow(a: int, b: int) -> int:
    """Add two integers, masking to 32-bit unsigned range."""
    MASK = 0xFFFFFFFF
    while b:
        carry = a & b
        a = (a ^ b) & MASK
        b = (carry << 1) & MASK
    return a


# Demonstrations
print(check_bit(0b1010, 1))     # True (bit 1 = 1)
print(check_bit(0b1010, 0))     # False (bit 0 = 0)
print(bin(set_bit(0b1010, 2)))  # 0b1110
print(is_power_of_two(64))      # True
print(is_power_of_two(60))      # False
print(count_set_bits(0b1011))   # 3
print(find_unique([2, 3, 2, 4, 4]))  # 3
print(get_subsets_bitmask([1, 2, 3]))  # 8 subsets
```

---

## How It Connects

Bit manipulation connects most directly to problems involving sets, flags, and combinatorics. Generating all 2^n subsets via bitmask enumeration is a cleaner alternative to backtracking when n is small (typically n ≤ 20). Many dynamic programming problems on subsets use bitmask DP, where the state is a bitmask representing which elements have been used. This technique - encoding a subset as an integer - is a powerful bridge between bit manipulation and dynamic programming.

In graph algorithms, bitboards (integers encoding adjacency or reachability) are used in chess engines and game solvers to represent board states and compute moves in single operations. Understanding bits makes those techniques accessible.

[[dynamic-programming|Dynamic Programming]]
[[backtracking|Backtracking]]
[[arrays|Arrays]]

---

## Common Misconceptions

Misconception 1: Python's `~n` gives the bitwise complement, turning all 0s to 1s and vice versa.
Reality: In Python, `~n` is defined as `-(n + 1)` due to Python's two's complement representation of arbitrary-precision integers. There is no fixed upper bit to flip. `~5` is `-6`, not `0b...11111010` as it would be in C for an 8-bit integer. When you need to flip bits within a specific width (say, 8 bits), use `n ^ 0xFF` rather than `~n`.

Misconception 2: Bit manipulation tricks are only useful for competitive programming and embedded systems.
Reality: Bit manipulation appears in real-world Python: `enum.Flag` uses bitmask composition for flag sets, Django's permission system historically used bitmask fields, Redis's bitfield commands use bit operations for compact storage, and Python's `hash()` function and many hash table implementations use bitwise operations for index computation. The XOR-based unique-element trick has been used in production code where memory constraints are tight.

---

## Why It Matters in Practice

Bit manipulation is a marker of low-level understanding. Developers who know it can implement compact set representations (a 64-bit integer replacing a set of 64 booleans), verify alignment and power-of-two conditions in O(1), and solve certain problems with O(1) space where other techniques require O(n). In systems programming - writing parsers, encoding formats, network protocol handlers - bit manipulation is not optional; it is the primary tool.

In interviews at FAANG-level companies, bit manipulation problems appear regularly at medium and hard difficulty. The XOR-unique trick, the power-of-two check, and bitmask subset enumeration each appear as core techniques or as sub-steps in larger problems. Knowing the tricks fluently enough to apply them without derivation during an interview requires the kind of pattern memorisation that only comes from practice.

---

## Interview Angle

Common question forms:
- "Find the element that appears once when all others appear twice."
- "Count the number of 1 bits in an integer."
- "Determine if an integer is a power of two."
- "Generate all subsets of a set."

Answer frame:
State which bit property or trick applies. Write the operation explicitly (do not assume the interviewer knows it). Trace one numeric example in binary to verify. Confirm O(1) time and O(1) space. For the XOR-unique trick, explain why `x ^ x == 0` makes it work. Mention the Python-specific caveat about `~` if it is relevant.

---

## Related Notes

- [[arrays|Arrays]]
- [[dynamic-programming|Dynamic Programming]]
- [[backtracking|Backtracking]]
- [[hash-tables|Hash Tables]]
