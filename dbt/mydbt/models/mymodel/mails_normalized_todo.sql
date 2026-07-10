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

ai_calculated AS (
    SELECT
        k.MESSAGE_ID,
        k.SUBJECT,
        k.FROM_EMAIL,
        k.RECEIVED_AT,
        k.body_trimmed,
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
        k.keywords,

        -- 💡【新規追加】AIに本文から「具体的なTODO内容」を抽出させる指示
        TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
            CONCAT(
                '以下のメール本文から、やるべきこと（TODOタスク）を1文で簡潔に抽出してください。',
                '余計な解説や挨拶、前置きは一切含めず、タスク内容のみを出力してください。\n',
                'メール本文: ', k.body_trimmed
            )
        )) AS todo_task_extracted,

        -- 💡【新規追加】AIに本文から「期限の日付」を抽出させる指示
        TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
            CONCAT(
                '以下のメール本文から、タスクの期限・期日（日付）を抽出して「YYYY-MM-DD」の形式のみで返してください。',
                'もし本文中に明確な期限が書かれていない場合は、メールの受信日である「', TO_DATE(k.RECEIVED_AT, 'YYYY-MM-DD'), '」をそのまま返してください。',
                '余計な文字や説明、マークダウンは絶対に含めず、日付の文字列（例: 2026-07-07）のみを返してください。\n',
                'メール本文: ', k.body_trimmed
            )
        )) AS todo_deadline_extracted
    FROM keywords_extracted AS k
    CROSS JOIN labels AS l
)

-- 最後に、画面に表示したい4つの列（期日、TODO、完了 / 未完了、優先度）のみに絞り込みます
SELECT
    -- 1. AIが抽出した期限を日付型（または文字）にして「期日」とする
    TRY_TO_DATE(todo_deadline_extracted) AS "期日",
    
    -- 2. AIが抽出したタスクの本文内容を「TODO」とする
    todo_task_extracted AS "TODO", 
    
    -- 3. 「完了 / 未完了」の列
    '未完了' AS "完了 / 未完了",
    
    -- 4. 「優先度」の列
    CASE 
        WHEN sentiment_score <= -0.3 THEN '★★'
        ELSE '★'
    END AS "優先度"

FROM ai_calculated
WHERE category_raw = 'TODO' 
   OR category_raw = 'TODOアプリ'