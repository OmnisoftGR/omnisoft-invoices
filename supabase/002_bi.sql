-- =====================================================================
-- omnisoft BI : σχήμα + demo δεδομένα για 2 εικονικές επιχειρήσεις
-- =====================================================================
begin;

-- ---------- Πίνακες ----------
create table public.bi_sales (
  id              bigserial primary key,
  tenant_id       uuid not null references public.tenants(id),
  doc_date        date not null,
  customer        text not null,
  customer_group  text,
  region          text,
  salesperson     text,
  item_code       text,
  item            text,
  category        text,
  brand           text,
  qty             numeric(14,3),
  net_amount      numeric(14,2),
  cost_amount     numeric(14,2)
);
create index bi_sales_tenant_date on public.bi_sales (tenant_id, doc_date);

create table public.bi_customer_balances (
  tenant_id  uuid not null references public.tenants(id),
  customer   text not null,
  balance    numeric(14,2),
  d0_30      numeric(14,2),
  d31_60     numeric(14,2),
  d61_90     numeric(14,2),
  d90p       numeric(14,2),
  avg_days   int,
  primary key (tenant_id, customer)
);

create table public.bi_stock (
  tenant_id  uuid not null references public.tenants(id),
  item_code  text not null,
  item       text,
  category   text,
  qty        numeric(14,3),
  value      numeric(14,2),
  last_sale  date,
  primary key (tenant_id, item_code)
);

create table public.bi_insights (
  id          bigserial primary key,
  tenant_id   uuid not null references public.tenants(id),
  created_at  timestamptz not null default now(),
  severity    text not null check (severity in ('bad','warn','good')),
  tag         text,
  title       text not null,
  body        text,
  action      text
);

create table public.bi_reports (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null default public.current_tenant_id() references public.tenants(id),
  name        text not null,
  kind        text not null default 'pivot' check (kind in ('pivot','dashboard')),
  config      jsonb not null,
  created_by  uuid default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now()
);

-- ---------- RLS ----------
alter table public.bi_sales             enable row level security;
alter table public.bi_customer_balances enable row level security;
alter table public.bi_stock             enable row level security;
alter table public.bi_insights          enable row level security;
alter table public.bi_reports           enable row level security;

create policy tenant_read on public.bi_sales             for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_read on public.bi_customer_balances for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_read on public.bi_stock             for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_read on public.bi_insights          for select to authenticated using (tenant_id = public.current_tenant_id());
create policy tenant_all  on public.bi_reports for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

grant select on public.bi_sales, public.bi_customer_balances, public.bi_stock, public.bi_insights to authenticated;
grant select, insert, update, delete on public.bi_reports to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant all on public.bi_sales, public.bi_customer_balances, public.bi_stock, public.bi_insights, public.bi_reports to service_role;

-- ---------- Demo επιχειρήσεις ----------
insert into public.tenants (id, name, afm) values
  ('11111111-1111-1111-1111-111111111111', 'Demo Χονδρική Τροφίμων Α.Ε.', '000000001'),
  ('22222222-2222-2222-2222-222222222222', 'Demo Οικοδομικά Υλικά Ο.Ε.',  '000000002');

-- ---------- Demo πωλήσεις (Ιαν 2025 – Οκτ 2026) ----------
select setseed(0.42);

