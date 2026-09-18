{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with scored as (
    select
        test_unique_id,
        test_name,
        test_type,
        guarded_model,
        failure_count,
        {{ sentinel_ai_complete('prompt_text') }} as verdict
    from {{ ref('sentinel__prompts') }}
)
select
    '{{ invocation_id }}'::varchar   as invocation_id,
    current_timestamp()              as run_started_at,
    test_unique_id,
    test_name,
    test_type,
    guarded_model,
    failure_count,
    verdict:root_cause::varchar      as root_cause,
    verdict:suggested_fix::varchar   as suggested_fix,
    verdict:confidence::varchar      as confidence,
    verdict:evidence::varchar        as evidence
from scored