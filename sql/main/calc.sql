create table if not exists results ("id" int, "response" text);
truncate table results;
--select count(*) from results
--select * from results order by id desc limit 200
--select * from results order by id asc limit 200
--определение основных KPI
--
with 
--кол-во людей в брони
num_people_in_book as (select count(ticket_no) num_people, book_ref from tickets group by book_ref)
--макс кол-во людей в брони
,max_num as (select max(num_people) "max_num_people" from (select count(t.ticket_no) num_people from bookings b left join tickets t on b.book_ref = t.book_ref group by b.book_ref) as t)
--ср кол-во людей на 1 бронь
,avg_people_book as (select avg(num_people) from (select count(ticket_no) num_people from tickets group by book_ref) as t)
--кол-во людей в брони выше ср кол-ва людей на 1 бронь
,over_avg_book as (select count(*) "num_book_over_avg" from (select count(distinct ticket_no) as "num_people" from tickets group by book_ref) as t where "num_people" > (select * from avg_people_book))
--список бронирований с макс кол-вом людей, человек = passenger_id, т.к. повторяющихся фио в одной брони среди бронирований с макс кол-вом людей также не найдено
,books_with_max_num as (select book_passenger_id, book_ref from (select array_agg(passenger_id order by passenger_id) as book_passenger_id, book_ref, array_length(array_agg(passenger_id),1) "num_people"
						from tickets group by book_ref) as t where "num_people" = (select * from max_num))
--подсчет кол-ва броней на один и тот же список пассажиров среди бронирований с макс кол-вом людей
,pass_ids_num_books as (select book_passenger_id, count(book_ref) "num_same_pass_book" from books_with_max_num group by book_passenger_id)
--кол-во перелетов на бронь (если под кол-вом понимается учитывать дубли, то 24, если не учитывать, то 6)
,num_flights_books as (select t.book_ref, count(tf.flight_id) "num_flight" from tickets t, ticket_flights tf where t.ticket_no = tf.ticket_no group by t.book_ref order by 2 desc)
--кол-во перелетов на пассажира в брони
,num_flights_book_ticket as (select t.book_ref, t.passenger_id, count(flight_id) "num_flight" from tickets t, ticket_flights tf where t.ticket_no = tf.ticket_no group by t.book_ref, t.passenger_id order by 2 desc)
--кол-во перелетов на пассажира (если выбрать ФИО(passenger_name) в качестве пассажира - результат 2423, если ID то результат тот же что и в п6)
,num_flights_ticket as (select t.passenger_id, count(tf.flight_id) "num_flight" from tickets t, ticket_flights tf where t.ticket_no = tf.ticket_no group by t.passenger_id)
--стоимость всех билетов 1го пассажира
,amount_flights_pass_id as (select t.passenger_id, t.passenger_name, t.contact_data, sum(tf.amount) "amount" from tickets t, ticket_flights tf where t.ticket_no = tf.ticket_no group by t.passenger_id, t.passenger_name, t.contact_data)
--общее время полетов на 1 пассажира
,time_flights_pass_id as (select t.passenger_id, t.passenger_name, t.contact_data, sum((extract(epoch from f.actual_arrival) - extract(epoch from f.actual_departure))/3600::decimal) "time_hours" from tickets t join ticket_flights tf on t.ticket_no = tf.ticket_no join flights f on tf.flight_id = f.flight_id where f.status = 'Arrived' group by t.passenger_id, t.passenger_name, t.contact_data)
--список всех городов сообщения
,cities_routes as (select distinct r.arrival_city a_city, r.departure_city b_city from routes r union select distinct r.departure_city a_city, r.arrival_city b_city from routes r)
--список городов и кол-во городов сообщения
,cities_num_routes as (select a.city a_city, count(cr.b_city) "num_b_cities" from airports a left join cities_routes cr on a.city=cr.a_city group by a.city)
--пары городов без реверсных дубликатов и прямого сообщения
,pairs_cities_wo_routes as (select cr.a_city || ' | '|| t.a_city ab_cities, cr.a_city a_city, t.a_city b_city from cities_routes cr cross join (select distinct a_city from cities_routes) as t where cr.a_city < t.a_city except select a_city || ' | '|| b_city ab_cities, a_city, b_city from cities_routes where a_city < b_city)
--модели самолетов и количество рейсов
,num_model_flights as (select model, count(flight_id) "num_flights" from flights f left join aircrafts using(aircraft_code) group by model)
--модели самолетов и количество пассажиров
,num_model_pass as (select a.model, count(ticket_no) "num_ticket" from ticket_flights tf left join flights f using(flight_id) left join aircrafts a using(aircraft_code) where status = 'Arrived' group by a.model)
--запланированное и фактическое время полета
,time_delta as (select extract(epoch from scheduled_arrival)/60::decimal - extract(epoch from scheduled_departure)/60::decimal delta_sched_min, extract(epoch from actual_arrival)/60::decimal - extract(epoch from actual_departure)/60::decimal delta_act_min from flights where status = 'Arrived' group by flight_id)
--города отправления и прибытия с датами отправления
,city_act_dep_date as (select a.city a_city, b.city b_city, f.actual_departure::date dep_date from flights f join airports a on f.departure_airport = a.airport_code join airports b on f.arrival_airport = b.airport_code where f.status = 'Arrived')
--рейсы и их стоимость
,flight_cost as (select tf.flight_id, sum(tf.amount) "cost" from ticket_flights tf join flights f using(flight_id) where f.status = 'Arrived' group by tf.flight_id)
--рейсы и даты
,flight_date as (select f.actual_departure::date dep_date, count(f.flight_id) count_flight from flights f where status = 'Arrived' group by dep_date)
--города отправления с датами отправления и полетами
,city_act_dep_date_flight as (select a.city a_city, date_trunc('month', f.actual_departure)::date dep_month, date_part('days', date_trunc('month', f.actual_departure) + interval '1 month - 1 day') month_num_days, count(f.flight_id) num_flights from flights f join airports a on f.departure_airport = a.airport_code join airports b on f.arrival_airport = b.airport_code where f.status = 'Arrived' group by a_city, dep_month, month_num_days)
--города отправления и прибытия с временем перелета
,city_avg_flight_time as (select a.city a_city, b.city b_city, f.flight_id,(extract(epoch from f.actual_arrival)-extract(epoch from f.actual_departure))/3600::decimal time_flight_hours
	from flights f join airports a on f.departure_airport = a.airport_code join airports b on f.arrival_airport = b.airport_code where f.status = 'Arrived' group by a_city, b_city, flight_id)
