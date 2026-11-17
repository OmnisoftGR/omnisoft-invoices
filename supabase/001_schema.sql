-- =====================================================================
-- omnisoft-invoices : αρχικό σχήμα (multi-tenant)
-- =====================================================================
begin;

create extension if not exists vector with schema extensions;

-- ---------- Πελάτες (tenants) ----------
create table public.tenants (
  id                          uuid primary key default gen_random_uuid(),
  name                        text not null,
  afm                         text,
  galaxy_api_key_hash         text,                      -- hash του key που δίνουμε στο Galaxy script
  auto_approve                boolean not null default false,
  auto_approve_min_confidence numeric(4,3) not null default 0.950,
  created_at                  timestamptz not null default now()
);

-- ---------- Χρήστες ----------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  tenant_id   uuid not null references public.tenants(id),
  full_name   text,
  role        text not null default 'user' check (role in ('admin','user')),
  created_at  timestamptz not null default now()
);

-- tenant του συνδεδεμένου χρήστη
create or replace function public.current_tenant_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid()
$$;

-- ---------- Τιμολόγια ----------
create table public.invoices (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null default public.current_tenant_id() references public.tenants(id),
  source           text not null default 'upload'
                   check (source in ('upload','email','mydata','provider')),
  status           text not null default 'uploaded'
                   check (status in ('uploaded','analyzing','review','approved','importing','imported','error','duplicate')),
  file_path        text,
  supplier_afm     text,
  supplier_name    text,
  doc_type         text,
  doc_series       text,
  doc_number       text,
  doc_date         date,
  mark             text,                -- ΜΑΡΚ myDATA
  currency         text not null default 'EUR',
  net_amount       numeric(14,2),
  vat_amount       numeric(14,2),
  total_amount     numeric(14,2),
  confidence       numeric(4,3),
  ai_raw           jsonb,
  galaxy_doc_id    text,
  galaxy_doc_code  text,
  error_message    text,
  created_by       uuid default auth.uid() references auth.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index invoices_tenant_status on public.invoices (tenant_id, status);

-- έλεγχος διπλοεγγραφών: ίδιος πελάτης + ΑΦΜ προμηθευτή + αριθμός + ημερομηνία
create unique index invoices_dedup
  on public.invoices (tenant_id, supplier_afm, doc_number, doc_date)
  where supplier_afm is not null and doc_number is not null and status <> 'duplicate';

-- ---------- Γραμμές τιμολογίων ----------
create table public.invoice_lines (
  id                  uuid primary key default gen_random_uuid(),
  invoice_id          uuid not null references public.invoices(id) on delete cascade,
  tenant_id           uuid not null default public.current_tenant_id() references public.tenants(id),
  line_no             int not null,
  supplier_item_code  text,
  description         text,
  quantity            numeric(14,4),
  unit                text,
  unit_price          numeric(14,4),
  discount            numeric(14,2),
  net_amount          numeric(14,2),
  vat_rate            numeric(5,2),
  vat_amount          numeric(14,2),
  galaxy_item_code    text,
  galaxy_item_id      text,
  galaxy_extra        jsonb,           -- αποθήκη, κέντρο κόστους, έργο κ.λπ.
  match_source        text check (match_source in ('mapping','history','ai','manual')),
  confidence          numeric(4,3)
);

create index invoice_lines_invoice on public.invoice_lines (invoice_id);

-- ---------- Αντιστοιχίσεις ειδών ανά πελάτη ----------
create table public.item_mappings (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null default public.current_tenant_id() references public.tenants(id),
  supplier_afm          text not null,
  supplier_item_code    text,
  supplier_description  text,
  galaxy_item_code      text not null,
  galaxy_extra          jsonb,
  times_used            int not null default 1,
  last_used_at          timestamptz not null default now(),
  unique nulls not distinct (tenant_id, supplier_afm, supplier_item_code, supplier_description)
);

-- ---------- Master δεδομένα από Galaxy ----------
create table public.galaxy_suppliers (
  tenant_id   uuid not null references public.tenants(id),
  galaxy_id   text not null,
  code        text,
  name        text,
  afm         text,
  synced_at   timestamptz not null default now(),
  primary key (tenant_id, galaxy_id)
);
create index galaxy_suppliers_afm on public.galaxy_suppliers (tenant_id, afm);

create table public.galaxy_items (
  tenant_id    uuid not null references public.tenants(id),
  galaxy_id    text not null,
  code         text,
  description  text,
  unit         text,
  vat_rate     numeric(5,2),
  embedding    extensions.vector(384),
  synced_at    timestamptz not null default now(),
  primary key (tenant_id, galaxy_id)
);

-- ---------- Ιστορικό αγορών από Galaxy (για «μάθηση») ----------
create table public.purchase_history (
  tenant_id          uuid not null references public.tenants(id),
  galaxy_doc_id      text not null,
  line_no            int not null,
  supplier_afm       text,
  doc_type           text,
  doc_series         text,
  doc_date           date,
  line_description   text,
  galaxy_item_code   text,
  quantity           numeric(14,4),
  net_amount         numeric(14,2),
  vat_rate           numeric(5,2),
  extra              jsonb,            -- αποθήκη, κέντρο κόστους, έργο, σχόλια
  embedding          extensions.vector(384),
  synced_at          timestamptz not null default now(),
  primary key (tenant_id, galaxy_doc_id, line_no)
);
create index purchase_history_supplier on public.purchase_history (tenant_id, supplier_afm, doc_date desc);
create index purchase_history_embedding on public.purchase_history
  using hnsw (embedding extensions.vector_cosine_ops);

-- ---------- updated_at ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger invoices_updated_at
  before update on public.invoices
  for each row execute function public.set_updated_at();

-- ---------- Row Level Security ----------
alter table public.tenants          enable row level security;
alter table public.profiles         enable row level security;
alter table public.invoices         enable row level security;
alter table public.invoice_lines    enable row level security;
alter table public.item_mappings    enable row level security;
alter table public.galaxy_suppliers enable row level security;
alter table public.galaxy_items     enable row level security;
alter table public.purchase_history enable row level security;

create policy tenant_read on public.tenants
  for select to authenticated using (id = public.current_tenant_id());

create policy profile_read on public.profiles
  for select to authenticated using (tenant_id = public.current_tenant_id());

create policy tenant_all on public.invoices
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy tenant_all on public.invoice_lines
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy tenant_all on public.item_mappings
  for all to authenticated
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy tenant_read on public.galaxy_suppliers
  for select to authenticated using (tenant_id = public.current_tenant_id());

create policy tenant_read on public.galaxy_items
  for select to authenticated using (tenant_id = public.current_tenant_id());

create policy tenant_read on public.purchase_history
  for select to authenticated using (tenant_id = public.current_tenant_id());

-- δικαιώματα (τα νέα tables δεν εκτίθενται αυτόματα)
grant select on public.tenants, public.profiles,
               public.galaxy_suppliers, public.galaxy_items, public.purchase_history
  to authenticated;
grant select, insert, update, delete on public.invoices, public.invoice_lines, public.item_mappings
  to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function public.current_tenant_id() to authenticated;

-- ---------- Storage: αρχεία τιμολογίων ανά πελάτη ----------
insert into storage.buckets (id, name, public)
values ('invoices', 'invoices', false)
on conflict (id) do nothing;

create policy invoices_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'invoices'
         and (storage.foldername(name))[1] = public.current_tenant_id()::text);

create policy invoices_files_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'invoices'
              and (storage.foldername(name))[1] = public.current_tenant_id()::text);

-- ---------- Realtime ----------
alter publication supabase_realtime add table public.invoices;

commit;