with t(tid, k, base) as (values
  ('11111111-1111-1111-1111-111111111111'::uuid, 'food',  5200),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'build', 3600)
),
cust(k, customer, grp, region, sp, weight, trend) as (values
  ('food','Σούπερ Μάρκετ Αλώνι','Σούπερ μάρκετ','Ηράκλειο','Γ. Μανουσάκης',1.6, 0.10),
  ('food','Ξενοδοχείο Γαλάζια Ακτή','HoReCa','Χερσόνησος','Μ. Δασκαλάκη',1.4, 0.06),
  ('food','Mini Market Δαφνές','Σούπερ μάρκετ','Ηράκλειο','Γ. Μανουσάκης',1.1, 0.04),
  ('food','Ταβέρνα Ο Μύλος','HoReCa','Ρέθυμνο','Μ. Δασκαλάκη',1.0,-0.22),
  ('food','Καφέ-Εστιατόριο Πλατεία','HoReCa','Ηράκλειο','Μ. Δασκαλάκη',0.8, 0.02),
  ('food','Παντοπωλείο Κουκούλι','Παντοπωλεία','Λασίθι','Ν. Βασιλάκης',0.7, 0.24),
  ('food','Beach Bar Αλμυρίδα','HoReCa','Χανιά','Ν. Βασιλάκης',0.6,-0.08),
  ('food','Ψητοπωλείο Στάχυ','HoReCa','Ηράκλειο','Γ. Μανουσάκης',0.5, 0.01),
  ('build','Κατασκευαστική Τέρμα ΕΠΕ','Κατασκευαστικές','Ηράκλειο','Π. Σταυράκης',1.7,-0.12),
  ('build','Δομή Κρήτης Α.Ε.','Κατασκευαστικές','Χανιά','Π. Σταυράκης',1.4, 0.05),
  ('build','Ν. Παπαδάκης Εργοληπτική','Εργολάβοι','Ηράκλειο','Ε. Κουτσάκη',1.1,-0.04),
  ('build','Ανακαινίσεις Φάρος','Εργολάβοι','Ρέθυμνο','Ε. Κουτσάκη',0.9, 0.18),
  ('build','Τεχνική Ψηλορείτης','Κατασκευαστικές','Ηράκλειο','Π. Σταυράκης',0.8,-0.20),
  ('build','Θερμοϋδραυλική Λευκά Όρη','Τεχνίτες','Χανιά','Ε. Κουτσάκη',0.7, 0.07),
  ('build','Ι. Μαρκάκης Ηλεκτρολόγος','Τεχνίτες','Λασίθι','Ε. Κουτσάκη',0.6, 0.03),
  ('build','Οικοδομή Μεσαρά ΙΚΕ','Εργολάβοι','Μεσαρά','Π. Σταυράκης',0.5, 0.09)
),
items(k, code, item, cat, brand, price, cr, cr26) as (values
  ('food','Γ001','Γάλα φρέσκο 1lt','Γαλακτοκομικά','Κρήτης Γη',1.15,0.78,0.84),
  ('food','Γ002','Γιαούρτι στραγγιστό 1kg','Γαλακτοκομικά','Κρήτης Γη',4.20,0.80,0.85),
  ('food','Γ003','Γραβιέρα Κρήτης kg','Γαλακτοκομικά','Ψηλορείτης',13.50,0.82,0.86),
  ('food','Α001','Λουκάνικο χωριάτικο kg','Αλλαντικά','Σφακιανό',9.80,0.78,0.77),
  ('food','Α002','Απάκι kg','Αλλαντικά','Σφακιανό',14.20,0.77,0.77),
  ('food','Ε001','Ελαιόλαδο έξτρα παρθένο 5lt','Ελαιόλαδο','Μεσαρά Gold',42.00,0.86,0.85),
  ('food','Ε002','Ελαιόλαδο 1lt γυάλινο','Ελαιόλαδο','Μεσαρά Gold',9.80,0.84,0.83),
  ('food','Ζ001','Μακαρόνια Νο10 500g','Ζυμαρικά & όσπρια','Σιτάρι',0.95,0.75,0.75),
  ('food','Ζ002','Φακές ψιλές 500g','Ζυμαρικά & όσπρια','Σιτάρι',1.90,0.76,0.75),
  ('food','Π001','Νερό 1,5lt (εξάδα)','Αναψυκτικά & ποτά','Πηγή Ίδης',1.80,0.79,0.80),
  ('food','Π002','Κρασί λευκό 750ml','Αναψυκτικά & ποτά','Αμπέλια Πεζών',6.50,0.81,0.81),
  ('food','Κ001','Απορρυπαντικό πιάτων 4lt','Απορρυπαντικά','Καθαρό',5.40,0.72,0.71),
  ('build','Τ001','Τσιμέντο 25kg','Τσιμέντα & κονιάματα','Ηρακλής',6.80,0.87,0.87),
  ('build','Τ002','Κόλλα πλακιδίων 25kg','Τσιμέντα & κονιάματα','Κολλητήρι',9.50,0.85,0.86),
  ('build','Σ001','Σίδηρος Β500C Φ12 (τόνος)','Σίδηρος οπλισμού','Σιδηρουργία Αιγαίου',780.0,0.90,0.93),
  ('build','Σ002','Πλέγμα Τ131','Σίδηρος οπλισμού','Σιδηρουργία Αιγαίου',38.0,0.89,0.92),
  ('build','Π101','Πλακάκι δαπέδου 60x60 γκρι m²','Πλακίδια','Κεραμική Κνωσού',18.50,0.70,0.70),
  ('build','Π102','Πλακάκι μπάνιου 30x60 m²','Πλακίδια','Κεραμική Κνωσού',16.00,0.71,0.70),
  ('build','Χ001','Πλαστικό χρώμα λευκό 10lt','Χρώματα','Χρωματικά Ίδης',42.00,0.68,0.67),
  ('build','Χ002','Ακρυλικό πρόσοψης 10lt','Χρώματα','Χρωματικά Ίδης',58.00,0.69,0.68),
  ('build','Υ001','Σωλήνας PPR Φ20 (6m)','Υδραυλικά','Aqua Kriti',4.80,0.74,0.74),
  ('build','Υ002','Μπαταρία κουζίνας','Υδραυλικά','Aqua Kriti',64.00,0.73,0.74),
  ('build','Η001','Καλώδιο NYM 3x1,5 (100m)','Ηλεκτρολογικά','Volta',62.00,0.76,0.78),
  ('build','Η002','Πίνακας ηλεκτρικός 24 θέσεων','Ηλεκτρολογικά','Volta',85.00,0.75,0.77)
),
months(m) as (select generate_series('2025-01-01'::date, '2026-10-01'::date, interval '1 month')::date),
season(k, mon, f) as (values
  ('food',1,0.70),('food',2,0.72),('food',3,0.85),('food',4,0.98),('food',5,1.10),('food',6,1.30),
  ('food',7,1.50),('food',8,1.55),('food',9,1.20),('food',10,0.95),('food',11,0.75),('food',12,0.85),
  ('build',1,0.80),('build',2,0.85),('build',3,1.02),('build',4,1.10),('build',5,1.15),('build',6,1.10),
  ('build',7,1.05),('build',8,0.70),('build',9,1.08),('build',10,1.12),('build',11,0.95),('build',12,0.80)
),
raw as (
  select t.tid, m, c.customer, c.grp, c.region, c.sp, i.code, i.item, i.cat, i.brand, i.price,
         case when extract(year from m) = 2026 then i.cr26 else i.cr end as cr,
         (t.base * c.weight * s.f
           * (case when extract(year from m) = 2026 then 1 + c.trend else 1 end)
           * (0.55 + random() * 0.9))::numeric as val,
         random() as pick, random() as dayr
  from t
  join cust c   on c.k = t.k
  join items i  on i.k = t.k
  cross join months
  join season s on s.k = t.k and s.mon = extract(month from m)
)
insert into public.bi_sales (tenant_id, doc_date, customer, customer_group, region, salesperson,
                             item_code, item, category, brand, qty, net_amount, cost_amount)
