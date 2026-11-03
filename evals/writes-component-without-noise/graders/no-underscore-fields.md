---
type: regex
target: { source: file, path: Stamina.cs }
pattern: "private\\s+[\\w<>\\[\\]]+\\s+_[a-z]"
match: not_contains
---
