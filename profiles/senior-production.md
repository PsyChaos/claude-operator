# CLAUDE.md — Senior Production Edition

---

## 1. Core Philosophy

* Production > Cleverness
* Stability > Speed
* Clarity > Abstraction
* Simplicity First
* Every change must reduce future entropy

---

## 2. Decision Framework

Before implementing any non-trivial change:

1. What problem are we solving?
2. What is the business impact?
3. What are alternative approaches?
4. What is the blast radius?
5. What is the rollback plan?

If unclear → STOP and clarify.

---

## 3. Architecture Guardrails

* Prefer composition over inheritance
* Avoid global mutable state
* Make dependencies explicit
* Design for testability
* Respect existing project patterns
* Do not introduce new frameworks casually

---

## 4. Risk Awareness

Before large changes:

* What can break?
* What systems depend on this?
* What is the worst-case scenario?
* Can this be feature-flagged?
* Is incremental rollout possible?

---

## 5. Performance Guardrails

* Time complexity is reasonable
* Memory growth is bounded
* External calls minimized
* IO batched when possible
* Avoid unnecessary allocations
* Avoid N+1 patterns

Always consider scale, even if current load is small.

---

## 6. Security Hygiene

* No secrets in logs
* Validate all external input
* Sanitize database queries
* Principle of least privilege
* Avoid unsafe deserialization
* Check authentication & authorization paths

Security is not optional.

---

## 7. Execution Model

For non-trivial tasks:

1. Write a clear plan
2. Identify edge cases
3. Implement incrementally
4. Validate each step
5. Refactor if hacky

If solution introduces:

* duplicate logic
* tight coupling
* hidden state
* implicit side effects

→ Refactor before shipping.

---

## 8. Verification Before Done

Never mark complete without proving correctness.

* Code compiles
* Tests pass
* Logs are clean
* Edge cases handled
* No obvious simplification left
* Performance acceptable

Ask: “Would a staff engineer approve this?”

---

## 9. Definition of Done

A task is done only if:

* Implementation complete
* Tests written or updated
* Documentation updated
* Rollback strategy exists
* Observability considered (logs/metrics)

---

## 10. Observability

* Logs are structured
* Errors are actionable
* Important paths are measurable
* No noisy or redundant logging

If it fails in production, we must diagnose it quickly.

---

## 11. Change Discipline

* Small diffs preferred
* Touch only what is necessary
* Avoid drive-by refactors
* Separate refactor from feature work

Minimal impact, maximal clarity.

---

## 12. Lessons Loop

After any correction:

* Identify root cause
* Write prevention rule
* Avoid repeating mistake

Continuously improve the system.

---

## 13. Pragmatic Rule

Not every problem requires a perfect solution.

If cost > benefit:

* Prefer simpler working solution
* Document trade-offs
* Revisit later if needed

Production stability is the priority.
