-- migration-class: additive
-- migration: reference_commerce_rls
-- reference-client: reference-commerce
-- description: >-
--   Row level security for the reference commerce schema. Backend/RLS is the
--   real authorization boundary; Flutter role guards are UX convenience only.
--   Consumers own their own profile/cart/order rows. B2B access to an account
--   is granted only through account_memberships; manager-level writes require a
--   b2b_manager membership. Global admin operations are intentionally expressed
--   through the backend service role (which bypasses RLS); no client-side admin
--   policy is granted here.
--
--   Write scoping: a personal (consumer) row must satisfy
--   ``identity_id = auth.uid() and account_id is null``; a row with a non-null
--   ``account_id`` is only writable by an actor who holds a membership on that
--   account AND sets ``identity_id = auth.uid()``. A consumer can therefore
--   never attach their own row to an arbitrary account, and an account member
--   can never attribute a row to another identity. Child rows without an
--   ``identity_id`` column (cart_items, order_items, rfq_items, quotations) are
--   scoped by their parent account membership; manager-authored quotations for
--   a buyer-created RFQ remain possible.

begin;

-- Membership helpers -----------------------------------------------------------
-- SECURITY DEFINER keeps membership lookups from recursing through the
-- account_memberships RLS policy.

create or replace function public.is_account_member(target_account_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.account_memberships membership
        where membership.account_id = target_account_id
          and membership.identity_id = auth.uid()
    );
$$;

create or replace function public.has_account_role(target_account_id text, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.account_memberships membership
        where membership.account_id = target_account_id
          and membership.identity_id = auth.uid()
          and membership.role = any (allowed_roles)
    );
$$;

revoke all on function public.is_account_member(text) from public;
revoke all on function public.has_account_role(text, text[]) from public;
grant execute on function public.is_account_member(text) to authenticated;
grant execute on function public.has_account_role(text, text[]) to authenticated;

-- Catalog: readable by authenticated users, writable only by the backend -------

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.variants enable row level security;
alter table public.inventory enable row level security;

drop policy if exists categories_read_authenticated on public.categories;
create policy categories_read_authenticated
    on public.categories for select to authenticated using (true);
drop policy if exists products_read_authenticated on public.products;
create policy products_read_authenticated
    on public.products for select to authenticated using (true);
drop policy if exists variants_read_authenticated on public.variants;
create policy variants_read_authenticated
    on public.variants for select to authenticated using (true);
drop policy if exists inventory_read_authenticated on public.inventory;
create policy inventory_read_authenticated
    on public.inventory for select to authenticated using (true);

-- Profiles: a consumer owns exactly their own profile --------------------------

alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
    on public.profiles for select to authenticated
    using (identity_id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
    on public.profiles for insert to authenticated
    with check (identity_id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
    on public.profiles for update to authenticated
    using (identity_id = auth.uid())
    with check (identity_id = auth.uid());

-- Business accounts: membership-gated reads, manager-gated writes --------------

alter table public.business_accounts enable row level security;

drop policy if exists business_accounts_select_member on public.business_accounts;
create policy business_accounts_select_member
    on public.business_accounts for select to authenticated
    using (public.is_account_member(id));
drop policy if exists business_accounts_update_manager on public.business_accounts;
create policy business_accounts_update_manager
    on public.business_accounts for update to authenticated
    using (public.has_account_role(id, array['b2b_manager']))
    with check (public.has_account_role(id, array['b2b_manager']));

-- Account memberships: own rows plus manager administration --------------------

alter table public.account_memberships enable row level security;

drop policy if exists account_memberships_select_own on public.account_memberships;
create policy account_memberships_select_own
    on public.account_memberships for select to authenticated
    using (identity_id = auth.uid() or public.is_account_member(account_id));
drop policy if exists account_memberships_manage_manager on public.account_memberships;
create policy account_memberships_manage_manager
    on public.account_memberships for all to authenticated
    using (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    )
    with check (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    );

-- Credit snapshots: member-visible, manager-maintained -------------------------

alter table public.credit_snapshots enable row level security;

drop policy if exists credit_snapshots_select_member on public.credit_snapshots;
create policy credit_snapshots_select_member
    on public.credit_snapshots for select to authenticated
    using (public.is_account_member(account_id));
drop policy if exists credit_snapshots_manage_manager on public.credit_snapshots;
create policy credit_snapshots_manage_manager
    on public.credit_snapshots for all to authenticated
    using (public.has_account_role(account_id, array['b2b_manager']))
    with check (public.has_account_role(account_id, array['b2b_manager']));

-- Carts: consumer-owned or account-member --------------------------------------

alter table public.carts enable row level security;

drop policy if exists carts_select_owner_or_member on public.carts;
create policy carts_select_owner_or_member
    on public.carts for select to authenticated
    using (identity_id = auth.uid() or public.is_account_member(account_id));
drop policy if exists carts_insert_owner_or_buyer on public.carts;
create policy carts_insert_owner_or_buyer
    on public.carts for insert to authenticated
    with check (
        identity_id = auth.uid()
        and (
            account_id is null
            or public.has_account_role(account_id, array['b2b_buyer', 'b2b_manager'])
        )
    );
drop policy if exists carts_update_owner_or_buyer on public.carts;
create policy carts_update_owner_or_buyer
    on public.carts for update to authenticated
    using (
        identity_id = auth.uid()
        and (
            account_id is null
            or public.has_account_role(account_id, array['b2b_buyer', 'b2b_manager'])
        )
    )
    with check (
        identity_id = auth.uid()
        and (
            account_id is null
            or public.has_account_role(account_id, array['b2b_buyer', 'b2b_manager'])
        )
    );
drop policy if exists carts_delete_owner_or_manager on public.carts;
create policy carts_delete_owner_or_manager
    on public.carts for delete to authenticated
    using (
        identity_id = auth.uid()
        and (
            account_id is null
            or public.has_account_role(account_id, array['b2b_manager'])
        )
    );

alter table public.cart_items enable row level security;

drop policy if exists cart_items_select_owner_or_member on public.cart_items;
create policy cart_items_select_owner_or_member
    on public.cart_items for select to authenticated
    using (
        exists (
            select 1 from public.carts cart
            where cart.id = cart_items.cart_id
              and (cart.identity_id = auth.uid() or public.is_account_member(cart.account_id))
        )
    );
drop policy if exists cart_items_insert_owner_or_buyer on public.cart_items;
create policy cart_items_insert_owner_or_buyer
    on public.cart_items for insert to authenticated
    with check (
        exists (
            select 1 from public.carts cart
            where cart.id = cart_items.cart_id
              and (
                  (cart.identity_id = auth.uid() and cart.account_id is null)
                  or public.has_account_role(cart.account_id, array['b2b_buyer', 'b2b_manager'])
              )
        )
    );
drop policy if exists cart_items_update_owner_or_buyer on public.cart_items;
create policy cart_items_update_owner_or_buyer
    on public.cart_items for update to authenticated
    using (
        exists (
            select 1 from public.carts cart
            where cart.id = cart_items.cart_id
              and (
                  (cart.identity_id = auth.uid() and cart.account_id is null)
                  or public.has_account_role(cart.account_id, array['b2b_buyer', 'b2b_manager'])
              )
        )
    )
    with check (
        exists (
            select 1 from public.carts cart
            where cart.id = cart_items.cart_id
              and (
                  (cart.identity_id = auth.uid() and cart.account_id is null)
                  or public.has_account_role(cart.account_id, array['b2b_buyer', 'b2b_manager'])
              )
        )
    );
drop policy if exists cart_items_delete_owner_or_manager on public.cart_items;
create policy cart_items_delete_owner_or_manager
    on public.cart_items for delete to authenticated
    using (
        exists (
            select 1 from public.carts cart
            where cart.id = cart_items.cart_id
              and (
                  (cart.identity_id = auth.uid() and cart.account_id is null)
                  or public.has_account_role(cart.account_id, array['b2b_manager'])
              )
        )
    );

-- Orders: consumer-owned or account-member; manager-gated status writes --------

alter table public.orders enable row level security;

drop policy if exists orders_select_owner_or_member on public.orders;
create policy orders_select_owner_or_member
    on public.orders for select to authenticated
    using (identity_id = auth.uid() or public.is_account_member(account_id));
drop policy if exists orders_insert_owner_or_buyer on public.orders;
create policy orders_insert_owner_or_buyer
    on public.orders for insert to authenticated
    with check (
        identity_id = auth.uid()
        and (
            account_id is null
            or public.has_account_role(account_id, array['b2b_buyer', 'b2b_manager'])
        )
    );
drop policy if exists orders_update_manager on public.orders;
create policy orders_update_manager
    on public.orders for update to authenticated
    using (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    )
    with check (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    );

alter table public.order_items enable row level security;

drop policy if exists order_items_select_owner_or_member on public.order_items;
create policy order_items_select_owner_or_member
    on public.order_items for select to authenticated
    using (
        exists (
            select 1 from public.orders customer_order
            where customer_order.id = order_items.order_id
              and (
                  customer_order.identity_id = auth.uid()
                  or public.is_account_member(customer_order.account_id)
              )
        )
    );
drop policy if exists order_items_insert_owner_or_buyer on public.order_items;
create policy order_items_insert_owner_or_buyer
    on public.order_items for insert to authenticated
    with check (
        exists (
            select 1 from public.orders customer_order
            where customer_order.id = order_items.order_id
              and (
                  (customer_order.identity_id = auth.uid() and customer_order.account_id is null)
                  or public.has_account_role(
                      customer_order.account_id, array['b2b_buyer', 'b2b_manager']
                  )
              )
        )
    );

-- RFQs: members read, buyers create, managers amend ----------------------------

alter table public.rfqs enable row level security;

drop policy if exists rfqs_select_member on public.rfqs;
create policy rfqs_select_member
    on public.rfqs for select to authenticated
    using (identity_id = auth.uid() or public.is_account_member(account_id));
drop policy if exists rfqs_insert_buyer_or_manager on public.rfqs;
create policy rfqs_insert_buyer_or_manager
    on public.rfqs for insert to authenticated
    with check (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_buyer', 'b2b_manager'])
    );
drop policy if exists rfqs_update_manager on public.rfqs;
create policy rfqs_update_manager
    on public.rfqs for update to authenticated
    using (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    )
    with check (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    );
drop policy if exists rfqs_delete_manager on public.rfqs;
create policy rfqs_delete_manager
    on public.rfqs for delete to authenticated
    using (
        identity_id = auth.uid()
        and public.has_account_role(account_id, array['b2b_manager'])
    );

alter table public.rfq_items enable row level security;

drop policy if exists rfq_items_select_member on public.rfq_items;
create policy rfq_items_select_member
    on public.rfq_items for select to authenticated
    using (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = rfq_items.rfq_id
              and (rfq.identity_id = auth.uid() or public.is_account_member(rfq.account_id))
        )
    );
drop policy if exists rfq_items_insert_buyer_or_manager on public.rfq_items;
create policy rfq_items_insert_buyer_or_manager
    on public.rfq_items for insert to authenticated
    with check (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = rfq_items.rfq_id
              and public.has_account_role(rfq.account_id, array['b2b_buyer', 'b2b_manager'])
        )
    );

