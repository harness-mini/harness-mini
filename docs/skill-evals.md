# Skill lift-evals

A **sensor** for whether a skill changes agent behavior. It is not the slice
acceptance firewall (`skills/evaluate` grades one slice against its plan, from
a separate context). It is not a `harness.sh status` gate and it does not run
in `doctor`.

Run it on the **garden cadence**: after several checkpoints, when a plan
reaches done, before a release, or when the smell backlog is due. Same triggers
as the `garden` skill. Not every slice.

## Layout

```
skills/<name>/
  SKILL.md
  evals/
    evals.json
    fixtures/<case-name>/
      inputs/                         # optional prompt inputs
      with_skill/reply.md             # fixture-oracle arm (answer key)
      without_skill/reply.md
```

`init.sh` copies the whole skill tree, so `evals/` is installed with the skill.
`evals.json` follows the portable [Agent Skills](https://agentskills.io/skill-creation/evaluating-skills)
shape: `skill_name`, and `evals[]` with `id`, `prompt`, `expected_output`,
optional `files`, and `assertions`. Two Mini fields sit beside that:

| Field | Values | Role |
|-------|--------|------|
| `name` | slug | fixture directory |
| `style` | `happy` · `trigger` · `adversarial` · `saturated` | what the case is for |
| `trigger` | `should_fire` · `should_not_fire` | whether this skill should load |
| `checks` | string oracle, below | keyless grader |

`assertions` are the portable rubric (prose a person or an external runner can
grade). `checks` are the deterministic oracle CI runs. Prefer checks. An LLM
judge is optional and never the only gate when a check can say the same thing.

One field per line. No escaped quotes inside strings. `id` is a positive integer.

### Checks

```
[saturated] <kind> <present|absent> <fixed string>
```

| kind | graded against |
|------|----------------|
| `contract` | the live `SKILL.md` (drift gate, not lift) |
| `both` | both transcripts |
| `with` / `without` | that arm only |

The string is a fixed substring (`grep -F`), not a regular expression.
`both` states the **skilled** behavior. The with-skill transcript must satisfy
it. The without-skill transcript must fail at least one such check, or the case
has no lift.

`saturated` marks a check the baseline already passes. A `style: saturated`
case must pass on **both** arms. Green on both is not a skill win — it means
the case measured nothing. Do not delete those cases; they keep weak rubrics
visible. See the note in skill-eval-harness: an eval you can always pass is broken.

### Lift

A case **passes an arm** when every transcript check on that arm holds.
Contract checks must pass, and they do not enter the rate.

```
lift = pass_rate_with − pass_rate_without
```

`pass_rate_*` is cases passed / cases. Positive lift means the skill arm
passed cases the baseline did not. Repeated live runs can also report pass@k
and token cost; the keyless script does not.

Wave A case mix, at least three per skill:

- **happy** — the skill should fire and do the job
- **trigger** — it should fire, or it should refuse because another skill owns the job
- **adversarial** or **saturated** — a jailbreak of the rule, or a rubric the baseline already aces

## Keyless command (default CI)

```bash
bash bin/skill-eval.sh
```

No API key. Stdout is JSON. The numbers below are an example; they move
when cases change:

```json
{
  "mode": "fixture-oracle",
  "live": false,
  "cadence": "garden",
  "wave": "A",
  "ok": true,
  "pass_rate_with": "1.000",
  "pass_rate_without": "0.048",
  "lift": "+0.952"
}
```

Exit 0 when the Wave A schema, input files, contract checks, and fixture lift
rules hold. Exit 1 otherwise. `--only <skill>` grades one skill (authors).
`--root DIR` points at another tree.

The numbers are the **fixture oracle**: committed transcripts, not a live
agent. They lock the rubric and prove the with/without arms actually differ.
They do not prove a model will follow the skill. Treat `fixtures/*/with_skill`
and `without_skill` as answer keys — a live run must not paste them into the
prompt.

`tests/run.sh` runs this command. That is the deterministic check CI can own.
Mini does not start a live agent job and does not require a key.

## Live runs (people, optional)

Install a runner **beside** this repo. Do not vendor it.

| Runner | Paired comparison |
|--------|-------------------|
| [skill-eval-harness](https://github.com/adewale/skill-eval-harness) | `with_skill` / `without_skill` rows, then a lift report |
| [caliper](https://github.com/edonadei/caliper) | run the spec, run again with the skill ablated, then `compare` |
| [SkillEvaluator](https://docs.nvidia.com/skills/skillevaluator/tier3-live-evaluation) | same cases with and without the skill; reports skill lift |

Give the runner the case `prompt`, `files`, and `assertions`. Point the
with-skill arm at `skills/<name>/` and the baseline arm at the same prompt with
no skill. Keep the host's own key out of default CI. Record pass@k only when
the runner repeats the pair.

## Wave A

`session-init`, `session-coding`, `evaluate`, `stage-viewer`, `to-prd`,
`to-issues`, `tdd`.

Later waves add their own `evals/evals.json` and extend the list in
`bin/skill-eval.sh`. Until then the checker ignores them on purpose.
