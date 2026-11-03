---
type: llm
focus: trace
---
PASS when the review names all three of these: the null-conditional `health?.IsDead` on a UnityEngine.Object (a destroyed component passes the check, so the fix is `health == null`); the `is KnockedDownState` / `is DeadState` type tests and the `switch` on HitKind as a case list the object or the data could answer itself (polymorphism, a question on the state, or damage carried by data); and the test `Light_hit_damages_health`, whose only assertion `Assert.IsNotNull(health)` cannot fail. FAIL if any of the three is missing, or if the response rewrites the code instead of reporting findings.
