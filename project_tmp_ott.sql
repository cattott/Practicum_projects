## Исследование поведенческих факторов, влияющих на приобретение внутриигровой валюты 
* Цель проекта — изучить влияние характеристик игроков и их игровых персонажей на покупку внутриигровой валюты «райские лепестки», 
 а также оценить активность игроков при совершении внутриигровых покупок.

Поставленные ad-hoc задачи: изучить активность игроков при покупке эпических предметов в разрезе разных рас персонажей.
	 
-- Исследовательский анализ данных
-- Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT 
	COUNT(id) AS total_users,
	SUM(payer) AS payers,
	ROUND(AVG(payer), 3) AS users_share
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT 
	race,
	COUNT(id) AS total_users,
	SUM(payer) AS payers,
	ROUND(AVG(payer), 3) AS payers_share
FROM fantasy.users 
JOIN fantasy.race USING(race_id)
GROUP BY race
ORDER BY payers_share DESC;

-- Задача 2. Исследование внутриигровых покупок
-- Статистические показатели по полю amount:
SELECT
	COUNT(*) AS total_events,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	AVG(amount)::numeric(5, 2) AS avg_amount,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY amount) AS mod,
	STDDEV(amount)::numeric(6, 2) AS stand_dev
FROM fantasy.events;
-- Статистические показатели по полю amount, исключая нулевые покупки:
SELECT
	COUNT(*) AS total_events,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	AVG(amount)::numeric(5, 2) AS avg_amount,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY amount) AS mod,
	STDDEV(amount)::numeric(6, 2) AS stand_dev
FROM fantasy.events
WHERE amount != 0;

-- 2.2: Аномальные нулевые покупки:
SELECT
	COUNT(*) AS total_events,
	COUNT(*) FILTER(WHERE amount = '0') AS null_events,
	COUNT(*) FILTER(WHERE amount = '0') / COUNT(*)::float AS events_share
FROM fantasy.events;

-- Запрос для определения предметов, купленных за 0, и количества игроков, которые совершили данные покупки:
SELECT 
	game_items,
	id,
	COUNT(*) AS amt
FROM fantasy.events AS e 
JOIN fantasy.items AS i ON e.item_code = i.item_code 
WHERE amount = 0
GROUP BY game_items, id 
ORDER BY id;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
WITH users_events AS (
	SELECT 
		id,
		COUNT(*) AS total_events_per_user,
		SUM(amount) AS total_amount_per_user
	FROM fantasy.events
	WHERE amount != '0'
	GROUP BY id
)
	SELECT
		CASE 
			WHEN payer = '0'
				THEN 'non-payers'
			ELSE 'payers'
		END AS payer_category,
		COUNT(ue.id) AS total_users,
		(SUM(total_events_per_user) / COUNT(ue.id))::numeric(4, 2) AS avg_events_per_user,
		(SUM(total_amount_per_user) / COUNT(ue.id))::numeric(7, 2) AS avg_amount_per_user
	FROM fantasy.users AS u
	LEFT JOIN users_events AS ue ON u.id = ue.id
	GROUP BY payer;

-- 2.4: Популярные эпические предметы:
WITH total_item_amt AS (
    SELECT
        item_code,
        COUNT(*) AS items_amt,
        COUNT(*)::float / SUM(COUNT(*)) OVER() AS items_share,
    	(COUNT(DISTINCT id)::float / (SELECT COUNT(DISTINCT id) FROM fantasy.events)) AS total_us_share    	
    FROM fantasy.events
    WHERE amount != '0'
    GROUP BY item_code
)
SELECT 
	game_items,
	items_amt,
	items_share,
	total_us_share
FROM total_item_amt AS tia
JOIN fantasy.items AS i ON tia.item_code = i.item_code
ORDER BY total_us_share DESC;

