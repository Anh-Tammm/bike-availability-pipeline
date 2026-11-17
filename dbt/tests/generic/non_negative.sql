{# Fails if any row has a negative value in the tested column #}
{% test non_negative(model, column_name) %}
select {{ column_name }}
from {{ model }}
where {{ column_name }} < 0
{% endtest %}
