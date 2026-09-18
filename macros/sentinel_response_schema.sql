{% macro sentinel_response_schema() %}
{{ return({
  'type': 'json',
  'schema': {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'root_cause':    {'type': 'string'},
      'suggested_fix': {'type': 'string'},
      'confidence':    {'type': 'string', 'enum': ['high','medium','low']},
      'evidence':      {'type': 'string'}
    },
    'required': ['root_cause','suggested_fix','confidence','evidence']
  }
}) }}
{% endmacro %}