-- Quotations: members read, managers author ------------------------------------

alter table public.quotations enable row level security;

drop policy if exists quotations_select_member on public.quotations;
create policy quotations_select_member
    on public.quotations for select to authenticated
    using (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = quotations.rfq_id
              and (rfq.identity_id = auth.uid() or public.is_account_member(rfq.account_id))
        )
    );
drop policy if exists quotations_insert_manager on public.quotations;
create policy quotations_insert_manager
    on public.quotations for insert to authenticated
    with check (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = quotations.rfq_id
              and public.has_account_role(rfq.account_id, array['b2b_manager'])
        )
    );
drop policy if exists quotations_update_manager on public.quotations;
create policy quotations_update_manager
    on public.quotations for update to authenticated
    using (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = quotations.rfq_id
              and public.has_account_role(rfq.account_id, array['b2b_manager'])
        )
    )
    with check (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = quotations.rfq_id
              and public.has_account_role(rfq.account_id, array['b2b_manager'])
        )
    );
drop policy if exists quotations_delete_manager on public.quotations;
create policy quotations_delete_manager
    on public.quotations for delete to authenticated
    using (
        exists (
            select 1 from public.rfqs rfq
            where rfq.id = quotations.rfq_id
              and public.has_account_role(rfq.account_id, array['b2b_manager'])
        )
    );

commit;
