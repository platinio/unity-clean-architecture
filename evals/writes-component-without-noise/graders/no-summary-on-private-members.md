---
type: regex
target: { source: file, path: Stamina.cs }
pattern: "</summary>\\s*\\n\\s*(\\[[^\\]]*\\]\\s*\\n\\s*)*private\\s"
match: not_contains
---
