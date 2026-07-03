{% macro load_mails_raw() %}
    {% set db = env_var('DBT_DATABASE') %}
    {% set copy_sql %}
        COPY INTO {{ db }}.RAW.MAILS_RAW
        FROM @{{ db }}.RAW.ST_S3_MAIL
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    {% endset %}

    {{ log("Executing: " ~ copy_sql, info=True) }}
    {% do run_query(copy_sql) %}
    {{ log("load_mails_raw: COPY INTO completed.", info=True) }}
{% endmacro %}