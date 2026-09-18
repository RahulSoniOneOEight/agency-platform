-- seed: reference_commerce_seed
-- reference-client: reference-commerce
-- synthetic: true
-- description: >-
--   Deterministic, synthetic reference-commerce seed data. IDs align with
--   client-projects/reference-commerce/reference-e2e/fixture.yaml. All names,
--   emails and amounts are invented; emails use reserved .invalid domains and
--   there are no production secrets or real PII. Re-running is safe because
--   every insert is guarded by ON CONFLICT DO NOTHING.
--
-- Status mapping note: the fixture uses a few display statuses that are not
-- part of the provider-neutral domain enums; the seed stores the closest
-- domain value (order "processing" -> "confirmed", quotation "pending" -> "sent").

begin;

-- Profiles (identity_id mirrors auth.users.id for the synthetic identities) ----

insert into public.profiles (id, identity_id, display_name, email) values
    ('prof-consumer-01', '00000000-0000-4000-8000-000000000001', 'Dana Whitfield', 'dana.whitfield@example.invalid'),
    ('prof-consumer-02', '00000000-0000-4000-8000-000000000002', 'Marco Reyes', 'marco.reyes@example.invalid'),
    ('prof-buyer-01', '00000000-0000-4000-8000-000000000011', 'Priya Nandakumar', 'priya.nandakumar@northwind.example.invalid'),
    ('prof-manager-01', '00000000-0000-4000-8000-000000000012', 'Tomas Lindqvist', 'tomas.lindqvist@northwind.example.invalid'),
    ('prof-buyer-02', '00000000-0000-4000-8000-000000000013', 'Amara Okafor', 'amara.okafor@blueharbor.example.invalid'),
    ('prof-manager-02', '00000000-0000-4000-8000-000000000014', 'Jonas Petrov', 'jonas.petrov@blueharbor.example.invalid'),
    ('prof-manager-03', '00000000-0000-4000-8000-000000000015', 'Helena Marsh', 'helena.marsh@cedarpine.example.invalid'),
    ('prof-admin-01', '00000000-0000-4000-8000-000000000099', 'Operations Admin', 'operations.admin@example.invalid')
on conflict (id) do nothing;

-- Business accounts ------------------------------------------------------------

insert into public.business_accounts (id, name, account_type, registration_number) values
    ('acct-consumer-01', 'Dana Whitfield', 'consumer', null),
    ('acct-consumer-02', 'Marco Reyes', 'consumer', null),
    ('acct-trade-01', 'Northwind Electronics LLC', 'trade', 'REG-NW-1001'),
    ('acct-trade-02', 'Blue Harbor Audio', 'trade', 'REG-BH-2002'),
    ('acct-trade-03', 'Cedar and Pine Home', 'trade', 'REG-CP-3003')
on conflict (id) do nothing;

-- Account memberships (B2B access is always membership-scoped) ------------------

insert into public.account_memberships (account_id, identity_id, role) values
    ('acct-consumer-01', '00000000-0000-4000-8000-000000000001', 'consumer'),
    ('acct-consumer-02', '00000000-0000-4000-8000-000000000002', 'consumer'),
    ('acct-trade-01', '00000000-0000-4000-8000-000000000011', 'b2b_buyer'),
    ('acct-trade-01', '00000000-0000-4000-8000-000000000012', 'b2b_manager'),
    ('acct-trade-02', '00000000-0000-4000-8000-000000000013', 'b2b_buyer'),
    ('acct-trade-02', '00000000-0000-4000-8000-000000000014', 'b2b_manager'),
    ('acct-trade-03', '00000000-0000-4000-8000-000000000015', 'b2b_manager'),
    ('acct-trade-01', '00000000-0000-4000-8000-000000000099', 'admin')
on conflict (account_id, identity_id) do nothing;

-- Credit snapshots (minor units) ------------------------------------------------

insert into public.credit_snapshots (id, account_id, credit_limit_minor, available_credit_minor) values
    ('00000000-0000-4000-8000-000000000101', 'acct-trade-01', 5000000, 3245000),
    ('00000000-0000-4000-8000-000000000102', 'acct-trade-02', 2000000, 875000),
    ('00000000-0000-4000-8000-000000000103', 'acct-trade-03', 3500000, 3500000)
on conflict (id) do nothing;

-- Categories -------------------------------------------------------------------

insert into public.categories (id, name) values
    ('cat-001', 'Computing'),
    ('cat-002', 'Audio'),
    ('cat-003', 'Home Appliances'),
    ('cat-004', 'Accessories'),
    ('cat-005', 'Networking')
