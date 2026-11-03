# Weak tests: green runs that prove nothing

Read this when a test in a review matched one of the tells and you need its mechanism to argue the
finding.

The author of a change usually wrote its tests in the same sitting, and increasingly the author is an
agent graded on "make the suite pass". Both take the cheap path under pressure: a test shaped around
what the code *does* rather than what it was *supposed to do*, or an inconvenient existing test quietly
loosened. A green run is therefore self-confirmation until someone independent reads what the tests
assert.

The question for every test is the same: **if the production code were wrong, would this go red?**
Answer it by naming the production line whose breakage fails the test. If you cannot name one, the test
is a finding, and the cost to name is the specific bug this test would wave through.

## Tampering: an existing test changed to get green

*Fix before merge* unless the PR description or spec explicitly changes the behaviour the test asserted.
Diff the test files against the base and grep the diff rather than trusting a read-through; quote the
old assertion next to the new one in the finding.

- **Deleted test, fixture or `[TestCase]` row.** The inconvenient case is the one that goes missing.
  Check renamed files too: a "moved" test sometimes arrives lighter than it left.
- **`[Ignore]`, `[Explicit]`, `Assert.Ignore`, `Assert.Inconclusive`, `Assert.Pass`**, or an early
  `return` above the asserts. All of them report as not-failed.
- **`LogAssert.ignoreFailingMessages = true`**, or a new `LogAssert.Expect(LogType.Error|Exception, …)`.
  In the Unity Test Framework an unexpected error log fails the test; this is the one-line way to
  silence an error the change introduced. Legitimate only when the error is the behaviour under test.
- **Loosened assertion.** `AreEqual` → `IsNotNull`, an exact value → a range, a widened float tolerance
  or timeout, a collection compared by `Count` instead of content, a regex broadened until it matches
  anything.
- **Expected value edited to match the new output** with no spec change behind it. The diff shows a
  constant changing in the test and the production code in the same commit; ask which one was wrong.
- **Assert commented out, or behind `#if` / `if (false)` / a platform define that is never set.**
- **A test stopped being discovered**: an asmdef reference or `defineConstraints` changed, a class made
  non-public or abstract, `[Test]` dropped in a refactor. No assertion changed and nothing fails; only
  the suite total moves. Ask for the before and after totals if the PR does not state them.

## Vacuous: a new test that cannot fail

*Should fix*; *fix before merge* when it is the only test covering a bug fix or a stated requirement.

- **Asserts what it just set.** Arrange `x.Value = 5`, assert `x.Value == 5`, with no production logic
  between the two.
- **Expected value computed by the code under test.** `Assert.AreEqual(Score(a), Score(a))`, or the
  expectation built with the same helper the production path calls. It pins nothing but determinism.
- **Only not-null, no-throw, or "returns something".** `Assert.DoesNotThrow` alone, `IsNotNull` on a
  constructor result, `Assert.IsTrue(list.Count >= 0)`.
- **No assert at all**, including a `[UnityTest]` that yields a few frames and ends. It passes unless
  something throws or logs an error.
- **Asserts that never execute.** Inside a `foreach` over a collection that may be empty; inside a
  callback the test never confirms was invoked; after a `yield` the coroutine never reaches; inside a
  `try` whose `catch` swallows. Look for a guard: a counter, a `wasCalled` flag, an
  `Assert.That(items, Is.Not.Empty)` first. No guard, no test.
- **Mocks away the change.** The fake implements the very interface the feature added, so the real code
  path never runs and the test verifies the fake.
- **Mirrors the implementation.** The test re-derives the result with the same algorithm, or asserts
  call order and private state (reflection into fields) rather than observable behaviour. It fails on
  refactors and passes on bugs, the wrong way round.
- **Happy path only, where the spec named the edge.** The requirement says "empty / destroyed agent /
  re-entered after abort" and the tests cover only the populated, alive, first-entry case.

## Unity-specific traps

- **Time- or frame-dependent without control.** `yield return new WaitForSeconds(…)` then assert, with
  no injected clock and a tolerance wide enough to hide the bug. Also flaky, which trains everyone to
  re-run red.
- **Static or scene state leaking between tests.** Passes in suite order, fails alone, or the reverse:
  the test asserts on a previous test's leftovers. Missing `[TearDown]`, objects created and never
  destroyed, statics never reset.
- **Destroyed-object checks that cannot see destruction.** NUnit's `Assert.IsNull(obj)` on a
  `UnityEngine.Object` compares the C# reference, which is still live after `Destroy`; the assert fails
  when the code is right, and the "fix" is usually to delete it. `Assert.IsTrue(obj == null)` uses
  Unity's overload. In EditMode, `Destroy` is deferred and `DestroyImmediate` is what the test needs.
- **EditMode test for behaviour that only exists in Play.** `Awake`, `Start` and `Update` never ran; the
  test asserts on default field values and passes.

## Coverage against the spec

When a spec, feature document or PR description states what the change promises, walk it line by line
against the tests and list every promised behaviour no test asserts, one line each with the requirement
quoted. The author tests the cases they already thought of; this is the check they cannot do for
themselves. No spec available: say so in the Scope line and derive the promises from the PR title and
the public API instead.

## When reading cannot settle it

You never run anything. If you cannot tell from the source whether a test is able to fail, do not assert
either way: name the one-line mutation that would settle it ("negate the guard at `Foo.cs:88`;
`Foo_Rejects_Stale_Target` must go red") and put it in the finding. For a bug-fix PR the mutation is
always available and always worth naming: revert the fix, and the new test must fail.
