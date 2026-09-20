{{ config(materialized='view') }}

select
    test_unique_id,
    test_name,
    test_type,
    guarded_model,
    failure_count,
    'You are diagnosing a failing dbt test. Ground every claim in the evidence below.'
    || '\n\nRULES:'
    || '\n1. Ground every statement in the evidence provided.'
    || '\n2. If the evidence is insufficient, say so plainly and set confidence to "low".'
    || '\n   Do not invent tables, columns or values.'
    || '\n3. If the evidence supports more than one plausible explanation (the data may be'
    || '\n   wrong, OR the test expectation may be stale), name the competing explanations'
    || '\n   and set confidence to "low". Reserve "high" for when alternatives are ruled out.'
    || '\n4. Respond as a JSON object with keys: root_cause, suggested_fix, confidence, evidence.'
    || '\n\nTEST: '        || test_name
    || '\nTEST TYPE: '     || test_type
    || '\nGUARDED MODEL: ' || guarded_model
    || '\nFAILING ROWS: '  || failure_count::varchar
    || '\n\nSQL OF THE TEST:\n' || test_sql
    || '\n\nSQL OF THE GUARDED MODEL:\n' || model_sql
    || '\n\nSAMPLE OF FAILING ROWS (JSON):\n' || failing_rows
        as prompt_text
from {{ ref('sentinel__failures') }}