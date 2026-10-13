-- =============================================================================
-- drobie · 0900 · Row Level Security and privileges
-- Default deny everywhere. Every public table has RLS enabled; clients get only
-- the table and column privileges listed here. PLATFORM_ARCHITECTURE §4.
-- Policy helpers are wrapped in (select …) so they run once per statement.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Read helpers for child tables (items are the centre of the closet)
-- ---------------------------------------------------------------------------
create or replace function private.can_read_item(p_item uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.items i
    where i.id = p_item
      and (
        i.owner_user_id = auth.uid()
        or (i.deleted_at is null and i.visibility <> 'private' and private.is_household_member(i.household_id))
        or (i.deleted_at is null and private.has_access(i.owner_user_id, 'item_read', i.id, i.category_id, i.place_id))
      )
  )
$$;

create or replace function private.owns_item(p_item uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from public.items where id = p_item and owner_user_id = auth.uid()) $$;

create or replace function private.can_read_media(p_asset uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.media_assets a
    where a.id = p_asset
      and a.deleted_at is null
      and (
        a.owner_user_id = auth.uid()
        or (a.sensitivity <> 'sensitive' and exists (
              select 1 from public.item_media im where im.asset_id = a.id and private.can_read_item(im.item_id)))
      )
  )
$$;

create or replace function private.owns_order(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from public.orders where id = p_order and buyer_user_id = auth.uid()) $$;


-- Set-returning helpers: evaluated ONCE per statement (hashed sub-plans)
-- instead of once per row. This keeps list reads index-driven at scale
-- (a per-row has_access() call made closet sync a sequential scan).
create or replace function private.my_household_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$ select m.household_id from public.household_members m where m.user_id = auth.uid() $$;

