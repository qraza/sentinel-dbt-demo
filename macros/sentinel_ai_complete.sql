{% macro sentinel_ai_complete(prompt_col) %}
  {{ return(adapter.dispatch('sentinel_ai_complete', 'sentinel_demo')(prompt_col)) }}
{% endmacro %}


{% macro default__sentinel_ai_complete(prompt_col) %}
  {{ exceptions.raise_compiler_error(
       "sentinel: no LLM function for adapter '" ~ target.type ~ "'. Supported: snowflake."
  ) }}
{% endmacro %}


{% macro snowflake__sentinel_ai_complete(prompt_col) %}

  {%- if var('sentinel_use_stub', true) -%}

    object_construct(
      'root_cause',    'STUB — prompt was: ' || left({{ prompt_col }}, 200),
      'suggested_fix', 'STUB — no model called.',
      'confidence',    'low',
      'evidence',      'STUB — Cortex unavailable on trial accounts.'
    )

  {%- else -%}

    AI_COMPLETE(
      model            => '{{ var("sentinel_model") }}',
      prompt           => {{ prompt_col }},
      model_parameters => {'temperature': 0, 'max_tokens': {{ var("sentinel_max_tokens") }}},
      response_format  => {{ sentinel_response_schema() }}
    )

  {%- endif -%}

{% endmacro %}