on conflict (id) do nothing;

-- Products ---------------------------------------------------------------------

insert into public.products (id, sku, name, category_id, retail_price_minor) values
    ('prd-001', 'SKU-ELE-1000', 'Laptop Pro 14', 'cat-001', 129900),
    ('prd-002', 'SKU-ELE-1001', 'Wireless Mouse', 'cat-004', 3900),
    ('prd-003', 'SKU-ELE-1002', 'Mechanical Keyboard', 'cat-004', 12900),
    ('prd-004', 'SKU-ELE-1003', '27-inch Monitor', 'cat-001', 34900),
    ('prd-005', 'SKU-ELE-1004', 'USB-C Hub', 'cat-004', 7900),
    ('prd-006', 'SKU-ELE-1005', 'Noise-Cancelling Headphones', 'cat-002', 27900),
    ('prd-007', 'SKU-ELE-1006', 'Bluetooth Speaker', 'cat-002', 8900),
    ('prd-008', 'SKU-ELE-1007', '65W GaN Charger', 'cat-004', 4900),
    ('prd-009', 'SKU-ELE-1008', 'Air Purifier', 'cat-003', 19900),
    ('prd-010', 'SKU-ELE-1009', 'Espresso Machine', 'cat-003', 44900),
    ('prd-011', 'SKU-ELE-1010', 'Mesh Wi-Fi Router', 'cat-005', 15900),
    ('prd-012', 'SKU-ELE-1011', '8-Port Network Switch', 'cat-005', 6900),
    ('prd-013', 'SKU-ELE-1012', 'Portable SSD 1TB', 'cat-001', 11900),
    ('prd-014', 'SKU-ELE-1013', 'Smart Thermostat', 'cat-003', 17900)
on conflict (id) do nothing;

-- Variants ---------------------------------------------------------------------

insert into public.variants (id, product_id, name, sku, price_minor, attributes) values
    ('var-001', 'prd-001', 'Laptop Pro 14 / 16GB / 512GB', 'SKU-ELE-1000-A', 129900, '{"memory": "16GB", "storage": "512GB"}'),
    ('var-002', 'prd-001', 'Laptop Pro 14 / 32GB / 1TB', 'SKU-ELE-1000-B', 129900, '{"memory": "32GB", "storage": "1TB"}'),
    ('var-003', 'prd-002', 'Wireless Mouse / Graphite', 'SKU-ELE-1001-A', 3900, '{"color": "Graphite"}'),
    ('var-004', 'prd-003', 'Mechanical Keyboard / ANSI / Brown', 'SKU-ELE-1002-A', 12900, '{"layout": "ANSI", "switch": "Brown"}'),
    ('var-005', 'prd-003', 'Mechanical Keyboard / ISO / Blue', 'SKU-ELE-1002-B', 12900, '{"layout": "ISO", "switch": "Blue"}'),
    ('var-006', 'prd-004', '27-inch Monitor / QHD', 'SKU-ELE-1003-A', 34900, '{"resolution": "QHD"}'),
    ('var-007', 'prd-005', 'USB-C Hub / 7-Port', 'SKU-ELE-1004-A', 7900, '{"ports": 7}'),
    ('var-008', 'prd-006', 'Noise-Cancelling Headphones / Midnight', 'SKU-ELE-1005-A', 27900, '{"color": "Midnight"}'),
    ('var-009', 'prd-006', 'Noise-Cancelling Headphones / Sand', 'SKU-ELE-1005-B', 27900, '{"color": "Sand"}'),
    ('var-010', 'prd-007', 'Bluetooth Speaker / Slate', 'SKU-ELE-1006-A', 8900, '{"color": "Slate"}'),
    ('var-011', 'prd-008', '65W GaN Charger / US', 'SKU-ELE-1007-A', 4900, '{"plug": "US"}'),
    ('var-012', 'prd-009', 'Air Purifier / Standard', 'SKU-ELE-1008-A', 19900, '{"filter": "HEPA"}'),
    ('var-013', 'prd-010', 'Espresso Machine / Stainless', 'SKU-ELE-1009-A', 44900, '{"finish": "Stainless"}'),
    ('var-014', 'prd-011', 'Mesh Wi-Fi Router / 2-Pack', 'SKU-ELE-1010-A', 15900, '{"pack": 2}'),
    ('var-015', 'prd-011', 'Mesh Wi-Fi Router / 3-Pack', 'SKU-ELE-1010-B', 15900, '{"pack": 3}'),
    ('var-016', 'prd-012', '8-Port Network Switch / Unmanaged', 'SKU-ELE-1011-A', 6900, '{"managed": "false"}'),
    ('var-017', 'prd-013', 'Portable SSD 1TB / USB-C', 'SKU-ELE-1012-A', 11900, '{"interface": "USB-C"}'),
    ('var-018', 'prd-014', 'Smart Thermostat / White', 'SKU-ELE-1013-A', 17900, '{"color": "White"}')
