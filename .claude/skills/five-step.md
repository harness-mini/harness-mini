---
name: five-step
description: Apply Elon Musk's Five-Step Algorithm to any requirement or plan before building. Use in the intake/plan stages to question, delete, simplify, accelerate, and automate — in that order. Prevents the expensive mistake of optimizing or automating something that should have been deleted.
---

Run these **in order**. The order is the whole point.

## 1. Make the requirement less dumb
- Rewrite each requirement and attach a *person's name*, never a department.
- Ask: is this actually true? what evidence? Even smart people's requirements
  are partly wrong. Push back before proceeding.

## 2. Delete the part or process
- Delete every requirement, step, or component you can.
- Test of sufficiency: if you are **not later forced to add back ≥10%**, you
  didn't delete enough. Over-delete on purpose.

## 3. Simplify / optimize — only what survived step 2
- Now, and only now, optimize what remains.
- The classic smart-engineer error is optimizing something that shouldn't exist.

## 4. Accelerate cycle time
- Speed up the surviving, simplified process. Never before steps 1–3.

## 5. Automate — last
- Automate only what survived all four steps. Automating a flawed process
  locks the flaw in and replicates it across every future agent run.

## Output
Append a short "Five-Step pass" block to the active exec-plan listing what was
deleted (and what you predict you'll add back), then proceed to `to-prd`.
Trace it: `bin/trace.sh <agent> <stage> five_step deleted=<count>`.
