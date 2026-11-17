-- =====================================================================
-- omnisoft BI : αγορές, εισπράξεις, κανόνες ειδοποιήσεων + demo δεδομένα
-- =====================================================================
begin;

create table public.bi_purchases (
  id           bigserial primary key,
  tenant_id    uuid not null references public.tenants(id),
  doc_date     date not null,
  supplier     text not null,
  item_code    text,
  item         text,
  category     text,
  brand        text,
  qty          numeric(14,3),
  net_amount   numeric(14,2)
);
create index bi_purchases_tenant_date on public.bi_purchases (tenant_id, doc_date);

create table public.bi_receipts (
  id              bigserial primary key,
  tenant_id       uuid not null references public.tenants(id),
  doc_date        date not null,
  customer        text not null,
  customer_group  text,
  region          text,
  salesperson     text,
  method          text,
  amount          numeric(14,2)
);
create index bi_receipts_tenant_date on public.bi_receipts (tenant_id, doc_date);

create table public.bi_alert_rules (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null default public.current_tenant_id() references public.tenants(id),
  name        text not null,
  type        text not null,
  params      jsonb not null default '{}',
  channels    jsonb not null default '{"app": true, "email": false}',
  recipients  text,
  frequency   text not null default 'daily' check (frequency in ('instant','daily','weekly')),
  active      boolean not null default true,
  created_by  uuid default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now()
);

alter table public.bi_purchases   enable row level security;
alter table public.bi_receipts    enable row level security;
alter table public.bi_alert_rules enable row level security;

create policy tenant_read on public.bi_purchases for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_read on public.bi_receipts  for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_all  on public.bi_alert_rules for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

grant select on public.bi_purchases, public.bi_receipts to authenticated;
grant select, insert, update, delete on public.bi_alert_rules to authenticated;
grant all on public.bi_purchases, public.bi_receipts, public.bi_alert_rules to service_role;
grant usage, select on all sequences in schema public to authenticated;

select setseed(0.17);

-- Αγορές: ανά είδος και μήνα, από τον προμηθευτή της μάρκας
insert into public.bi_purchases (tenant_id, doc_date, supplier, item_code, item, category, brand, qty, net_amount)
select tenant_id,
       date_trunc('month', doc_date)::date + 4,
       brand || case when tenant_id = '11111111-1111-1111-1111-111111111111' then ' Α.Ε.' else ' Ε.Π.Ε.' end,
       item_code, max(item), max(category), brand,
       round(sum(qty) * (0.92 + random() * 0.2)),
       round((sum(cost_amount) * (0.92 + random() * 0.2))::numeric, 2)
from public.bi_sales
group by tenant_id, date_trunc('month', doc_date), item_code, brand;

-- Εισπράξεις: ανά πελάτη και μήνα, με καθυστέρηση ανάλογη των ημερών είσπραξης
with m as (
  select s.tenant_id, s.customer, max(s.customer_group) grp, max(s.region) region, max(s.salesperson) sp,
         date_trunc('month', s.doc_date)::date as mon, sum(s.net_amount) * 1.24 as gross,
         coalesce(max(b.avg_days), 45) as days
  from public.bi_sales s
  left join public.bi_customer_balances b on b.tenant_id = s.tenant_id and b.customer = s.customer
  group by s.tenant_id, s.customer, date_trunc('month', s.doc_date)
)
insert into public.bi_receipts (tenant_id, doc_date, customer, customer_group, region, salesperson, method, amount)
select tenant_id,
       (mon + make_interval(days => days))::date,
       customer, grp, region, sp,
       (array['Τραπεζική κατάθεση','Τραπεζική κατάθεση','Επιταγή','Μετρητά'])[1 + floor(random() * 4)::int],
       round((gross * case when days > 90 then 0.7 when days > 60 then 0.85 else 0.97 end * (0.9 + random() * 0.15))::numeric, 2)
from m
where (mon + make_interval(days => days))::date <= '2026-10-31';

-- Προκαθορισμένες ειδοποιήσεις ανά επιχείρηση
insert into public.bi_alert_rules (tenant_id, name, type, params, channels, recipients, frequency, active, created_by)
select t.id, r.name, r.type, r.params::jsonb, r.channels::jsonb, null, r.freq, true, null
from public.tenants t
cross join (values
  ('Πελάτες σε καθυστέρηση', 'overdue', '{"days": 90, "min_amount": 1000}', '{"app": true, "email": true}', 'daily'),
  ('Πτώση περιθωρίου κατηγορίας', 'margin_drop', '{"points": 2}', '{"app": true, "email": false}', 'weekly'),
  ('Μεγάλος πελάτης μειώνει αγορές', 'customer_drop', '{"pct": 15, "min_sales": 100000}', '{"app": true, "email": true}', 'weekly')
) as r(name, type, params, channels, freq)
where t.id in ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

commit;

select 'purchases' t, count(*) from public.bi_purchases
union all select 'receipts', count(*) from public.bi_receipts
union all select 'alert_rules', count(*) from public.bi_alert_rules;
