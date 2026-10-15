# Arena v0: can an AI agent fix a broken Kubernetes app?

This is the smallest real test of the agent-ratings idea. It breaks a working app on purpose, gives a contestant
(you, or an AI agent) a restricted login, and grades the fix automatically with a stopwatch.

Old-world equivalent: a QA regression suite run by Jenkins. The difference is that the thing under test is the
**person or agent doing the fix**, not the code.

| Piece | Plain English | Legacy equivalent |
|---|---|---|
| `app.yaml` | A known-good copy of ratings-api in its own namespace `arena` (Argo CD ignores it) | A dedicated QA box you can trash |
| `scenarios/NN-*/break.sh` | Breaks it in one specific, realistic way | The "chaos" step: someone deploys the wrong build |
| `scenarios/NN-*/task.md` | What the contestant is told: symptoms only, never the cause | The incident ticket |
| `rbac.yaml` + `setup.sh` | A login that can look at and fix `arena` only: no Secrets, no other namespaces, can't create objects | A restricted sudoers entry for the on-call contractor |
| `check.sh` | The grader: 2 ready pods AND `/api/version` answers through the Service | A Nagios check plus a smoke-test URL |
| `run.sh` | Reset to healthy, break, confirm it's really down, start the clock, grade every 15s, record | The Jenkins job that runs the whole test |

## Scenario 01: bad image tag
Someone deployed a version that CI never published. Old pods are stopped first (Recreate strategy), and the new
ones can't download their image, so the site is fully down. Expected fix: roll back (`kubectl rollout undo`) or
set the image to a tag that exists. Old-world version: Artifactory has no WAR for the version in the deploy script.

## Where to run it: a local kind cluster, not Linode
The first runs don't need anything public, so use kind on your machine. It costs nothing, needs no IP allowlist,
and rebuilds in about a minute. Nothing here is kind-specific, so it also runs on LKE unchanged.

## Steps (one line at a time)
Check first: `uname -m` must print `x86_64`. The ratings-api image is built for amd64 only, so on an ARM
Chromebook the baseline never starts (`exec format error`). In that case, run the arena on LKE instead.

In tab 1, the referee (your admin kubeconfig):
```bash
kind create cluster --name arena
kubectl config current-context        # expect: kind-arena
./arena/setup.sh                      # expect: 5 can-i lines, "RBAC OK", "Baseline healthy"
RECORD=1 ./arena/run.sh 01-bad-image jake
```
`run.sh` prints the task, then waits and grades.

In tab 2, the contestant (agent login only):
```bash
export KUBECONFIG=~/.kube/arena-agent.yaml
kubectl get pods                      # works (namespace arena)
kubectl get pods -n kube-system       # must be Forbidden
```
Then either fix it yourself, or start the AI agent in this tab and paste the task text.

Tab 1 prints `RESULT: ... pass after Ns` as soon as the site is back.

## Order of contestants
1. **You first (`jake`)**, without help. Your time is the human baseline, and you can't judge an agent's answer
   to a test you haven't taken.
2. **One AI agent** that can run shell commands (Claude Code, Codex CLI, Gemini CLI, ...). Name the contestant
   after the agent and version, e.g. `claude-code-2026-10`.
3. Save the agent's full transcript next to the result. Pass/fail alone doesn't show whether it diagnosed the
   problem or got lucky.

## Known holes in v0 (on purpose, to keep it small)
- **The agent can cheat.** An agent with a shell on your machine can read `~/.kube/config` (your admin login)
  and ignore the restricted one. RBAC only limits what the agent kubeconfig can do. Until v1 runs the agent in a
  container that holds only the agent kubeconfig, read the transcript and disqualify any run that touched another
  kubeconfig.
- One scenario, so one result is an anecdote, not a rating. A score needs several scenarios and repeated runs.
- 15-second grading resolution, and no cost/token tracking yet.
- The grader checks "is it serving", not "is it the right version". An agent that deploys an older working tag
  passes, which matches what an on-call engineer would do.

## Cleanup
`kind delete cluster --name arena`. On LKE, `kubectl delete namespace arena` (teardown also removes it with the cluster).