select tid, m + floor(dayr * 27)::int, customer, grp, region, sp, code, item, cat, brand,
       greatest(1, round(val / price)),
       round(greatest(1, round(val / price)) * price, 2),
       round(greatest(1, round(val / price)) * price * cr, 2)
from raw
where pick < 0.78;

-- ---------- Υπόλοιπα πελατών ----------
with days(customer, d) as (values
  ('Σούπερ Μάρκετ Αλώνι',38),('Ξενοδοχείο Γαλάζια Ακτή',52),('Mini Market Δαφνές',96),('Ταβέρνα Ο Μύλος',44),
  ('Καφέ-Εστιατόριο Πλατεία',121),('Παντοπωλείο Κουκούλι',33),('Beach Bar Αλμυρίδα',68),('Ψητοπωλείο Στάχυ',47),
  ('Κατασκευαστική Τέρμα ΕΠΕ',104),('Δομή Κρήτης Α.Ε.',61),('Ν. Παπαδάκης Εργοληπτική',45),('Ανακαινίσεις Φάρος',36),
  ('Τεχνική Ψηλορείτης',132),('Θερμοϋδραυλική Λευκά Όρη',52),('Ι. Μαρκάκης Ηλεκτρολόγος',41),('Οικοδομή Μεσαρά ΙΚΕ',73)
),
b as (
  select s.tenant_id, s.customer, d.d,
         round(sum(s.net_amount * 1.24) * d.d / 90.0 * 0.55, 2) as bal
  from public.bi_sales s join days d on d.customer = s.customer
  where s.doc_date >= '2026-08-01'
  group by s.tenant_id, s.customer, d.d
)
insert into public.bi_customer_balances (tenant_id, customer, balance, d0_30, d31_60, d61_90, d90p, avg_days)
select tenant_id, customer, bal,
       bal - (case when d > 35 then round(bal*0.25,2) else 0 end)
           - (case when d > 60 then round(bal*0.25,2) else 0 end)
           - (case when d > 90 then round(bal*0.35,2) else 0 end),
       case when d > 35 then round(bal*0.25,2) else 0 end,
       case when d > 60 then round(bal*0.25,2) else 0 end,
       case when d > 90 then round(bal*0.35,2) else 0 end,
       d
