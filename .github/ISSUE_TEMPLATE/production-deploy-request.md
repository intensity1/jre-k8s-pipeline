---
name: Production Deploy Request
about: Lightweight change-management analog — required before a prod deploy runs
title: "[PROD DEPLOY] "
labels: production-deploy
---

## Production Deploy Request

**App:**

**Git SHA / branch:**

**What changed (one or two lines):**

**Risk:** Low / Medium / High

**Rollback plan:** (what will you do if this fails — e.g. `kubectl rollout undo`, revert PR, etc.)

**Backout time estimate:**

---

### Approval

Comment `approved` on this issue to authorize the deploy. The prod deploy
workflow (`.github/workflows/deploy-app.yml`) requires a reference to an
**approved** issue number as a manual input before it will run against the
`prod` environment — it will not proceed without one.

This is a deliberately lightweight stand-in for an enterprise ITSM change
record. The goal is the same discipline (documented reason, rollback plan,
recorded approval before a prod change), not the same tooling.
