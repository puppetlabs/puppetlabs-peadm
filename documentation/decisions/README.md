# Design decisions

Each file here records one decision about how PEADM behaves: the context, what was decided, and what it changes. Read the note before changing the behaviour it covers, and update the note in the same pull request if the decision changes.

## Naming

Files are named `NNNN-short-title.md`. `NNNN` is the next unused four-digit number; numbers are never reused, even if a note is withdrawn.

## Status

Each note starts with a status line:

* **Proposed:** open for review; the note names who must sign it off.
* **Accepted:** signed off; the behaviour it describes is the target.
* **Superseded by NNNN:** replaced by a later note, which says what changed.

## Stable references

Tickets and code comments cite notes by number and, inside a note, by row or section. Don't renumber rows: add new ones at the end of the numbering, even if they appear earlier in a table.

## Index

| Note | Title | Status |
| --- | --- | --- |
| [0001](0001-failures-that-may-end-with-warnings.md) | Which failures may end a run with warnings | Proposed |