from b;

-- ---------- Απόθεμα ----------
insert into public.bi_stock (tenant_id, item_code, item, category, qty, value, last_sale)
select tenant_id, item_code, max(item), max(category),
       round(sum(qty) filter (where doc_date >= '2026-09-01') * 0.6),
       round(sum(cost_amount) filter (where doc_date >= '2026-09-01') * 0.6, 2),
       max(doc_date)
from public.bi_sales
group by tenant_id, item_code;

insert into public.bi_stock (tenant_id, item_code, item, category, qty, value, last_sale) values
  ('11111111-1111-1111-1111-111111111111','Ε090','Ελαιόλαδο 5lt κουτί – παρτίδα 2025','Ελαιόλαδο',140,4270,'2026-06-04'),
  ('11111111-1111-1111-1111-111111111111','Π090','Χυμός ανανά 1lt','Αναψυκτικά & ποτά',310,450,'2026-05-21'),
  ('11111111-1111-1111-1111-111111111111','Ζ090','Σάλτσα τρούφας 180g','Ζυμαρικά & όσπρια',96,461,'2026-04-02'),
  ('22222222-2222-2222-2222-222222222222','Π190','Πλακάκι δαπέδου 60x120 μπεζ m²','Πλακίδια',180,3312,'2026-03-12'),
  ('22222222-2222-2222-2222-222222222222','Υ190','Ηλιακός θερμοσίφωνας 160lt','Υδραυλικά',6,3120,'2026-05-08'),
  ('22222222-2222-2222-2222-222222222222','Χ190','Χρώμα πρόσοψης ώχρα 10lt','Χρώματα',42,1617,'2026-04-19');

-- ---------- AI συμβουλές (στο demo υπολογίζονται από τα δεδομένα) ----------
-- 1. Μεγαλύτερη πτώση μεικτού κέρδους ανά κατηγορία
insert into public.bi_insights (tenant_id, severity, tag, title, body, action)
select distinct on (tenant_id) tenant_id, 'bad', 'Κερδοφορία',
  format('Το μεικτό κέρδος στα «%s» έπεσε %s μονάδες', category, replace(to_char(m25 - m26, 'FM90.0'), '.', ',')),
  format('Από %s%% στο ίδιο διάστημα πέρσι σε %s%% φέτος. Το κόστος αγοράς ανέβηκε, οι τιμές πώλησης έμειναν σχεδόν ίδιες.',
         replace(to_char(m25, 'FM90.0'), '.', ','), replace(to_char(m26, 'FM90.0'), '.', ',')),
  'Πρόταση: έλεγχος τιμοκαταλόγου για τα βασικά είδη της κατηγορίας.'
from (
  select tenant_id, category,
    100 * (1 - sum(cost_amount) filter (where doc_date between '2025-01-01' and '2025-10-31')
             / nullif(sum(net_amount) filter (where doc_date between '2025-01-01' and '2025-10-31'), 0)) as m25,
    100 * (1 - sum(cost_amount) filter (where doc_date >= '2026-01-01')
             / nullif(sum(net_amount) filter (where doc_date >= '2026-01-01'), 0)) as m26
  from public.bi_sales group by tenant_id, category
) x
order by tenant_id, (m25 - m26) desc;

