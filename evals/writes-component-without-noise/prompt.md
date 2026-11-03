---
description: A new Unity component written from a chat request follows the house style without being told to.
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Write]
expected_outcome: Stamina.cs with camelCase fields, question-shaped booleans, no summary on private members, no comment restating a name.
---

I'm working on a Unity 6 third-person game. Write me a Stamina component for the player: it holds a max and a current value, drains by a configurable amount when the player dodges, regenerates per second while idle, and other systems need to know when it hits zero and when it is full again. Save it as Stamina.cs in the current folder. Plain C#, no DI container in this project.