-- Решение ad hoc-задач
-- Зависимость активности игроков от расы персонажа:
WITH total_users_race AS (
	SELECT 
		race_id,
		COUNT(id) AS total_users
	FROM fantasy.users
	GROUP BY race_id
),
payers_users AS (
	SELECT 
		u.race_id,
		COUNT(DISTINCT e.id) AS event_users,
		COUNT(DISTINCT e.id) FILTER(WHERE u.payer = '1')::float / COUNT(DISTINCT e.id) FILTER(WHERE e.amount != 0) AS payer_user_share
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u ON e.id = u.id
	WHERE e.amount != 0
	GROUP BY u.race_id),
users_activity AS (
	SELECT 
		race_id,
		COUNT(DISTINCT e.id) AS users,
		COUNT(e.transaction_id) AS total_transactions,
		SUM(e.amount) AS total_transactions_sum,
		AVG(e.amount::numeric) AS avg_transaction_amt
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u ON e.id = u.id
	GROUP BY race_id)
SELECT 
	r.race,
	tur.total_users,
	pu.event_users,
	(pu.event_users::float / tur.total_users)::numeric(4, 3) AS event_users_share,
	pu.payer_user_share::NUMERIC(4, 3),
	(ua.total_transactions::float / ua.users)::NUMERIC(6, 3) AS avg_transactions,
	(ua.total_transactions_sum::float / ua.users)::numeric(7, 2) AS avg_transaction,
	ua.avg_transaction_amt::numeric(5, 2)
FROM total_users_race AS tur
JOIN payers_users AS pu ON tur.race_id = pu.race_id 
JOIN users_activity AS ua ON pu.race_id = ua.race_id
JOIN fantasy.race AS r ON ua.race_id = r.race_id
ORDER BY event_users_share DESC;

-- Частота покупок
WITH days_between AS (
	SELECT 
		id,
		date_f,
		date_l,
		date_l::date - date_f::date AS days_between
	FROM (SELECT 
		id,
		date AS date_l,
		LAG(date, 1, date) OVER(PARTITION BY id ORDER BY date) AS date_f
		FROM fantasy.events
		WHERE amount != '0') AS f_l_days),
total_events AS (
	SELECT 
		db.id,
		u.payer,
		db.total_events,
		avg_days_between
	FROM 
	(SELECT 
		id,
		COUNT(*) AS total_events,
		ROUND(AVG(days_between), 2) AS avg_days_between
	FROM days_between
	GROUP BY id
	HAVING COUNT(*) >= 25) AS db
	JOIN fantasy.users AS u ON db.id = u.id	
),
categories AS ( 
	SELECT 
		*,
		NTILE(3) OVER(ORDER BY avg_days_between) AS category
	FROM total_events
)
SELECT 
	CASE 
		WHEN category = '1'
			THEN 'высокая частота'
		WHEN category = '2'
			THEN 'средняя частота'
		ELSE 'низкая частота'
	END AS category,
	COUNT(id) AS total_users,
	COUNT(id) FILTER(WHERE payer = '1') AS payer_users,
	COUNT(id) FILTER(WHERE payer = '1')::float / COUNT(id) AS payers_share,
	AVG(total_events) AS avg_events,
	AVG(avg_days_between) AS avg_days
FROM categories

GROUP BY category;

* Выводы исследовательского анализа: 
-- Доля платящих игроков занимает около 18% от всех игроков, зарегистрированных в игре. Зависимость между покупкой валюты 
«райские лепестки», сегментом игрока и характеристикой персонажа незначительна. В связи с чем можно внедрить акционные предложения 
для платящих игроков, чтобы увеличить долю платящих игроков.
-- Существует большой размах между стоимостью эпических предметов, при этом большое количество предметов были куплены всего 1 раз, 
в связи с чем можно пересмотреть необходимость некоторых эпических предметов, а также их стоимость.
-- Также необходимо обратить внимание на аномальные покупки с нулевой стоимостью (могут быть сбои в работе программы), 
так как все случаи купленных предметов за 0 пришлись на один и тот же эпический предмет “Book of Legends”, а большая часть 
аномальных покупок была совершена одним игроком.
-- Наибольшее количество покупок в среднем совершают игроки, выбравшие расу “Люди” (121 покупка) и “Ангелы” (106 покупок), 
что может указывать на большую необходимость в эпических предметах в ходе игры для данных рас.
