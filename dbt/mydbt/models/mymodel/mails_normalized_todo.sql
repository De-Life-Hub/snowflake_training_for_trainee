{{ config(
    materialized='table',
    schema='NORMALIZED_TODO'
) }}

WITH labels AS (
    SELECT ARRAY_AGG(LABEL) WITHIN GROUP (ORDER BY SORT_ORDER) AS label_array
    FROM {{ ref('classify_text_labels_todo') }}
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
    FROM {{ source('raw', 'MAILS_RAW') }}
),

keywords_extracted AS (
    SELECT
        MESSAGE_ID,
        SUBJECT,
        FROM_EMAIL,
        RECEIVED_AT,
        body_trimmed,
        SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
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

-- 1. ここでAIの各種スコアやカテゴリの生データを一度計算します（元コードのロジックを維持）
ai_calculated AS (
    SELECT
        k.MESSAGE_ID,
        k.SUBJECT,
        k.FROM_EMAIL,
        k.RECEIVED_AT,
        SNOWFLAKE.CORTEX.SUMMARIZE(k.body_trimmed) AS summary,
        TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
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

-- 2. 最後に、画像に合わせた「日本語の列名」を整えつつ、TODOのみに絞り込みます
SELECT
    -- 画像の「期日」に相当する列 (受信日時を日付の形式に整える)
    TO_VARCHAR(RECEIVED_AT, 'YYYY/MM/DD') AS "期日",
    
    -- 画像の「TODO」に相当する列 (メールの件名を表示)
    SUBJECT AS "TODO", 
    
    -- 画像の「完了 / 未完了」に相当する列 (初期データは一律 '未完了' とします)
    '未完了' AS "完了 / 未完了",
    
    -- 画像の「優先度」に相当する列 (ネガティブな内容＝至急対応なら星2つ、それ以外は星1つ)
    CASE 
        WHEN sentiment_score <= -0.3 THEN '★★'
        ELSE '★'
    END AS "優先度",

    -- 【裏側のデータ用】元の列名もテーブルの互換性のために残しておきます
    MESSAGE_ID,
    SUBJECT,
    FROM_EMAIL,
    RECEIVED_AT,
    TRUE AS AI_PROCESSED,
    summary AS AI_SUMMARY,
    CASE
        WHEN category_raw NOT IN (
            SELECT LABEL FROM {{ this.database }}.NORMALIZED_TODO.CLASSIFY_TEXT_LABELS_TODO
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
FROM ai_calculated
WHERE category_raw = 'TODO' 
   OR category_raw = 'TODOアプリ'


-- SELECT
--     MESSAGE_ID,
--     SUBJECT, -- TODO:メールの件名を表示する列を定義してください。
--     FROM_EMAIL,
--     RECEIVED_AT,
--     TRUE AS AI_PROCESSED,
--     summary AS AI_SUMMARY,
--     CASE
--         WHEN category_raw NOT IN (
--             SELECT LABEL FROM {{ this.database }}.NORMALIZED_TODO.CLASSIFY_TEXT_LABELS_TODO -- {{ ref('classify_text_labels_todo') }}
--         ) THEN 'その他'
--         ELSE category_raw
--     END AS AI_CATEGORY,
--     CASE -- SENTIMENT 関数が返す sentiment_score の幅（範囲）は、-1から 1までの間。0はニュートラル。

--         WHEN sentiment_score >= 0.3 THEN 'positive'
--         WHEN sentiment_score <= -0.3 THEN 'negative'
--         ELSE 'neutral' 
--     END AS AI_SENTIMENT, -- TODO: 感情判定の結果を、文字列として格納する列を定義してください。
--     keywords AS AI_KEYWORDS,
--     OBJECT_CONSTRUCT(
--         'summary', summary,
--         'category', category_raw,
--         'sentiment_score', sentiment_score,
--         'keywords', keywords
--     ) AS AI_RAW_RESULT,
--     CURRENT_TIMESTAMP() AS NORMALIZED_AT
-- FROM ai_processed