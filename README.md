# sentinel-dbt-demo

A Snowflake-native version of [dbt-sentinel](https://github.com/qraza/dbt-sentinel): failing dbt tests diagnosed by a dbt model running **inside the warehouse**, with no external process, no API key, and no data leaving Snowflake.

> **The LLM call is stubbed.** Snowflake Cortex AI functions aren't available on trial accounts. Everything else — evidence gathering, prompt construction, structured output handling, run history — runs for real. Enabling the real call is a one-line change (see [Enabling Cortex](#enabling-cortex)).

---

## Why this exists

dbt tells you a test failed and how many rows. It doesn't tell you *why*. The Python version of Sentinel closes that gap by reading dbt's artifacts and calling the Anthropic API over HTTP — which works anywhere, but means sending rows outside the warehouse and installing a tool.

This is the alternative shape. Two facts make it possible:

1. **`store_failures`** — dbt already writes failing test rows into warehouse tables.
2. **Snowflake Cortex** — exposes LLMs as SQL functions with schema-enforced structured output.

So the diagnosis doesn't need to be a Python process pulling data *out* of Snowflake. It can be a dbt model running *inside* it.

## How it works

```
dbt build
 └─ assert_speed_is_plausible fails
     └─ store_failures writes offending rows to <schema>_dbt_test__audit

dbt run --select sentinel__failures+     ← separate step, see Known constraints
 ├─ sentinel__failures    (view)  collect + verify failing rows, cap sample
 ├─ sentinel__prompts     (view)  build the grounded prompt
 └─ sentinel_diagnoses    (incremental)  LLM call → structured verdict, appended
```

Each model owns one stage, and the LLM is confined to one of them: everything before `sentinel_diagnoses` is deterministic evidence-gathering, and the model call itself sits behind a single dispatched macro.

### The demo data

Deliberately trivial, so the interesting code is obviously the diagnosis pipeline and not the data:

- `seeds/trips.csv` — six taxi trips with a distance and a duration
- `models/trip_speeds.sql` — computes `avg_speed_mph` with a **planted bug**: `* 600` where it should be `* 60`, inflating every speed tenfold
- `tests/assert_speed_is_plausible.sql` — asserts speed stays under 100 mph; four of six rows breach it

### The prompt

The grounding rules are carried over from the Python version's system prompt, including the one its evaluation harness proved necessary:

1. Ground every statement in the evidence provided.
2. If evidence is insufficient, say so and set confidence to `low`. Don't invent tables, columns or values.
3. **If evidence supports more than one plausible explanation** (the data may be wrong, *or* the test's expectation may be stale), name the competing explanations and set confidence to `low`. Reserve `high` for when alternatives are ruled out.
4. Respond as JSON: `root_cause`, `suggested_fix`, `confidence`, `evidence`.

Rule 3 isn't decoration. In the Python implementation, adding it took calibration from 0.00 to 1.00 with no accuracy loss — without it, the model confidently diagnoses cases the data can't resolve.

### Structured output

Once Cortex is live, `AI_COMPLETE`'s `response_format` argument verifies each generated token against a JSON schema, so the four-field verdict is guaranteed to conform and `confidence` can only ever be `high`, `medium` or `low`. The verdict destructures straight into typed columns — no parsing, no fail-safe branch.

This is **stronger** than the Python version, which parses JSON out of free text after the fact.

---

## Running it

Requires a Snowflake connection and a dbt project. Two commands, in this order:

```bash
dbt build                                # tests run; failures land in the audit schema
dbt run --select sentinel__failures+     # diagnose them
```

Then:

```sql
select run_started_at, test_name, failure_count, confidence, root_cause
from SENTINEL_FUSION_DEMO.DBT_Q.sentinel_diagnoses
order by run_started_at desc;
```

### Verifying both paths

The demo is only trustworthy if it behaves correctly when nothing is wrong:

| Scenario | Expected |
|---|---|
| `* 600` (bug present) | Test fails, one new row in `sentinel_diagnoses` |
| `* 60` (bug fixed) | Test passes, **no** new row, nothing charged |

The green path matters — `having count(*) > 0` means a healthy project produces no diagnoses and incurs no LLM cost.

---

## Known constraints

Both of these were found by building this, not by designing it. They're real properties of dbt, and any implementation of this pattern has to live with them.

### 1. The audit table goes stale

dbt writes the failures table when a test fails, but **does not clear it when the test starts passing**. A naive model reading that table will report yesterday's failures as current — and produce a confident diagnosis of a problem that no longer exists.

`sentinel__failures` guards against this by joining the audit rows back to the live model and keeping only rows that are *still* failing:

```sql
from <schema>_dbt_test__audit.assert_speed_is_plausible a
inner join {{ ref('trip_speeds') }} t
  on a.trip_id = t.trip_id
 and t.avg_speed_mph > 100
```

This is the warehouse-side equivalent of the stale-manifest problem the Python version hit: a diagnostic tool that can be confidently wrong must check whether its inputs are current.

The demo's guard hardcodes the test's condition, so it doesn't generalise. A general version needs to establish whether the audit table was written by the current run.

### 2. Diagnosis can't run inside the same `dbt build` as the test

When a test fails, dbt **skips its downstream nodes**. The sentinel models depend on `trip_speeds`, so a failing test on that model blocks exactly the models meant to diagnose it.

Hence the two-step sequence. This isn't a workaround so much as the actual shape of the solution — in dbt Cloud it's a job with two steps, the second of which runs regardless of the first's test results.

---

## Enabling Cortex

The stub/real switch lives in exactly one place: `macros/sentinel_ai_complete.sql`. Flip one variable in `dbt_project.yml`:

```yaml
vars:
  sentinel_use_stub: false
  sentinel_model: 'claude-sonnet-4-5'
```

Prerequisites:

- A **paid** Snowflake account — trial accounts can't call Cortex AI functions
- `CORTEX_USER` (granted to `PUBLIC` by default) and the `USE AI FUNCTIONS` privilege
- The model available in your region, or `CORTEX_ENABLED_CROSS_REGION` set
- Use `AI_COMPLETE`, not `SNOWFLAKE.CORTEX.COMPLETE` — the latter is legacy and deprecated end of 2026

---

## Fusion compatibility

The target environment is dbt Cloud on the **Fusion** engine, which constrains the design. Fusion in the dbt platform is a paid-tier feature, so this demo runs on v1; Fusion compatibility is verified separately against the local Fusion binary.

Design choices made for Fusion:

| Choice | Reason |
|---|---|
| No `on-run-end` hook | Reported to hang indefinitely on Fusion in dbt platform after a successful insert |
| No dependency on the Jinja `results` object | `compiled_code` and the test `failures` count are missing from Fusion's run results |
| `default__` prefix on all dispatch candidates | Fusion requires it — a breaking change from dbt Core |
| No agate / Python objects | Fusion's Jinja is Rust, not CPython |
| Models rather than macros wherever possible | Normal dependency ordering, `--select` support, testable in isolation |

Evidence therefore comes from the **warehouse** (`store_failures`) and metadata from **`graph.nodes`**, never from the engine's run context.

---

## What's deliberately unfinished

- **Cortex call untested** — trial account limitation; one-line change to enable
- **No SQL in the prompt** — the model sees that output is wrong but not the calculation producing it, so suggested fixes are generic. Adding the guarded model's SQL from `graph.nodes` is the obvious next improvement
- **One hardcoded test** — generalising across all failing tests via `graph.nodes` iteration is the next structural step
- **No new/recurring/regressed classification** — the history table supports it; the view isn't written
- **No Core/Fusion CI matrix**

## Relationship to dbt-sentinel

Not a replacement — a second distribution for a different constraint.

| | [dbt-sentinel](https://github.com/qraza/dbt-sentinel) (Python) | This (dbt package) |
|---|---|---|
| Runs | Anywhere — any warehouse, any CI | Snowflake only |
| Install | `pip install dbt-sentinel` | `packages.yml` |
| API key | Required | None |
| Data leaves warehouse | Yes (capped row sample) | **No** |
| Structured output | Parsed from text | Enforced at generation |
| Evidence | Compiled SQL + sampled rows | Failing rows (+ `graph.nodes` metadata) |
| Calibration testing | Eval harness, 6 fixtures × 3 runs | Inherits the prompt; harness not yet ported |
| Deployable in dbt Cloud | ✗ (can't `pip install` into a job) | ✓ |

The Python version remains the portable, measurable one and carries the evaluation harness. This is the version for teams who can't send rows outside the warehouse and want zero-install adoption.
