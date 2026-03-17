-- Stage

create database hotel_db;

create or replace file format ff_csv
    type = 'CSV'
    field_optionally_enclosed_by = '"'
    skip_header = 1
    null_if = ('NULL', 'null', '')

create or replace stage stg_hotel_bookings
    file_format = ff_csv;

---------------------------------------------------------------
-- Bronze

create table bronze_hotel_booking ( 

--on the first stage, it is easier to put all the data as string

    booking_id string,
    hotel_id string,
    hotel_city string,
    customer_id string,
    customer_name string,
    customer_email string,
    check_in_date string,
    check_out_date string,
    room_type string,
    num_guests string,
    total_amount string,
    currency string,
    booking_status string
);

copy into bronze_hotel_booking
from @stg_hotel_bookings
file_format = (format_name = ff_csv)
on_error = 'CONTINUE';

select * from bronze_hotel_booking limit 50;

-------------------------------------------------------------
-- Silver

create table silver_hotel_booking (
    booking_id varchar,
    hotel_id varchar,
    hotel_city varchar,
    customer_id varchar,
    customer_name varchar,
    customer_email varchar,
    check_in_date date,
    check_out_date date,
    room_type varchar,
    num_guests integer,
    total_amount float,
    currency varchar,
    booking_status varchar
)

--check if there is any weird data to clean

select customer_email 
from bronze_hotel_booking
where not (customer_email like '%@%.%')
    or customer_email is null;

select total_amount
from bronze_hotel_booking
where try_to_number(total_amount) < 0; --we use try_to_number incase some row are a weird type so it show null instead of error.

select check_in_date, check_out_date
from bronze_hotel_booking
where try_to_date(check_in_date) > try_to_date(check_out_date);

select distinct booking_status
from bronze_hotel_booking;

insert into silver_hotel_booking
select
    booking_id,
    hotel_id,
    initcap(trim(hotel_city)) as hotel_city, --
    customer_id,
    initcap(trim(customer_name)) as customer_name, --
    case
        when customer_email like '%@%.%' then lower(trim(customer_email)) 
        else null
    end as customer_email,
    try_to_date(ifnull(check_in_date, '')) as check_in_date,
    try_to_date(ifnull(check_out_date, '')) as check_out_date,
    room_type,
    num_guests,
    abs(try_to_number(total_amount)) as total_amount,
    currency,
    case
        when lower(booking_status) in ('confirmeeed', 'confirmd') then 'Confirmed'
        else booking_status
    end as booking_status
    from bronze_hotel_booking
    where
        try_to_date(check_in_date) is not null
        and try_to_date(check_out_date) is not null
        and try_to_date(check_out_date) >= try_to_date(check_in_date); -- we dont assume to swap, if the date is wrong, we just dont want it, dont assume to swap

select * from silver_hotel_booking limit 30;

-------------------------------------------------------------------------------
-- Gold

create table gold_agg_daily_booking as
select
    check_in_date as date,
    count(*) as total_booking,
    sum(total_amount) as total_revenue,
from silver_hotel_booking
group by check_in_date
order by date;

create table gold_city_revenue as
select
    hotel_city,
    sum(total_amount) as total_revenue
from silver_hotel_booking
group by hotel_city
order by total_revenue desc;

create table gold_booking_clean as
select
    booking_id,
    hotel_id,
    hotel_city,
    customer_id,
    customer_name,
    customer_email,
    check_in_date,
    check_out_date,
    room_type,
    num_guests,
    total_amount,
    currency,
    booking_status
from silver_hotel_booking;

select * from gold_agg_daily_booking limit 30;

select * from gold_city_revenue limit 30;
    
    
