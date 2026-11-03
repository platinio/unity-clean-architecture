---
description: A question about where a designer-tuned value lives triggers the toolbox and gets the Arcane Onyx answer.
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: The cooldown lives in an asset referenced by the character, not on the component and not as a constant.
---

Quick one for our Unity project (it uses Zenject and the Arcane Onyx modules). The dodge cooldown is currently `private const float DodgeCooldown = 1.2f;` inside DodgeAction.cs. The designer wants to tune it, and the brute enemy should have a longer cooldown than the player. Where should this value live and how does DodgeAction get it?
