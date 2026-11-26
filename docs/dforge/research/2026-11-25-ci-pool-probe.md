# CI pool probe — 2026-11-25

Task 1 of the CI for pushed branches plan: the throwaway `probe` job of `.github/workflows/ci.yml` (commit 124ee58),
`runs-on: [self-hosted, doment-linux]`.

- **Run:** https://github.com/darkraise/doment/actions/runs/45543424998 (job
  https://github.com/darkraise/doment/actions/runs/45543424998/job/139289770348)
- **Attempts:** the first run and one re-run each stayed queued for 15 minutes and were cancelled while ghr did not yet
  serve doment (0 registered runners). After the owner added doment to ghr, the next re-run started at 14:50:20 UTC and
  ended `success` at 14:50:46 UTC.
- **Labels and runner:** `self-hosted,doment-linux` on runner `ghr-doment-da5047` (runner version 2.338.2, group
  `Default`). The repository lists 0 registered runners while idle: ghr registers a runner when a job is queued.

## Printed facts

- host: `secondary-25-10-2028`
- runner: `ghr-doment-da5047`
- user: `ghrunner`
- home: `/home/ghrunner`
- `~/.ssh`: absent
- `~/.nuget/packages`: exists, 19 entries
- cgroup: `0::/system.slice/ghr-runner-da5047.service`
- job-started hook: `/opt/ghr/hooks/job-started.sh`; it contains `refusing a job started from another repository`
  (the fork refusal is installed). A job-completed hook, `/opt/ghr/hooks/job-completed.sh`, also runs.
- `clang`: missing
- `jq`: `/usr/bin/jq`
- `file`: missing
- `ps`: `/usr/bin/ps`
- `pgrep`: `/usr/bin/pgrep`
- `ssh`: `/usr/bin/ssh`
- workspace file system: `/dev/vda3` mounted on `/`, 115467420 KiB in all, 99086568 KiB available (11% used, about
  94 GB free)

## Owner actions

- Add `clang` to the `doment-linux` pool's managed packages: the NativeAOT publish links with it.
- Add `file` to the `doment-linux` pool's managed packages: the NativeAOT acceptance suite reads binary types with it.

Until both are present, `build/ci.sh verify` (Task 4) fails every run with the missing-package annotation. The probe
did not look for `zlib.h` (package `zlib1g-dev`), which `verify` also requires; Task 5's first run shows whether it is
present.

## Job durations (Task 5)

First green run: https://github.com/darkraise/doment/actions/runs/45735004164 (commit 57af03b, 2026-11-26), host
`secondary-25-10-2028`. Queue time is `created_at` to `started_at`; run time is `started_at` to `completed_at`
(`gh api repos/darkraise/doment/actions/runs/45735004164/attempts/<n>/jobs`).

| Job | Attempt | Runner | Queued | Ran |
|---|---|---|---|---|
| `acceptance` | 1 | `ghr-doment-69cabd` | 27 s (01:19:43 to 01:20:10 UTC) | 62 min 55 s (to 02:23:05 UTC) |
| `check` | 3 | `ghr-doment-8d40f6` | 20 s (14:28:27 to 14:28:47 UTC) | 11 min 19 s (to 14:40:06 UTC) |

The `check` job's attempts 1 and 2 failed `build/ci.sh verify` with `file is missing on the runner` (runners
`ghr-doment-826a16` at 01:20:19 and `ghr-doment-c14484`), while attempt 1's `acceptance` verify on the same host found
`file` at 01:20:28; attempt 3 ran after the owner fixed `file` on the host (asked to make it a managed package).