--города отправления, среднее время перелета и ранг по убыванию ср времени перелета (ч)
,city_avg_flight_time_rank as (select row_number() over (order by avg(time_flight_hours) desc) ranknum, a_city, avg(time_flight_hours) avg_time_flight from city_avg_flight_time group by a_city order by avg_time_flight desc)
--
--далее insert выборок в таблицу results
insert into results ("id", "response")
--
--секция выборок
--
select * from (
---1-- Вывести максимальное количество человек в одном бронировании
select 1, (select max_num_people from max_num)::text
	union all
---2-- Вывести количество бронирований с количеством людей больше среднего значения людей на одно бронирование
select 2, (select "num_book_over_avg" from "over_avg_book")::text
	union all
---3-- Вывести количество бронирований, у которых состав пассажиров повторялся два и более раза, среди бронирований с максимальным количеством людей (п.1)
--если 2 заменить на 1, то получим всего 23 брони, которые никак не совпадают по составу пассажиров
--select 3, sum(num_same_pass_book)::text from pass_ids_num_books where "num_same_pass_book" >= 2
select 3, coalesce (sum(num_same_pass_book)::text, '0') from pass_ids_num_books where "num_same_pass_book" >= 2
	union all
---4-- Вывести номера брони и контактную информацию по пассажирам в брони (passenger_id, passenger_name, contact_data) с количеством людей в брони = 3
select 4, book_ref || '|' || string_agg(passenger_id || ', ' || passenger_name || ', ' || contact_data, ';' order by passenger_id, passenger_name, contact_data) from tickets where book_ref in (select book_ref from num_people_in_book where num_people =3) group by book_ref  
    union all
---5-- Вывести максимальное количество перелётов на бронь
select 5, max("num_flight")::text from (select * from num_flights_books) as t
	union all
---6-- Вывести максимальное количество перелётов на пассажира в одной брони
select 6, max("num_flight")::text from num_flights_book_ticket
	union all
---7-- Вывести максимальное количество перелётов на пассажира
select 7, max("num_flight")::text from num_flights_ticket
	union all
---8-- Вывести контактную информацию по пассажиру(ам) (passenger_id, passenger_name, contact_data) и общие траты на билеты, для пассажира потратившему минимальное количество денег на перелеты
select 8, t.passenger_id || '|' || t.passenger_name || '|' || t.contact_data  || '|' ||  "amount" from (select * from amount_flights_pass_id) as t where "amount" = (select min("amount") from amount_flights_pass_id)
	union all
---9-- Вывести контактную информацию по пассажиру(ам) (passenger_id, passenger_name, contact_data) и общее время в полётах, для пассажира, который провёл максимальное время в полётах
select 9, passenger_id || '|' || passenger_name || '|' || contact_data  || '|' ||  "time_hours" from (select * from time_flights_pass_id ) as t where "time_hours" = (select max("time_hours") from time_flights_pass_id)
	union all
--10-- Вывести город(а) с количеством аэропортов больше одного
select 10, city::text FROM airports GROUP BY city HAVING COUNT(*) > 1
	union all
--11-- Вывести город(а), у которого самое меньшее количество городов прямого сообщения
select 11, a_city::text from cities_num_routes where "num_b_cities" = (select min("num_b_cities") from cities_num_routes)
	union all
--12-- Вывести пары городов, у которых нет прямых сообщений исключив реверсные дубликаты
select 12, ab_cities from pairs_cities_wo_routes
	union all
--13-- Вывести города, до которых нельзя добраться без пересадок из Москвы?
select 13, case when a_city != 'Москва' then a_city else b_city end city from pairs_cities_wo_routes where a_city = 'Москва' or b_city = 'Москва'
	union all
--14-- Вывести модель самолета, который выполнил больше всего рейсов
select 14, model from num_model_flights where "num_flights" = (select max("num_flights") from num_model_flights)
	union all
--15-- Вывести модель самолета, который перевез больше всего пассажиров
select 15, model from num_model_pass where num_ticket = (select max(num_ticket) from num_model_pass)
	union all
--16-- Вывести отклонение в минутах суммы запланированного времени перелета от фактического по всем перелётам
select 16, sum(delta_sched_min - delta_act_min)::text sched_min_vs_act_min from time_delta
	union all
--17-- Вывести города, в которые осуществлялся перелёт из Санкт-Петербурга 2016-09-13
--на заданную дату вылетов не зарегистрировано, но если взять, к примеру, дату 2017-08-16, то будет 19 городов
select 17, 'не найдено' b_city where not exists(
select b_city from city_act_dep_date where upper(a_city) like '%ПЕТЕРБ%' and dep_date = '2017-08-13' group by b_city) union all 
select 17, b_city from city_act_dep_date where upper(a_city) like '%ПЕТЕРБ%' and dep_date = '2017-08-13' group by b_city
	union all
--18-- Вывести перелёт(ы) с максимальной стоимостью всех билетов
--не очевидно состоявшийся или нет перелет, учел только состоявшиеся
select 18, flight_id::text from flight_cost where cost = (select max(cost) from flight_cost)
	union all
--19-- Выбрать дни в которых было осуществлено минимальное количество перелётов
select 19, dep_date::text from flight_date where count_flight = (select min(count_flight) from flight_date)
	union all
--20-- Вывести среднее количество вылетов в день из Москвы за 09 месяц 2016 года
--если указать дату 2017-08-01 то получим avg = 67 рейсов в день
select 20, '0' avg_per_month where not exists(select num_flights/month_num_days::decimal from city_act_dep_date_flight where upper(a_city) = 'МОСКВА' and dep_month = '2017-08-01')
	union all select 20, (num_flights/month_num_days::decimal)::text from city_act_dep_date_flight where upper(a_city) = 'МОСКВА' and dep_month = '2017-08-01'
--21-- Вывести топ 5 городов у которых среднее время перелета до пункта назначения больше 3 часов
	union all
select 21, a_city from city_avg_flight_time_rank where ranknum <=5

) as t order by 1, 2
