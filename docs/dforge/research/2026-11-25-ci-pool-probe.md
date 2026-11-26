# CI pool probe — 2026-11-25

Task 1 of the CI for pushed branches plan: the throwaway `probe` job of `.github/workflows/ci.yml` (commit 124ee58),
`runs-on: [self-hosted, doment-linux]`.

- **Run:** https://github.com/darkraise/doment/actions/runs/45543424998 (job
  https://github.com/darkraise/doment/actions/runs/45543424998/job/139289770348)
- **Attempts:** the first run and one re-run each stayed queued for 15 minutes and were cancelled
  (`gh api repos/darkraise/doment/actions/runs/45543424998/attempts/<n>`). The owner reported that ghr did not yet
  serve doment then and that they added it; the next re-run's job started at 14:50:20 UTC and ended `success` at
  14:50:46 UTC (`.../attempts/3/jobs`).
- **Labels and runner:** `self-hosted,doment-linux` on runner `ghr-doment-da5047`. The runner version (2.338.2), group
  (`Default`) and machine name come from the runner's own header at the top of the job log, not from the probe step.
- **Registered runners:** `gh api repos/darkraise/doment/actions/runners` reports `total_count` 0 while no job runs
  (checked again 2026-11-27). Every job so far has run on a different runner name, so ghr appears to register one
  runner per job; that is inferred from the logs, not documented by ghr.

## Printed facts

Each line below is the probe step's own output, except where it says otherwise.

- host: `secondary-25-10-2028`
- runner: `ghr-doment-da5047`
- user: `ghrunner`
- home: `/home/ghrunner`
- `~/.ssh`: absent
- `~/.nuget/packages`: exists, 19 entries
- cgroup: `0::/system.slice/ghr-runner-da5047.service`
- job-started hook: `/opt/ghr/hooks/job-started.sh`. The probe did not print the hook's text: it printed
  `fork refusal: installed at /opt/ghr/hooks/job-started.sh`, which it does only when `grep` finds
  `refusing a job started from another repository` in that file.
- job-completed hook: `/opt/ghr/hooks/job-completed.sh`, from the runner's own log lines after the probe step, not
  from the probe.
- `clang`: missing
- `jq`: `/usr/bin/jq`
- `file`: missing
- `ps`: `/usr/bin/ps`
- `pgrep`: `/usr/bin/pgrep`
- `ssh`: `/usr/bin/ssh`
- workspace file system: `/dev/vda3` mounted on `/`, 115467420 KiB in all, 99086568 KiB available, 11% used
  (`df -Pk`). 99086568 KiB is about 94.5 GiB (101 GB), computed here, not printed.

## Owner actions

- Add `clang` to the `doment-linux` pool's managed packages: the NativeAOT publish links with it.
- Add `file` to the `doment-linux` pool's managed packages: the NativeAOT acceptance suite reads binary types with it.

Until both are present, `build/ci.sh verify` (Task 4) fails every run with the missing-package annotation. The probe
did not look for `zlib.h` (package `zlib1g-dev`), which `verify` also requires; Task 5's first run shows whether it is
present.

## Job durations (Task 5)

First green run: https://github.com/darkraise/doment/actions/runs/45735004164 (commit 57af03b, 2026-11-26). Queue time
is `created_at` to `started_at`; run time is `started_at` to `completed_at`
(`gh api repos/darkraise/doment/actions/runs/45735004164/attempts/<n>/jobs`). The machine is the `Machine name` line of
each job's log header.

| Job | Attempt | Runner | Machine | Queued | Ran |
|---|---|---|---|---|---|
| `acceptance` | 1 | `ghr-doment-69cabd` | `primary` | 27 s (01:19:43 to 01:20:10 UTC) | 62 min 55 s (to 02:23:05 UTC) |
| `check` | 3 | `ghr-doment-8d40f6` | `primary` | 20 s (14:28:27 to 14:28:47 UTC) | 11 min 19 s (to 14:40:06 UTC) |

## The pool has two machines

The `doment-linux` pool serves jobs from two machines, `primary` and `secondary-25-10-2028`, and a job can land on
either. The probe ran on `secondary-25-10-2028` only, so its tool list describes that machine on 2026-11-25.

The `check` job's attempts 1 and 2 of run 45735004164 failed `build/ci.sh verify` with `file is missing on the runner`
(runner `ghr-doment-826a16` at 01:20:19 UTC, runner `ghr-doment-c14484` at 02:24:11 UTC). Both ran on
`secondary-25-10-2028`, and both passed the `clang` and `jq` checks that `verify` makes before `file`. Attempt 1's
`acceptance` job, which found `file`, ran on `primary`. So `file` did not disappear: `primary` had it and
`secondary-25-10-2028` did not. Attempt 3's green `check` also ran on `primary`, so it does not show the secondary
machine fixed. That shows first in run 45842901420 (2026-11-26), whose `check` job passed `verify` on
`secondary-25-10-2028` at 14:50 UTC. Every tool `verify` requires was therefore present on both machines by that time.