on conflict (id) do nothing;

-- Inventory --------------------------------------------------------------------

insert into public.inventory (variant_id, warehouse_id, available) values
    ('var-001', 'default', 24),
    ('var-002', 'default', 24),
    ('var-003', 'default', 180),
    ('var-004', 'default', 96),
    ('var-005', 'default', 96),
    ('var-006', 'default', 40),
    ('var-007', 'default', 210),
    ('var-008', 'default', 65),
    ('var-009', 'default', 65),
    ('var-010', 'default', 120),
    ('var-011', 'default', 300),
    ('var-012', 'default', 34),
    ('var-013', 'default', 18),
    ('var-014', 'default', 52),
    ('var-015', 'default', 52),
    ('var-016', 'default', 75),
    ('var-017', 'default', 88),
    ('var-018', 'default', 46)
on conflict (variant_id, warehouse_id) do nothing;

-- Carts and cart items ---------------------------------------------------------

insert into public.carts (id, account_id, identity_id, status) values
    ('cart-001', 'acct-consumer-01', '00000000-0000-4000-8000-000000000001', 'active'),
    ('cart-002', 'acct-trade-01', '00000000-0000-4000-8000-000000000011', 'active'),
    ('cart-003', 'acct-consumer-02', '00000000-0000-4000-8000-000000000002', 'active')
on conflict (id) do nothing;

insert into public.cart_items (cart_id, product_id, variant_id, quantity, unit_price_minor) values
    ('cart-001', 'prd-003', 'var-004', 1, 12900),
    ('cart-002', 'prd-005', 'var-007', 20, 7110),
    ('cart-003', 'prd-013', 'var-017', 2, 11900)
on conflict (cart_id, variant_id) do nothing;

-- Orders and order items -------------------------------------------------------

insert into public.orders (id, account_id, identity_id, status, total_minor, idempotency_key) values
    ('order-001', 'acct-consumer-01', '00000000-0000-4000-8000-000000000001', 'fulfilled', 16800, 'seed:order-001'),
    ('order-002', 'acct-trade-01', '00000000-0000-4000-8000-000000000011', 'confirmed', 142200, 'seed:order-002'),
    ('order-003', 'acct-trade-02', '00000000-0000-4000-8000-000000000013', 'pending', 80100, 'seed:order-003')
on conflict (id) do nothing;

insert into public.order_items (order_id, product_id, variant_id, quantity, unit_price_minor) values
    ('order-001', 'prd-002', 'var-003', 1, 3900),
    ('order-001', 'prd-003', 'var-004', 1, 12900),
    ('order-002', 'prd-005', 'var-007', 20, 7110),
    ('order-003', 'prd-007', 'var-010', 10, 8010)
on conflict (order_id, variant_id) do nothing;

-- RFQs, RFQ items and quotations -----------------------------------------------

insert into public.rfqs (id, account_id, identity_id, status, message, idempotency_key) values
    ('rfq-001', 'acct-trade-01', '00000000-0000-4000-8000-000000000011', 'submitted', 'Bulk monitor refresh for Q4.', 'seed:rfq-001'),
    ('rfq-002', 'acct-trade-02', '00000000-0000-4000-8000-000000000013', 'quoted', 'Networking bundle pricing request.', 'seed:rfq-002'),
    ('rfq-003', 'acct-trade-03', '00000000-0000-4000-8000-000000000015', 'draft', 'Smart thermostat pilot order.', 'seed:rfq-003')
on conflict (id) do nothing;

insert into public.rfq_items (rfq_id, product_id, variant_id, quantity, unit_price_minor) values
    ('rfq-001', 'prd-004', 'var-006', 12, 31410),
    ('rfq-002', 'prd-011', 'var-014', 8, 14310),
    ('rfq-003', 'prd-014', 'var-018', 6, 16110)
on conflict (rfq_id, variant_id) do nothing;

insert into public.quotations (id, rfq_id, total_minor, status, idempotency_key) values
    ('quote-001', 'rfq-001', 1708350, 'sent', 'seed:quote-001'),
    ('quote-002', 'rfq-002', 120150, 'accepted', 'seed:quote-002'),
    ('quote-003', 'rfq-003', 89550, 'rejected', 'seed:quote-003')
on conflict (id) do nothing;

commit;
