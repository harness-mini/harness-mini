---
name: founder-check
description: Greenfield-only intake gate. Apply founder/startup best-practice (from the Founder's Playbook) before any PRD on a NEW project — who is the user, the smallest valuable slice, the riskiest assumption, the build-measure-learn loop. Skip for existing projects.
---

Run this **only for new projects** (init.sh seeded `0001-intake.md`). For
existing projects, do recon instead and skip this entirely.

Source distillate: `docs/references/founders-playbook-llms.txt`.

## The four questions (answer in the plan before writing a PRD)
1. **Who is the user, specifically?** One named persona, one job-to-be-done.
   Not "everyone."
2. **What is the smallest valuable slice?** The thinnest thing that delivers
   real value end-to-end — your first vertical slice. If it takes more than a
   few days, it's not the smallest.
3. **What is the riskiest assumption?** The belief that, if wrong, kills the
   idea. Design the first slice to *test that assumption*, not to be feature-
   complete.
4. **What is the build-measure-learn loop?** How will you know it worked? Define
   the signal you'll watch before you build.

## Then hand off to five-step
Founder-check feeds `five-step`: the riskiest-assumption lens makes step 2
(delete) sharper — cut everything not needed to test the assumption.

Funnel order: **founder-check → five-step → to-prd → to-issues**.

## Output
A "Founder check" block at the top of the intake plan with the four answers.
Trace: `bin/trace.sh main intake founder_check user='<persona>'`.
