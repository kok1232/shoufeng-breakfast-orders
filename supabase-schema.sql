-- 壽豐早點團體訂餐 Supabase schema
-- 使用方式：到 Supabase 專案的 SQL Editor，整份貼上後執行。

create extension if not exists pgcrypto;

create table if not exists public.group_orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique,
  menu_type text not null check (menu_type in ('weekday', 'holiday')),
  owner_name text not null,
  owner_phone text not null,
  pickup_date date not null,
  pickup_time time not null,
  delivery_type text not null default '到店自取',
  order_note text not null default '',
  min_qty integer not null default 10 check (min_qty > 0),
  min_amount integer not null default 500 check (min_amount >= 0),
  locked boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.order_people (
  id uuid primary key default gen_random_uuid(),
  group_order_id uuid not null references public.group_orders(id) on delete cascade,
  person_name text not null,
  note text not null default '無',
  created_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_person_id uuid not null references public.order_people(id) on delete cascade,
  item_name text not null,
  unit_price integer not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create index if not exists group_orders_order_code_idx on public.group_orders(order_code);
create index if not exists order_people_group_order_id_idx on public.order_people(group_order_id);
create index if not exists order_items_order_person_id_idx on public.order_items(order_person_id);

alter table public.group_orders enable row level security;
alter table public.order_people enable row level security;
alter table public.order_items enable row level security;

revoke all on public.group_orders from anon, authenticated;
revoke all on public.order_people from anon, authenticated;
revoke all on public.order_items from anon, authenticated;

create or replace function public.make_order_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1 from public.group_orders where order_code = candidate
    );
  end loop;
  return candidate;
end;
$$;

create or replace function public.create_group_order(
  p_menu_type text,
  p_owner_name text,
  p_owner_phone text,
  p_pickup_date date,
  p_pickup_time time,
  p_delivery_type text,
  p_order_note text,
  p_min_qty integer,
  p_min_amount integer
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
begin
  if p_menu_type not in ('weekday', 'holiday') then
    raise exception 'menu_type must be weekday or holiday';
  end if;

  new_code := public.make_order_code();

  insert into public.group_orders (
    order_code,
    menu_type,
    owner_name,
    owner_phone,
    pickup_date,
    pickup_time,
    delivery_type,
    order_note,
    min_qty,
    min_amount
  ) values (
    new_code,
    p_menu_type,
    nullif(trim(p_owner_name), ''),
    nullif(trim(p_owner_phone), ''),
    p_pickup_date,
    p_pickup_time,
    coalesce(nullif(trim(p_delivery_type), ''), '到店自取'),
    coalesce(left(trim(p_order_note), 80), ''),
    greatest(coalesce(p_min_qty, 10), 1),
    greatest(coalesce(p_min_amount, 500), 0)
  );

  return new_code;
end;
$$;

create or replace function public.get_group_order(p_order_code text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with target_order as (
    select *
    from public.group_orders
    where order_code = upper(trim(p_order_code))
    limit 1
  ),
  people_json as (
    select
      p.group_order_id,
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'person_name', p.person_name,
          'note', p.note,
          'created_at', p.created_at,
          'items', coalesce(items.items, '[]'::jsonb)
        )
        order by p.created_at
      ) as people
    from public.order_people p
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'item_name', i.item_name,
          'unit_price', i.unit_price,
          'quantity', i.quantity
        )
        order by i.created_at
      ) as items
      from public.order_items i
      where i.order_person_id = p.id
    ) items on true
    group by p.group_order_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'order', jsonb_build_object(
          'order_code', o.order_code,
          'menu_type', o.menu_type,
          'owner_name', o.owner_name,
          'owner_phone', o.owner_phone,
          'pickup_date', o.pickup_date,
          'pickup_time', left(o.pickup_time::text, 5),
          'delivery_type', o.delivery_type,
          'order_note', o.order_note,
          'min_qty', o.min_qty,
          'min_amount', o.min_amount,
          'locked', o.locked,
          'created_at', o.created_at
        ),
        'people', coalesce(pj.people, '[]'::jsonb)
      )
      from target_order o
      left join people_json pj on pj.group_order_id = o.id
    ),
    '{}'::jsonb
  );
$$;

create or replace function public.add_order_person(
  p_order_code text,
  p_person_name text,
  p_note text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_order public.group_orders%rowtype;
  new_person_id uuid;
  item jsonb;
begin
  select *
  into target_order
  from public.group_orders
  where order_code = upper(trim(p_order_code))
  limit 1;

  if target_order.id is null then
    raise exception '找不到訂單';
  end if;

  if target_order.locked then
    raise exception '訂單已截止鎖定';
  end if;

  if nullif(trim(p_person_name), '') is null then
    raise exception '請填點餐人姓名';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception '請至少選一項餐點';
  end if;

  insert into public.order_people (group_order_id, person_name, note)
  values (
    target_order.id,
    left(trim(p_person_name), 40),
    coalesce(nullif(left(trim(p_note), 20), ''), '無')
  )
  returning id into new_person_id;

  for item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (
      order_person_id,
      item_name,
      unit_price,
      quantity
    ) values (
      new_person_id,
      left(item->>'item_name', 60),
      greatest((item->>'unit_price')::integer, 0),
      greatest((item->>'quantity')::integer, 1)
    );
  end loop;

  return new_person_id;
end;
$$;

create or replace function public.lock_group_order(
  p_order_code text,
  p_owner_phone text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.group_orders
  set locked = true
  where order_code = upper(trim(p_order_code))
    and owner_phone = trim(p_owner_phone);

  if not found then
    raise exception '訂單不存在，或主訂餐人電話不正確';
  end if;

  return true;
end;
$$;

grant execute on function public.create_group_order(text, text, text, date, time, text, text, integer, integer) to anon, authenticated;
grant execute on function public.get_group_order(text) to anon, authenticated;
grant execute on function public.add_order_person(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.lock_group_order(text, text) to anon, authenticated;