-- 2. Πελάτες πάνω από 90 μέρες
insert into public.bi_insights (tenant_id, severity, tag, title, body, action)
select tenant_id, 'warn', 'Εισπράξεις',
  format('%s %s τις 90 μέρες είσπραξης', count(*), case when count(*) = 1 then 'πελάτης ξεπερνά' else 'πελάτες ξεπερνούν' end),
  format('%s: ανοιχτό υπόλοιπο %s €.', string_agg(customer, ', ' order by balance desc),
         replace(to_char(sum(balance), 'FM999G999'), ',', '.')),
  'Πρόταση: τηλεφωνική υπενθύμιση και πάγωμα πίστωσης μέχρι να μπει πληρωμή.'
from public.bi_customer_balances where avg_days > 90
group by tenant_id;

-- 3. Μεγάλος πελάτης με πτώση / 4. πελάτης με ανάπτυξη
with c as (
  select tenant_id, customer,
    sum(net_amount) filter (where doc_date between '2025-01-01' and '2025-10-31') as s25,
    sum(net_amount) filter (where doc_date >= '2026-01-01') as s26
  from public.bi_sales group by tenant_id, customer
),
r as (select *, 100 * (s26 / s25 - 1) as ch from c)
insert into public.bi_insights (tenant_id, severity, tag, title, body, action)
select * from (
  select distinct on (tenant_id) tenant_id, 'warn', 'Πελάτες',
    format('Ο πελάτης «%s» αγόρασε %s%% λιγότερα φέτος', customer, replace(to_char(abs(ch), 'FM90.0'), '.', ',')),
    format('Πωλήσεις %s € έναντι %s € το ίδιο διάστημα πέρσι.',
           replace(to_char(s26, 'FM999G999'), ',', '.'), replace(to_char(s25, 'FM999G999'), ',', '.')),
    'Πρόταση: επίσκεψη πωλητή ή ειδική προσφορά πριν χαθεί ο πελάτης.'
  from r order by tenant_id, ch asc
) a
union all
select * from (
  select distinct on (tenant_id) tenant_id, 'good', 'Ευκαιρία',
    format('Ο πελάτης «%s» αυξάνει σταθερά (+%s%%)', customer, replace(to_char(ch, 'FM90.0'), '.', ',')),
    format('Πωλήσεις %s € φέτος. Υπάρχει περιθώριο για περισσότερες κατηγορίες ειδών.',
           replace(to_char(s26, 'FM999G999'), ',', '.')),
    'Πρόταση: προτείνετε είδη από τις κατηγορίες με το υψηλότερο περιθώριο.'
  from r order by tenant_id, ch desc
) b;

-- ---------- Διαφορετικές αναφορές ανά επιχείρηση ----------
insert into public.bi_reports (tenant_id, name, kind, config, created_by) values
  ('11111111-1111-1111-1111-111111111111', 'Πωλήσεις ανά περιοχή και μήνα', 'pivot',
   '{"rows":"region","cols":"month","measure":"net","year":"2026"}', null),
  ('11111111-1111-1111-1111-111111111111', 'Μεικτό κέρδος % ανά κατηγορία και πωλητή', 'pivot',
   '{"rows":"category","cols":"salesperson","measure":"margin_pct","year":"2026"}', null),
  ('11111111-1111-1111-1111-111111111111', 'HoReCa: πελάτες ανά τρίμηνο', 'pivot',
   '{"rows":"customer","cols":"quarter","measure":"net","year":"2026","filter":{"customer_group":"HoReCa"}}', null),
  ('22222222-2222-2222-2222-222222222222', 'Πωλήσεις ανά πωλητή και τρίμηνο', 'pivot',
   '{"rows":"salesperson","cols":"quarter","measure":"net","year":"2026"}', null),
  ('22222222-2222-2222-2222-222222222222', 'Μάρκες ανά ομάδα πελατών', 'pivot',
   '{"rows":"brand","cols":"customer_group","measure":"net","year":"2026"}', null),
  ('22222222-2222-2222-2222-222222222222', 'Σίδηρος: ποσότητα ανά πελάτη και μήνα', 'pivot',
   '{"rows":"customer","cols":"month","measure":"qty","year":"2026","filter":{"category":"Σίδηρος οπλισμού"}}', null);

commit;
