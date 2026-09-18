-- migration-class: additive
-- migration: reference_commerce_foundation
-- reference-client: reference-commerce
-- description: >-
--   Reference Supabase/Postgres foundation for the provider-neutral production
--   core: customer profiles, B2B accounts and memberships, credit snapshots,
--   catalog, inventory, carts, orders, RFQs and quotations. Persistence only;
--   this schema is never product or business authority.
--
-- Identity note: profiles.identity_id / account_memberships.identity_id /
-- carts.identity_id / orders.identity_id correspond to auth.users.id. They are
-- intentionally not declared as foreign keys so deterministic synthetic seed
-- data can be loaded without pre-creating Supabase Auth users.

begin;

-- Shared updated_at maintenance -------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

-- Customer profiles -------------------------------------------------------------

create table if not exists public.profiles (
    id text primary key,
    identity_id uuid not null unique,
    display_name text not null,
    email text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Business accounts and membership ---------------------------------------------

create table if not exists public.business_accounts (
    id text primary key,
    name text not null,
    account_type text not null default 'trade'
        check (account_type in ('consumer', 'trade')),
    registration_number text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.account_memberships (
    id uuid primary key default gen_random_uuid(),
    account_id text not null
        references public.business_accounts (id) on delete cascade,
    identity_id uuid not null,
    role text not null
        check (role in ('consumer', 'b2b_buyer', 'b2b_manager', 'admin')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (account_id, identity_id)
);

create index if not exists account_memberships_identity_idx
    on public.account_memberships (identity_id);
create index if not exists account_memberships_account_idx
    on public.account_memberships (account_id);

create table if not exists public.credit_snapshots (
    id uuid primary key default gen_random_uuid(),
    account_id text not null
        references public.business_accounts (id) on delete cascade,
    credit_limit_minor bigint not null check (credit_limit_minor >= 0),
    available_credit_minor bigint not null check (available_credit_minor >= 0),
    captured_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    check (available_credit_minor <= credit_limit_minor)
);

create index if not exists credit_snapshots_account_captured_idx
    on public.credit_snapshots (account_id, captured_at desc);

-- Catalog ----------------------------------------------------------------------

create table if not exists public.categories (
    id text primary key,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.products (
    id text primary key,
    sku text not null unique,
    name text not null,
    description text,
    category_id text references public.categories (id) on delete set null,
    retail_price_minor bigint not null check (retail_price_minor >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists products_category_idx on public.products (category_id);

create table if not exists public.variants (
    id text primary key,
    product_id text not null references public.products (id) on delete cascade,
    name text not null,
    sku text not null unique,
    price_minor bigint not null check (price_minor >= 0),
    attributes jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists variants_product_idx on public.variants (product_id);

create table if not exists public.inventory (
    id uuid primary key default gen_random_uuid(),
    variant_id text not null references public.variants (id) on delete cascade,
    warehouse_id text not null default 'default',
    available integer not null check (available >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (variant_id, warehouse_id)
);

create index if not exists inventory_variant_idx on public.inventory (variant_id);

-- Carts ------------------------------------------------------------------------

create table if not exists public.carts (
    id text primary key,
    account_id text references public.business_accounts (id) on delete cascade,
    identity_id uuid,
    status text not null default 'active'
        check (status in ('active', 'converted', 'abandoned')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (account_id is not null or identity_id is not null)
);

create index if not exists carts_account_idx on public.carts (account_id);
create index if not exists carts_identity_idx on public.carts (identity_id);

create table if not exists public.cart_items (
    id uuid primary key default gen_random_uuid(),
    cart_id text not null references public.carts (id) on delete cascade,
    product_id text not null references public.products (id) on delete restrict,
    variant_id text not null references public.variants (id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price_minor bigint not null check (unit_price_minor >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (cart_id, variant_id)
);

create index if not exists cart_items_cart_idx on public.cart_items (cart_id);
create index if not exists cart_items_variant_idx on public.cart_items (variant_id);

-- Orders -----------------------------------------------------------------------

create table if not exists public.orders (
    id text primary key,
    account_id text references public.business_accounts (id) on delete set null,
    identity_id uuid,
    status text not null default 'pending'
        check (status in ('pending', 'confirmed', 'fulfilled', 'cancelled')),
    total_minor bigint not null check (total_minor >= 0),
    idempotency_key text not null unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (account_id is not null or identity_id is not null)
);

create index if not exists orders_account_idx on public.orders (account_id);
create index if not exists orders_identity_idx on public.orders (identity_id);
create index if not exists orders_status_idx on public.orders (status);

create table if not exists public.order_items (
    id uuid primary key default gen_random_uuid(),
    order_id text not null references public.orders (id) on delete cascade,
    product_id text not null references public.products (id) on delete restrict,
    variant_id text not null references public.variants (id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price_minor bigint not null check (unit_price_minor >= 0),
    created_at timestamptz not null default now(),
    unique (order_id, variant_id)
);

create index if not exists order_items_order_idx on public.order_items (order_id);
create index if not exists order_items_variant_idx on public.order_items (variant_id);

-- RFQs and quotations ----------------------------------------------------------

create table if not exists public.rfqs (
    id text primary key,
    account_id text not null
        references public.business_accounts (id) on delete cascade,
    identity_id uuid,
    status text not null default 'submitted'
        check (status in ('draft', 'submitted', 'quoted', 'converted', 'rejected')),
    message text,
    idempotency_key text unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists rfqs_account_idx on public.rfqs (account_id);
create index if not exists rfqs_identity_idx on public.rfqs (identity_id);

create table if not exists public.rfq_items (
    id uuid primary key default gen_random_uuid(),
    rfq_id text not null references public.rfqs (id) on delete cascade,
    product_id text not null references public.products (id) on delete restrict,
    variant_id text not null references public.variants (id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price_minor bigint not null check (unit_price_minor >= 0),
    created_at timestamptz not null default now(),
    unique (rfq_id, variant_id)
);

create index if not exists rfq_items_rfq_idx on public.rfq_items (rfq_id);

create table if not exists public.quotations (
    id text primary key,
    rfq_id text not null references public.rfqs (id) on delete cascade,
    total_minor bigint not null check (total_minor >= 0),
    status text not null default 'draft'
        check (status in ('draft', 'sent', 'accepted', 'rejected', 'expired')),
    valid_until timestamptz,
    idempotency_key text unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists quotations_rfq_idx on public.quotations (rfq_id);
create index if not exists quotations_status_idx on public.quotations (status);

-- updated_at triggers ----------------------------------------------------------

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

drop trigger if exists business_accounts_set_updated_at on public.business_accounts;
create trigger business_accounts_set_updated_at
    before update on public.business_accounts
    for each row execute function public.set_updated_at();

drop trigger if exists account_memberships_set_updated_at on public.account_memberships;
create trigger account_memberships_set_updated_at
    before update on public.account_memberships
    for each row execute function public.set_updated_at();

drop trigger if exists categories_set_updated_at on public.categories;
create trigger categories_set_updated_at
    before update on public.categories
    for each row execute function public.set_updated_at();

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
    before update on public.products
    for each row execute function public.set_updated_at();

drop trigger if exists variants_set_updated_at on public.variants;
create trigger variants_set_updated_at
    before update on public.variants
    for each row execute function public.set_updated_at();

drop trigger if exists inventory_set_updated_at on public.inventory;
create trigger inventory_set_updated_at
    before update on public.inventory
    for each row execute function public.set_updated_at();

drop trigger if exists carts_set_updated_at on public.carts;
create trigger carts_set_updated_at
    before update on public.carts
    for each row execute function public.set_updated_at();

drop trigger if exists cart_items_set_updated_at on public.cart_items;
create trigger cart_items_set_updated_at
    before update on public.cart_items
    for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
    before update on public.orders
    for each row execute function public.set_updated_at();

drop trigger if exists rfqs_set_updated_at on public.rfqs;
create trigger rfqs_set_updated_at
    before update on public.rfqs
    for each row execute function public.set_updated_at();

drop trigger if exists quotations_set_updated_at on public.quotations;
create trigger quotations_set_updated_at
    before update on public.quotations
    for each row execute function public.set_updated_at();

commit;
