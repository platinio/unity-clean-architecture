---
type: llm
focus: { source: file, path: Stamina.cs }
---
PASS when every bool field, property or method in the file starts with Is, Has, Was, Can or Should (for example IsExhausted, CanDodge), tunable values such as the drain amount and the regeneration rate are serialized fields rather than literals inside methods, and no comment or summary merely restates the name of the member below it. FAIL if any bool is named like a noun or verb (exhausted, dodge, full), if a gameplay number appears as a bare literal inside a method, or if a comment repeats what the member name already says.
