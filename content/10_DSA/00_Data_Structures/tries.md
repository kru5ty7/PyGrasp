---
title: 14 - Tries
description: A trie (prefix tree) stores strings character-by-character in a tree, enabling O(L) insert, search, and prefix search independent of how many strings are stored.
tags: [dsa, layer-10, trie, prefix-tree]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Tries

> A trie exploits the shared prefix structure of strings to make search and autocomplete operations cost proportional to the length of the query, not the size of the dictionary.

---

## Quick Reference

**Core idea:**
- Each node represents a single character; paths from root to marked nodes spell out stored strings
- Insert, search, and prefix-check are all O(L) where L is the string length — independent of the number of stored strings
- An end-of-word marker at a node distinguishes a complete word from a mere prefix
- Standard implementation: each node holds a dict (or array of 26) mapping characters to child nodes
- Applications: autocomplete, spell checking, IP routing tables, prefix matching in search engines

**Tricky points:**
- O(L) search is only better than a hash table's O(L) hash computation when you also need prefix operations — for pure lookup, a hash table is simpler
- The end-of-word marker is critical: without it, "app" and "apple" become indistinguishable (both have paths in the trie)
- Deletion requires checking whether the deleted node is a prefix of another word before removing nodes
- Space cost is high: a node with 26 children (standard English alphabet) requires up to 26 pointers even if only one child exists
- Compressed tries (radix trees, Patricia tries) merge single-child chains into one node to save space

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Insert word of length L | O(L) | O(L) |
| Search word of length L | O(L) | O(L) |
| Prefix check (starts with) | O(L) | O(L) |
| Prefix search (return all matches) | O(L + k) | O(L + k) |
| Delete word of length L | O(L) | O(L) |

Space complexity: O(total characters × alphabet size) — can be large.

---

## What It Is

Imagine a large wall of filing cabinets at a library's front desk, each drawer labelled with a single letter. To find a book, you open drawer 'P', inside which is another set of mini-drawers — one for each second letter. You open 'Y', which leads to another set for the third letter. You open 'T', then 'H', then 'O', then 'N', at which point a tag says "word ends here — Python section is on shelf 42." To find the book for "Pythagoras," you follow the same P-Y-T-H path and then diverge at 'A'. The shared path P-Y-T-H was traversed only once, serving both words.

This shared-prefix structure is the trie's key insight. In a dictionary of English words, thousands of words start with "pre" — prehistoric, preliminary, prelude, and so on. A trie stores the 'p', 'r', 'e' path exactly once and branches at the fourth letter. A hash table would store "prehistoric" as an independent entry with no knowledge that it shares a prefix with "preliminary." When you want to find all words starting with "pre," the hash table must scan all entries (O(n)); the trie walks to the 'e' node and collects all descendants (O(prefix_length + matches)).

Autocomplete systems — from search engine suggestions to IDE code completion — are the canonical use case. When a user types "py", the system needs all stored words starting with "py" returned quickly. In a trie, this means descending three levels (root → 'p' → 'y'), arriving at the node for prefix "py," and collecting all words reachable from there. The cost depends on the prefix length and the number of matches, not the total vocabulary size. For a vocabulary of one million words, a hash-based approach requires filtering all one million entries; a trie requires only as much work as the words that share the prefix.

---

## How It Actually Works

Each trie node maintains a collection of child pointers, one for each character that can follow the current prefix. The simplest representation is a dict mapping each character to its child node. The end-of-word flag is a boolean field on the node that marks whether the path from root to this node spells out a complete stored word.

Insertion traverses from the root, creating new nodes for characters that do not yet have a child, and sets the end-of-word flag on the final node. Search traverses the same path and returns True only if it reaches the final character and that node has the end-of-word flag set. Prefix check is simpler: traverse and return True if you successfully reach the end of the prefix string, regardless of the end-of-word flag. Prefix-based collection recursively gathers all words reachable from the prefix node.

