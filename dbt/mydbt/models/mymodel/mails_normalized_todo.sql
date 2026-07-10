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

ai_processed AS (
-- (ここまでは元のコードのままでOKです)

SELECT
    -- 1. 画像の「期日」に相当する列 (受信日時を日付の形式に整える)
    TO_VARCHAR(RECEIVED_AT, 'YYYY/MM/DD') AS "期日",
    
    -- 2. 画像の「TODO」に相当する列 (メールの件名または要約を表示)
    SUBJECT AS "TODO", 
    
    -- 3. 画像の「完了 / 未完了」に相当する列
    -- ※まだ作成されたばかりなので、初期値として一律 '未完了' にするか、
    --   AI判定の状況（AI_PROCESSEDがTRUEなら完了など）に合わせて分岐させます。
    CASE 
        WHEN AI_PROCESSED = TRUE THEN '完了'
        ELSE '未完了'
    END AS "完了 / 未完了",
    
    -- 4. 画像の「優先度」に相当する列
    -- ※ここでは例として、AIの感情（AI_SENTIMENT）が 'negative'（至急対応が必要そうなもの）
    --   であれば星2つ、それ以外は星1つのように動的に星（★）マークを作っています。
    CASE 
        WHEN sentiment_score <= -0.3 THEN '★★'
        ELSE '★'
    END AS "優先度",

    -- 【裏側のデータ用】Streamlitの詳細表示機能などでも使うため、元の列もそのまま残しておきます
    MESSAGE_ID,
    FROM_EMAIL,
    RECEIVED_AT,
    AI_PROCESSED,
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
FROM ai_processed

-- 💡【超重要】ここでカテゴリが「TODO」のものだけに絞り込みます
-- ※AIの出力揺れに対応するため、念のため「category_raw」をチェックします
WHERE category_raw = 'TODO' 
   OR category_raw = 'TODOアプリ'
)

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