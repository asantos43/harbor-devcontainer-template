# Tasks

Every Harbor task in this project lives here, one directory per task.

```bash
harbor init -t my-task -o task          # scaffold task/my-task
harbor run  -p task/my-task -a oracle   # reference run; expect reward 1.0
```

A task directory looks like:

```
task/my-task/
├── instruction.md          # what the agent is asked to do
├── task.toml               # metadata, timeouts, resource requests
├── environment/Dockerfile  # the container the agent works in
├── solution/solve.sh       # reference solution (run by the `oracle` agent)
└── tests/                  # pytest assertions -> /logs/verifier/reward.txt
```

Run output does **not** land here — it goes to `jobs/` at the project root, which is
gitignored.