```python
class TrieNode:
    def __init__(self):
        self.children = {}       # char -> TrieNode
        self.is_end_of_word = False


class Trie:
    def __init__(self):
        self.root = TrieNode()

    def insert(self, word):
        """Insert word into trie — O(L)."""
        node = self.root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end_of_word = True

    def search(self, word):
        """Return True if word is in trie — O(L)."""
        node = self._traverse(word)
        return node is not None and node.is_end_of_word

    def starts_with(self, prefix):
        """Return True if any word in trie starts with prefix — O(L)."""
        return self._traverse(prefix) is not None

    def _traverse(self, prefix):
        """Walk trie following prefix; return final node or None if not found."""
        node = self.root
        for char in prefix:
            if char not in node.children:
                return None
            node = node.children[char]
        return node

    def autocomplete(self, prefix):
        """Return all words in trie that start with prefix — O(L + k)."""
        node = self._traverse(prefix)
        if node is None:
            return []
        results = []
        self._collect(node, prefix, results)
        return results

    def _collect(self, node, current_prefix, results):
        """DFS from node, collecting complete words."""
        if node.is_end_of_word:
            results.append(current_prefix)
        for char, child in node.children.items():
            self._collect(child, current_prefix + char, results)

    def delete(self, word):
        """Delete word from trie — O(L)."""
        self._delete(self.root, word, 0)

    def _delete(self, node, word, depth):
        if depth == len(word):
            if not node.is_end_of_word:
                return False   # word not in trie
            node.is_end_of_word = False
            return len(node.children) == 0   # True means node can be deleted

        char = word[depth]
        if char not in node.children:
            return False

        should_delete_child = self._delete(node.children[char], word, depth + 1)
        if should_delete_child:
            del node.children[char]
            # Can delete this node too if it is not a word end and has no children
            return not node.is_end_of_word and len(node.children) == 0
        return False


# Demonstration
trie = Trie()
words = ["apple", "app", "application", "apply", "apt", "bat", "bad"]
for word in words:
    trie.insert(word)

print("search 'app':", trie.search("app"))           # True (inserted directly)
print("search 'ap':", trie.search("ap"))             # False (prefix only, no end marker)
print("starts_with 'ap':", trie.starts_with("ap"))  # True

print("autocomplete 'app':", sorted(trie.autocomplete("app")))
# ['app', 'apple', 'application', 'apply']

print("autocomplete 'ba':", sorted(trie.autocomplete("ba")))
# ['bad', 'bat']

trie.delete("app")
print("after delete 'app':", trie.search("app"))         # False
print("'apple' still there:", trie.search("apple"))      # True — deletion was careful


# Dict-of-dicts implementation (more compact, common in interview code)
def make_trie():
    return {}

def insert_word(trie, word):
    node = trie
    for char in word:
        node = node.setdefault(char, {})
    node["#"] = True   # end-of-word marker

def search_word(trie, word):
    node = trie
    for char in word:
        if char not in node:
            return False
        node = node[char]
    return "#" in node

compact_trie = make_trie()
for word in ["hello", "help", "heap"]:
    insert_word(compact_trie, word)

print("search 'help':", search_word(compact_trie, "help"))   # True
print("search 'hel':", search_word(compact_trie, "hel"))     # False (no end marker)
```

---

## Visualizer

<iframe src="/static/visualizers/trie.html" style="width:100%;height:500px;border:none;border-radius:8px;" title="Trie Visualizer"></iframe>

---

## How It Connects

Hash tables offer O(L) lookup for a string of length L (due to hashing cost), but no prefix operations. The trie's advantage over a hash table is not raw lookup speed — it is the prefix-based operations that hash tables cannot support efficiently. Understanding hash tables makes the contrast with tries sharper.

[[hash-tables|Hash Tables]]

Graphs provide the general framework for understanding trie traversal. A trie is a directed acyclic graph with labeled edges (the characters) and no cycles. DFS on the trie is what `autocomplete` and `_collect` perform — collecting all words is a DFS that accumulates the path.

[[graphs|Graphs]]

---

## Common Misconceptions

Misconception 1: "A trie is always better than a hash table for string lookups."
Reality: For pure existence checking ("is this word in the dictionary?"), a hash table is simpler, more memory-efficient, and has roughly equivalent O(L) average lookup. Tries excel specifically at prefix operations: autocomplete, prefix counting, and finding the longest prefix match. Without those requirements, a hash table is the better default.

Misconception 2: "A trie uses O(n) space where n is the number of words."
Reality: A trie uses O(total characters × alphabet size) space. If every stored word is unique with no shared prefixes, each character requires its own node with up to 26 child pointers. In the worst case this is far more than O(n) where n is the number of words. Compressed tries (radix trees) mitigate this by collapsing single-child chains.

Misconception 3: "The end-of-word marker is optional — I can tell when a word ends by checking whether a node has no children."
Reality: The end-of-word marker is mandatory. Consider "app" and "apple": the node for the third 'p' in "apple" follows the node for the 'p' in "app." If "app" was inserted but "apple" was not, the 'p' node for "app" has no children — and indeed the marker approach works there. But if both "app" and "apple" were inserted, the 'p' node for "app" has one child ('l'). Without an end-of-word flag on it, there is no way to distinguish "app is stored" from "app is a prefix of apple."

---

## Why It Matters in Practice

Autocomplete is the most visible trie application in everyday software — every search engine, every IDE, and every phone keyboard uses some form of prefix tree. IP routing tables in network routers use tries (specifically Patricia tries or CIDR prefix tries) to match destination IP addresses to routing rules — a packet arriving at a router is matched against a trie of IP prefixes in microseconds. DNS lookup caches also use trie structures for hierarchical domain matching.

In competitive programming and technical interviews, tries appear frequently in string problems involving prefix matching, word search in grids, and dictionary-based validation. The trie is the right tool whenever the problem involves multiple strings with shared prefixes and the operations are "insert," "search," and "find all matching prefix."

---

## Interview Angle

Common question forms:
- "Implement a trie with insert, search, and startsWith."
- "Find all words in a board (Word Search II)."
- "Find the longest word in a dictionary that is built one character at a time."
- "Replace words in a sentence with their shortest root from a dictionary."

Answer frame:
For trie implementation, describe the node structure (children dict + is_end flag), then implement insert (loop creating nodes), search (loop + check is_end), and startsWith (loop without the is_end check). For Word Search II, explain that building a trie from the word list allows the board DFS to prune early — if the current path is not a prefix in the trie, stop exploring that direction. For "replace with shortest root," walk the trie character by character for each word until you find the first is_end=True node — that is the shortest matching root.

---

## Related Notes

- [[hash-tables|Hash Tables]]
- [[graphs|Graphs]]
- [[binary-search|Binary Search]]