create or replace function private.active_grants(p_scope public.grant_scope)
returns table (grantor_user_id uuid, resource_item_id uuid, resource_category_id uuid, resource_place_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select g.grantor_user_id, g.resource_item_id, g.resource_category_id, g.resource_place_id
  from public.access_grants g
  where auth.uid() is not null
    and g.revoked_at is null
    and (g.expires_at is null or g.expires_at > now())
    and g.scope = any (case p_scope
          when 'item_read'   then array['item_read', 'closet_read', 'item_borrow', 'support_view']::public.grant_scope[]
          when 'places_read' then array['places_read', 'closet_read', 'support_view']::public.grant_scope[]
          when 'closet_read' then array['closet_read', 'support_view']::public.grant_scope[]
          else array[p_scope] end)
    and (g.grantee_user_id = auth.uid()
         or g.grantee_household_id in (select m.household_id from public.household_members m where m.user_id = auth.uid()))
    and (g.scope <> 'support_view' or private.has_admin_role('support'))
    and not private.is_blocked(g.grantor_user_id, auth.uid())
$$;

-- (place, grantor) pairs covered by place-scoped grants, including sub-places
create or replace function private.granted_places(p_scope public.grant_scope)
returns table (place_id uuid, grantor_user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with recursive tree as (
    select pl.id, g.grantor_user_id
    from private.active_grants(p_scope) g join public.places pl on pl.id = g.resource_place_id
    union
    select c.id, tree.grantor_user_id from public.places c join tree on c.parent_id = tree.id
  )
  select id, grantor_user_id from tree
$$;

-- households whose owner granted the caller a whole-closet/places scope
create or replace function private.granted_household_ids(p_scope public.grant_scope)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select h.id from public.households h
  where h.owner_user_id in (select g.grantor_user_id from private.active_grants(p_scope) g
                            where g.resource_item_id is null and g.resource_category_id is null and g.resource_place_id is null)
$$;

grant execute on function
  private.can_read_item(uuid), private.owns_item(uuid), private.can_read_media(uuid), private.owns_order(uuid)
to authenticated, service_role;
grant execute on function
  private.my_household_ids(), private.active_grants(public.grant_scope),
  private.granted_places(public.grant_scope), private.granted_household_ids(public.grant_scope)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Owner columns default to the caller, so clients never need to send them
-- ---------------------------------------------------------------------------
alter table public.items         alter column owner_user_id   set default auth.uid();
alter table public.wear_logs     alter column owner_user_id   set default auth.uid();
alter table public.consents      alter column user_id         set default auth.uid();
alter table public.device_tokens alter column user_id         set default auth.uid();
alter table public.access_grants alter column grantor_user_id set default auth.uid();
alter table public.places        alter column created_by      set default auth.uid();
alter table public.body_profiles alter column user_id         set default auth.uid();
alter table public.notification_preferences alter column user_id set default auth.uid();

-- ---------------------------------------------------------------------------
-- Enable RLS on every public table. Table owners (the migration role, used by
-- SECURITY DEFINER helpers) are exempt because RLS is not FORCEd. Tables
-- without a policy below are server-only.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute format('alter table public.%I enable row level security', r.relname);
  end loop;
end $$;

-- Strip every client privilege, then grant precisely.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all tables    in schema private from anon, authenticated;
revoke all on all tables    in schema audit   from anon, authenticated;
grant  all on all tables    in schema public  to service_role;
grant  all on all tables    in schema private to service_role;
grant  all on all tables    in schema audit   to service_role;
grant  usage on schema public to anon, authenticated, service_role;

-- Functions: nothing is callable by clients unless granted on purpose.
-- Supabase auto-grants EXECUTE on new `public` functions to anon/authenticated;
-- strip that (now and for the future) and re-grant the client RPCs below.
revoke execute on all functions in schema public  from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon;
revoke execute on all functions in schema audit   from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
grant execute on function public.entitlement(text), public.my_wallets(), public.confirm_adult() to authenticated;

-- ===========================================================================
-- Reference data readable by everyone (taxonomy, plans for the paywall)
-- ===========================================================================
grant select on public.countries, public.categories, public.category_translations,
                public.plans, public.features, public.plan_features
  to anon, authenticated;
grant select on public.brands, public.retailers, public.products, public.synonyms to authenticated;

create policy countries_read on public.countries for select to anon, authenticated using (active);
create policy categories_read on public.categories for select to anon, authenticated using (active);
create policy category_translations_read on public.category_translations for select to anon, authenticated using (true);
create policy plans_read on public.plans for select to anon, authenticated using (active);
create policy features_read on public.features for select to anon, authenticated using (client_visible);
create policy plan_features_read on public.plan_features for select to anon, authenticated using (
  exists (select 1 from public.features f where f.id = feature_id and f.client_visible));
create policy brands_read on public.brands for select to authenticated using (true);
create policy retailers_read on public.retailers for select to authenticated using (active);
create policy products_read on public.products for select to authenticated using (true);
create policy synonyms_read on public.synonyms for select to authenticated using (active);

-- ===========================================================================
-- Identity
-- ===========================================================================
grant select on public.profiles to authenticated;
grant update (display_name, handle, country, city, locale, timezone, currency, morning_time, vibe, settings, avatar_media_id)
  on public.profiles to authenticated;
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select on public.consents to authenticated;
grant insert (user_id, consent_type, version, granted, source) on public.consents to authenticated;
create policy consents_select_own on public.consents for select to authenticated
  using (user_id = (select auth.uid()));
create policy consents_insert_own on public.consents for insert to authenticated
  with check (user_id = (select auth.uid()) and source in ('app', 'web'));

grant select, delete on public.device_tokens to authenticated;
grant insert (user_id, token, platform, app_version) on public.device_tokens to authenticated;
grant update (app_version, last_seen_at, disabled_at) on public.device_tokens to authenticated;
create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select on public.admin_users to authenticated;
create policy admin_users_select_own on public.admin_users for select to authenticated
  using (user_id = (select auth.uid()));

-- SENSITIVE: owner, or a grant that names measurements_read explicitly
grant select, delete on public.body_profiles to authenticated;
grant insert (user_id, height_cm, measurements, size_passport, fit_preferences) on public.body_profiles to authenticated;
grant update (height_cm, measurements, size_passport, fit_preferences) on public.body_profiles to authenticated;
create policy body_profiles_select on public.body_profiles for select to authenticated
  using (user_id = (select auth.uid()) or private.has_access(user_id, 'measurements_read'));
create policy body_profiles_insert on public.body_profiles for insert to authenticated
  with check (user_id = (select auth.uid()) and (select private.has_consent((select auth.uid()), 'measurements')));
create policy body_profiles_update on public.body_profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and (select private.has_consent((select auth.uid()), 'measurements')));
create policy body_profiles_delete on public.body_profiles for delete to authenticated
  using (user_id = (select auth.uid()));

-- ===========================================================================
-- Households and places
-- ===========================================================================
grant select on public.households to authenticated;
grant update (name) on public.households to authenticated;
create policy households_select_member on public.households for select to authenticated
  using ((select private.is_household_member(id)));
create policy households_update_owner on public.households for update to authenticated
  using (owner_user_id = (select auth.uid())) with check (owner_user_id = (select auth.uid()));

grant select on public.household_members to authenticated;
create policy household_members_select on public.household_members for select to authenticated
  using ((select private.is_household_member(household_id)));

grant select on public.places to authenticated;
grant insert (id, household_id, parent_id, name, kind, icon, sort_order, created_by) on public.places to authenticated;
grant update (parent_id, name, kind, icon, sort_order, deleted_at) on public.places to authenticated;
create policy places_select on public.places for select to authenticated
  using (
    household_id in (select private.my_household_ids())
    or (deleted_at is null and household_id in (select private.granted_household_ids('places_read')))
    or (deleted_at is null and id in (select gp.place_id from private.granted_places('places_read') gp))
  );
create policy places_insert on public.places for insert to authenticated
  with check (
    (select private.is_household_member(household_id, 'adult'))
    and created_by = (select auth.uid())
    and (select private.is_active_adult((select auth.uid())))
  );
create policy places_update on public.places for update to authenticated
  using ((select private.is_household_member(household_id, 'adult')))
  with check ((select private.is_household_member(household_id, 'adult')));

grant select on public.tags to authenticated;
create policy tags_select on public.tags for select to authenticated
  using (household_id is not null and (select private.is_household_member(household_id)));

-- ===========================================================================
-- Sharing grants
-- ===========================================================================
grant select on public.access_grants to authenticated;
grant insert (grantor_user_id, grantee_user_id, grantee_household_id, scope, resource_item_id, resource_category_id,
              resource_place_id, purpose, note, expires_at)
  on public.access_grants to authenticated;
grant update (expires_at, revoked_at) on public.access_grants to authenticated;
create policy access_grants_select on public.access_grants for select to authenticated
  using (grantor_user_id = (select auth.uid()) or grantee_user_id = (select auth.uid()));
create policy access_grants_insert on public.access_grants for insert to authenticated
  with check (
    grantor_user_id = (select auth.uid())
    and (resource_item_id is null or (select private.owns_item(resource_item_id)))
    and (select private.is_active_adult((select auth.uid())))
  );
create policy access_grants_update on public.access_grants for update to authenticated
  using (grantor_user_id = (select auth.uid())) with check (grantor_user_id = (select auth.uid()));

-- ===========================================================================
-- Media
-- ===========================================================================
grant select on public.media_assets, public.media_variants to authenticated;
create policy media_assets_select on public.media_assets for select to authenticated
  using (owner_user_id = (select auth.uid()) or private.can_read_media(id));
create policy media_variants_select on public.media_variants for select to authenticated
  using (private.can_read_media(asset_id));

-- ===========================================================================
-- Closet
-- ===========================================================================
grant select on public.items to authenticated;
grant insert (id, owner_user_id, household_id, visibility, kind, category_id, product_id, brand_id, name, brand, size,
              colours, pattern, fabric, seasons, occasions, own_tags, notes, attributes, price_minor, currency,
              purchased_on, return_by, warranty_until, place_id, state, holder_name, holder_user_id, due_back_on,
              confidence, tag_source, source, is_stub, user_confirmed)
  on public.items to authenticated;
grant update (household_id, visibility, kind, category_id, product_id, brand_id, name, brand, size,
              colours, pattern, fabric, seasons, occasions, own_tags, notes, attributes, price_minor, currency,
              purchased_on, return_by, warranty_until, place_id, state, holder_name, holder_user_id, due_back_on,
              confidence, tag_source, source, is_stub, user_confirmed, deleted_at)
  on public.items to authenticated;

create policy items_select on public.items for select to authenticated
  using (
    owner_user_id = (select auth.uid())
    or (deleted_at is null and (
          (visibility <> 'private' and household_id in (select private.my_household_ids()))
          or owner_user_id in (select g.grantor_user_id from private.active_grants('item_read') g
                               where g.resource_item_id is null and g.resource_category_id is null and g.resource_place_id is null)
          or id in (select g.resource_item_id from private.active_grants('item_read') g where g.resource_item_id is not null)
          or (category_id, owner_user_id) in (select g.resource_category_id, g.grantor_user_id
                                              from private.active_grants('item_read') g where g.resource_category_id is not null)
          or (place_id, owner_user_id) in (select gp.place_id, gp.grantor_user_id from private.granted_places('item_read') gp)
    ))
  );
create policy items_insert on public.items for insert to authenticated
  with check (
    owner_user_id = (select auth.uid())
    and (select private.is_active_adult((select auth.uid())))
  );
create policy items_update on public.items for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()) and (select private.is_active_adult((select auth.uid()))));

