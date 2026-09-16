# sentinel-dbt-demo

Demonstrates a Snowflake-native version of dbt-sentinel: dbt test failures
diagnosed by a model running inside the warehouse, on the dbt Fusion engine.

The Cortex AI_COMPLETE call is **stubbed** — Snowflake trial accounts can't
use Cortex AI functions. Everything else runs for real.

For the working LLM implementation, see github.com/qraza/dbt-sentinel
