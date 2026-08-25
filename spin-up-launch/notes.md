Submitting one batch

bash spin-up-launch/submit_chain_spinup.sh 01     # one landscape: 9 reps, 3 nodes, 1 PBS job
bash spin-up-launch/submit_chain_spinup.sh        # all six, afterok-chained
The mechanism is four small pieces:

Line 53 — lcp="${1:-}" captures the argument. The :- default is load-bearing: under set -u, a bare $1 with no argument given would abort with "unbound variable". This makes "no argument" a legal, detectable state rather than a crash.

Lines 56–60 — if [ -n "$lcp" ] forks on "was an argument given". The case "$lcp" in 0[1-6]) glob accepts exactly two characters: 0 followed by 1–6. So 01…06 pass, while 1, 7, 07 and typos fall through to *) and exit. That validation matters because the value goes straight into a filesystem path on the next line.

Line 61 — batches=("${script_dir}/cmdfile_spin_${lcp}.sh") builds a one-element array. This is the whole design idea: single-batch mode doesn't get its own submission logic, it just produces a shorter array. Line 62 then explicitly checks the file exists, which the glob branch gets for free but this branch doesn't — without it a typo would hand a nonexistent path to launch_cf.

Lines 68–77 — the loop is shared. JID starts empty, so the first iteration takes the -z "$JID" branch and submits with no dependency; only later iterations add -W depend=afterok:${JID}. With one batch the loop runs once, takes the first branch, and you get a standalone job — exactly right for a test.

One practical consequence worth knowing: after 01 succeeds, running the script with no argument to do the full six **re-runs landscape 01 from scratch and destroys its nine finished replicates** — output databases and snapshots alike. The resume guard this note originally relied on was removed from the runner on 2026-08-22, so every submitted line now always runs and `rm -rf`s its scenario directory first. Submit landscapes 02-06 individually, or move landscape 01's output aside before a full-six submission.

Also note shopt -s nullglob on line 55 protects the other branch: without it, a non-matching glob would survive as a literal string and the (( ${#batches[@]} )) count check would pass with one bogus element.