grant select on public.item_events to authenticated;
create policy item_events_select on public.item_events for select to authenticated
  using (owner_user_id = (select auth.uid()) or private.can_read_item(item_id));

grant select, delete on public.item_media to authenticated;
grant insert (item_id, asset_id, role, position) on public.item_media to authenticated;
grant update (role, position) on public.item_media to authenticated;
create policy item_media_select on public.item_media for select to authenticated
  using (private.can_read_item(item_id));
create policy item_media_write on public.item_media for insert to authenticated
  with check (private.owns_item(item_id));
create policy item_media_update on public.item_media for update to authenticated
  using (private.owns_item(item_id)) with check (private.owns_item(item_id));
create policy item_media_delete on public.item_media for delete to authenticated
  using (private.owns_item(item_id));

grant select on public.item_embeddings to authenticated;
create policy item_embeddings_select_own on public.item_embeddings for select to authenticated
  using (owner_user_id = (select auth.uid()));

grant select on public.wear_logs to authenticated;
grant insert (id, owner_user_id, worn_on, occasion, event_name, with_people, notes, weather, media_asset_id)
  on public.wear_logs to authenticated;
grant update (worn_on, occasion, event_name, with_people, notes, weather, media_asset_id, deleted_at)
  on public.wear_logs to authenticated;
