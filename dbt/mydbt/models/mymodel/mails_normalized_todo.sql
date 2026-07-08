{{ config(
    materialized='table',
    schema='NORMALIZED_TODO'
    -- 新しいTODO用のスキーマへ書き出すように指定
) }}

WITH labels AS (
    SELECT ARRAY_AGG(LABEL) WITHIN GROUP (ORDER BY SORT_ORDER) AS label_array
    -- TODO用のマスタテーブルを参照
    FROM {{ this.database }}.NORMALIZED_TODO.CLASSIFY_TEXT_LABELS
),

trimmed AS (  -- 前処理としてHTMLタグを消して、4000字に切る。
    SELECT
        MESSAGE_ID,
        SUBJECT,
        FROM_EMAIL,
        RECEIVED_AT,
        LEFT(
            REGEXP_REPLACE(BODY_TEXT, '<[^>]+>', ''),
            4000
        ) AS body_trimmed
    -- TODO用の生データが入っているRAW_TODOスキーマから読み込む
    FROM {{ this.database }}.RAW_TODO.MAILS_RAW
),

keywords_extracted AS (
    SELECT
        MESSAGE_ID,
        SUBJECT,
        FROM_EMAIL,
        RECEIVED_AT,
        body_trimmed,
        SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large',
            CONCAT(
                'Extract 3-5 important keywords from the following email. ',
                'Return ONLY a JSON array of strings with no explanation, no preamble, no markdown. ',
                'Example output: ["keyword1", "keyword2", "keyword3"]\n',
                'Subject: ', SUBJECT, '\n',
                'Email: ', body_trimmed
            )
        ) AS keywords
    FROM trimmed
),

ai_processed AS (
    SELECT
        k.MESSAGE_ID,
        k.SUBJECT,
        k.FROM_EMAIL,
        k.RECEIVED_AT,
        SNOWFLAKE.CORTEX.SUMMARIZE(k.body_trimmed) AS summary,
        TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large',
            CONCAT(
                '以下のメール本文を読み、次のカテゴリから最も適切なものを1つだけ答えてください。',
                'カテゴリ名のみ返してください。余分な説明は不要です。\n',
                'カテゴリ: ', ARRAY_TO_STRING(l.label_array, ' / '), '\n',
                'キーワード: ', k.keywords, '\n',
                'メール本文: ', k.body_trimmed
            )
        )) AS category_raw,
        SNOWFLAKE.CORTEX.SENTIMENT(k.body_trimmed) AS sentiment_score,
        k.keywords
    FROM keywords_extracted AS k
    CROSS JOIN labels AS l
)

SELECT
    MESSAGE_ID,
    SUBJECT, 
    FROM_EMAIL,
    RECEIVED_AT,
    TRUE AS AI_PROCESSED,
    summary AS AI_SUMMARY,
    CASE
        -- チェック対象のマスタテーブルも NORMALIZED_TODO を参照
        WHEN category_raw NOT IN (
            SELECT LABEL FROM {{ this.database }}.NORMALIZED_TODO.CLASSIFY_TEXT_LABELS
        ) THEN 'その他'
        ELSE category_raw
    END AS AI_CATEGORY,
    CASE 
        WHEN sentiment_score >= 0.3 THEN 'positive'
        WHEN sentiment_score <= -0.3 THEN 'negative'
        ELSE 'neutral' 
    END AS AI_SENTIMENT, 
    keywords AS AI_KEYWORDS,
    OBJECT_CONSTRUCT(
        'summary', summary,
        'category', category_raw,
        'sentiment_score', sentiment_score,
        'keywords', keywords
    ) AS AI_RAW_RESULT,
    CURRENT_TIMESTAMP() AS NORMALIZED_AT
FROM ai_processed