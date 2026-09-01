---
name: smallest-clean-diff
description: Prefer the smallest change that solves the problem cleanly; one mechanism over many, DRY and KISS over cleverness.
---

# Smallest clean diff

The best diff is the one a reviewer can hold in their head. Extra mechanisms, speculative generality, and parallel code paths are costs paid by everyone who reads the code later.

**Why:** surface area is where bugs and maintenance live; less of it is strictly better when the problem is still solved.

**How to apply:** solve the actual problem, not an imagined family of future ones. Reuse the existing mechanism before adding a new one. If you introduced two ways to do a thing, remove one.

**This also governs how the edit is applied, not just its size.** A one-line change delivered as a whole-file rewrite is a small diff produced the most expensive way: the file's length is paid twice, once in the call and once in the result, and the reviewer sees a replacement instead of an edit. Prefer a targeted edit with a unique anchor, then an in-place substitution, then an append; rewrite the whole file only when it is new or when most of it actually changes. The anchor-finding is not overhead — it is the step that fails loudly when your assumption about the file is stale, which a blind rewrite does not.