create policy wear_logs_select on public.wear_logs for select to authenticated
  using (owner_user_id = (select auth.uid()));
create policy wear_logs_insert on public.wear_logs for insert to authenticated
  with check (owner_user_id = (select auth.uid()) and (select private.is_active_adult((select auth.uid()))));
create policy wear_logs_update on public.wear_logs for update to authenticated
  using (owner_user_id = (select auth.uid())) with check (owner_user_id = (select auth.uid()));

grant select, insert, delete on public.wear_log_items to authenticated;
create policy wear_log_items_select on public.wear_log_items for select to authenticated
  using (exists (select 1 from public.wear_logs w where w.id = wear_log_id and w.owner_user_id = (select auth.uid())));
create policy wear_log_items_insert on public.wear_log_items for insert to authenticated
  with check (exists (select 1 from public.wear_logs w where w.id = wear_log_id and w.owner_user_id = (select auth.uid()))
              and private.owns_item(item_id));
create policy wear_log_items_delete on public.wear_log_items for delete to authenticated
  using (exists (select 1 from public.wear_logs w where w.id = wear_log_id and w.owner_user_id = (select auth.uid())));

grant select, delete on public.beauty_details to authenticated;
grant insert (item_id, opened_on, pao_months, expires_on, barcode, shade, spf, skin_types) on public.beauty_details to authenticated;
grant update (opened_on, pao_months, expires_on, barcode, shade, spf, skin_types) on public.beauty_details to authenticated;
create policy beauty_details_select on public.beauty_details for select to authenticated
  using (private.can_read_item(item_id));
