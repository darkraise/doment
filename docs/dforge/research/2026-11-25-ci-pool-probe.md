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