create policy beauty_details_insert on public.beauty_details for insert to authenticated
  with check (private.owns_item(item_id));
create policy beauty_details_update on public.beauty_details for update to authenticated
  using (private.owns_item(item_id)) with check (private.owns_item(item_id));
create policy beauty_details_delete on public.beauty_details for delete to authenticated
  using (private.owns_item(item_id));

-- ===========================================================================
-- Plans, entitlements, billing (read-only for clients; written by webhooks)
-- ===========================================================================
grant select on public.entitlement_grants, public.usage_counters, public.subscriptions,
                public.experiment_assignments, public.promo_redemptions, public.referrals
  to authenticated;
create policy entitlement_grants_select_own on public.entitlement_grants for select to authenticated
  using (user_id = (select auth.uid()));
create policy usage_counters_select_own on public.usage_counters for select to authenticated
  using (user_id = (select auth.uid()));
create policy subscriptions_select_own on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()));
create policy experiment_assignments_select_own on public.experiment_assignments for select to authenticated
  using (user_id = (select auth.uid()));
create policy promo_redemptions_select_own on public.promo_redemptions for select to authenticated
  using (user_id = (select auth.uid()));
create policy referrals_select_own on public.referrals for select to authenticated
  using (referrer_user_id = (select auth.uid()) or referred_user_id = (select auth.uid()));

grant select on public.user_entitlements to authenticated;

grant select on public.orders, public.order_lines, public.payments, public.refunds, public.invoices to authenticated;
create policy orders_select_own on public.orders for select to authenticated
  using (buyer_user_id = (select auth.uid()));
create policy order_lines_select_own on public.order_lines for select to authenticated
  using (private.owns_order(order_id));
create policy payments_select_own on public.payments for select to authenticated
  using (private.owns_order(order_id));
create policy refunds_select_own on public.refunds for select to authenticated
  using (exists (select 1 from public.payments p where p.id = payment_id and private.owns_order(p.order_id)));
create policy invoices_select_own on public.invoices for select to authenticated
  using (private.owns_order(order_id));

-- ===========================================================================
-- Notifications and data rights
-- ===========================================================================
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_select_own on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy notifications_update_own on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.notification_preferences to authenticated;
create policy notification_preferences_own on public.notification_preferences for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select on public.deletion_requests, public.data_exports to authenticated;
create policy deletion_requests_select_own on public.deletion_requests for select to authenticated
  using (user_id = (select auth.uid()));
create policy data_exports_select_own on public.data_exports for select to authenticated
  using (user_id = (select auth.uid()));

-- ===========================================================================
-- Server-only public tables (RLS on, no client policy, no client grants):
-- plan_prices (served by plans-catalog per channel), tax_rates, experiments,
-- offers, promo_codes, config_keys, config_versions.
-- ===========================================================================
comment on table public.config_versions is 'Server-only. Admin panel edits through admin functions (role + MFA + audit).';
