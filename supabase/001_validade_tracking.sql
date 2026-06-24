create extension if not exists pgcrypto;

create table if not exists public.validity_devices (
    app_install_id uuid primary key,
    android_id_hash text,
    device_fingerprint text,
    manufacturer text,
    brand text,
    model text,
    device_name text,
    product_name text,
    android_release text,
    sdk_int integer,
    app_version_name text,
    app_version_code integer,
    locale text,
    timezone text,
    region_country text,
    region_language text,
    printer_name text,
    printer_address_hash text,
    printer_address_last4 text,
    metadata jsonb not null default '{}'::jsonb,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now()
);

create table if not exists public.validity_print_history (
    id uuid primary key default gen_random_uuid(),
    app_install_id uuid not null references public.validity_devices(app_install_id) on delete cascade,
    printed_at timestamptz not null default now(),
    product text not null,
    copies integer not null default 1 check (copies > 0 and copies <= 999),
    start_at timestamptz,
    expiry_at timestamptz,
    validity_label text,
    uses_hours boolean not null default false,
    printer_name text,
    printer_address_hash text,
    printer_address_last4 text,
    source text not null default 'android_validity_print',
    locale text,
    timezone text,
    region_country text,
    region_language text,
    app_version_name text,
    app_version_code integer,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create table if not exists public.validity_check_history (
    id uuid primary key default gen_random_uuid(),
    app_install_id uuid not null references public.validity_devices(app_install_id) on delete cascade,
    checked_at timestamptz not null default now(),
    product text not null default 'Produto OCR',
    start_at timestamptz,
    expiry_at timestamptz,
    status text,
    danger boolean not null default false,
    complete boolean not null default false,
    raw_text text,
    source text not null default 'android_ocr',
    locale text,
    timezone text,
    region_country text,
    region_language text,
    app_version_name text,
    app_version_code integer,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists validity_print_history_printed_at_idx
    on public.validity_print_history (printed_at desc);

create index if not exists validity_print_history_device_idx
    on public.validity_print_history (app_install_id, printed_at desc);

create index if not exists validity_print_history_expiry_idx
    on public.validity_print_history (expiry_at, product);

create index if not exists validity_check_history_checked_at_idx
    on public.validity_check_history (checked_at desc);

create index if not exists validity_check_history_device_idx
    on public.validity_check_history (app_install_id, checked_at desc);

alter table public.validity_devices enable row level security;
alter table public.validity_print_history enable row level security;
alter table public.validity_check_history enable row level security;

revoke all on table public.validity_devices from anon, authenticated;
revoke all on table public.validity_print_history from anon, authenticated;
revoke all on table public.validity_check_history from anon, authenticated;

create or replace function public.upsert_validity_device(payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_app_install_id uuid := nullif(payload->>'app_install_id', '')::uuid;
begin
    if v_app_install_id is null then
        raise exception 'app_install_id required';
    end if;

    insert into public.validity_devices (
        app_install_id,
        android_id_hash,
        device_fingerprint,
        manufacturer,
        brand,
        model,
        device_name,
        product_name,
        android_release,
        sdk_int,
        app_version_name,
        app_version_code,
        locale,
        timezone,
        region_country,
        region_language,
        printer_name,
        printer_address_hash,
        printer_address_last4,
        metadata,
        first_seen_at,
        last_seen_at
    ) values (
        v_app_install_id,
        nullif(payload->>'android_id_hash', ''),
        nullif(payload->>'device_fingerprint', ''),
        nullif(payload->>'manufacturer', ''),
        nullif(payload->>'brand', ''),
        nullif(payload->>'model', ''),
        nullif(payload->>'device_name', ''),
        nullif(payload->>'product_name', ''),
        nullif(payload->>'android_release', ''),
        nullif(payload->>'sdk_int', '')::integer,
        nullif(payload->>'app_version_name', ''),
        nullif(payload->>'app_version_code', '')::integer,
        nullif(payload->>'locale', ''),
        nullif(payload->>'timezone', ''),
        nullif(payload->>'region_country', ''),
        nullif(payload->>'region_language', ''),
        nullif(payload->>'printer_name', ''),
        nullif(payload->>'printer_address_hash', ''),
        nullif(payload->>'printer_address_last4', ''),
        coalesce(payload->'metadata', '{}'::jsonb),
        now(),
        now()
    )
    on conflict (app_install_id) do update set
        android_id_hash = coalesce(excluded.android_id_hash, public.validity_devices.android_id_hash),
        device_fingerprint = coalesce(excluded.device_fingerprint, public.validity_devices.device_fingerprint),
        manufacturer = coalesce(excluded.manufacturer, public.validity_devices.manufacturer),
        brand = coalesce(excluded.brand, public.validity_devices.brand),
        model = coalesce(excluded.model, public.validity_devices.model),
        device_name = coalesce(excluded.device_name, public.validity_devices.device_name),
        product_name = coalesce(excluded.product_name, public.validity_devices.product_name),
        android_release = coalesce(excluded.android_release, public.validity_devices.android_release),
        sdk_int = coalesce(excluded.sdk_int, public.validity_devices.sdk_int),
        app_version_name = coalesce(excluded.app_version_name, public.validity_devices.app_version_name),
        app_version_code = coalesce(excluded.app_version_code, public.validity_devices.app_version_code),
        locale = coalesce(excluded.locale, public.validity_devices.locale),
        timezone = coalesce(excluded.timezone, public.validity_devices.timezone),
        region_country = coalesce(excluded.region_country, public.validity_devices.region_country),
        region_language = coalesce(excluded.region_language, public.validity_devices.region_language),
        printer_name = coalesce(excluded.printer_name, public.validity_devices.printer_name),
        printer_address_hash = coalesce(excluded.printer_address_hash, public.validity_devices.printer_address_hash),
        printer_address_last4 = coalesce(excluded.printer_address_last4, public.validity_devices.printer_address_last4),
        metadata = public.validity_devices.metadata || excluded.metadata,
        last_seen_at = now();
end;
$$;

create or replace function public.record_validity_print(payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_app_install_id uuid := nullif(payload->>'app_install_id', '')::uuid;
begin
    if v_app_install_id is null then
        raise exception 'app_install_id required';
    end if;

    insert into public.validity_devices (app_install_id, first_seen_at, last_seen_at)
    values (v_app_install_id, now(), now())
    on conflict (app_install_id) do update set last_seen_at = now();

    insert into public.validity_print_history (
        app_install_id,
        printed_at,
        product,
        copies,
        start_at,
        expiry_at,
        validity_label,
        uses_hours,
        printer_name,
        printer_address_hash,
        printer_address_last4,
        source,
        locale,
        timezone,
        region_country,
        region_language,
        app_version_name,
        app_version_code,
        metadata
    ) values (
        v_app_install_id,
        coalesce(to_timestamp(nullif(payload->>'printed_at_ms', '')::numeric / 1000.0), now()),
        coalesce(nullif(payload->>'product', ''), 'Produto'),
        greatest(1, least(999, coalesce(nullif(payload->>'copies', '')::integer, 1))),
        case when coalesce(nullif(payload->>'start_at_ms', '')::numeric, 0) > 0
            then to_timestamp((payload->>'start_at_ms')::numeric / 1000.0)
            else null end,
        case when coalesce(nullif(payload->>'expiry_at_ms', '')::numeric, 0) > 0
            then to_timestamp((payload->>'expiry_at_ms')::numeric / 1000.0)
            else null end,
        nullif(payload->>'validity_label', ''),
        coalesce((payload->>'uses_hours')::boolean, false),
        nullif(payload->>'printer_name', ''),
        nullif(payload->>'printer_address_hash', ''),
        nullif(payload->>'printer_address_last4', ''),
        coalesce(nullif(payload->>'source', ''), 'android_validity_print'),
        nullif(payload->>'locale', ''),
        nullif(payload->>'timezone', ''),
        nullif(payload->>'region_country', ''),
        nullif(payload->>'region_language', ''),
        nullif(payload->>'app_version_name', ''),
        nullif(payload->>'app_version_code', '')::integer,
        coalesce(payload->'metadata', '{}'::jsonb)
    );
end;
$$;

create or replace function public.record_validity_check(payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_app_install_id uuid := nullif(payload->>'app_install_id', '')::uuid;
begin
    if v_app_install_id is null then
        raise exception 'app_install_id required';
    end if;

    insert into public.validity_devices (app_install_id, first_seen_at, last_seen_at)
    values (v_app_install_id, now(), now())
    on conflict (app_install_id) do update set last_seen_at = now();

    insert into public.validity_check_history (
        app_install_id,
        checked_at,
        product,
        start_at,
        expiry_at,
        status,
        danger,
        complete,
        raw_text,
        source,
        locale,
        timezone,
        region_country,
        region_language,
        app_version_name,
        app_version_code,
        metadata
    ) values (
        v_app_install_id,
        coalesce(to_timestamp(nullif(payload->>'checked_at_ms', '')::numeric / 1000.0), now()),
        coalesce(nullif(payload->>'product', ''), 'Produto OCR'),
        case when coalesce(nullif(payload->>'start_at_ms', '')::numeric, 0) > 0
            then to_timestamp((payload->>'start_at_ms')::numeric / 1000.0)
            else null end,
        case when coalesce(nullif(payload->>'expiry_at_ms', '')::numeric, 0) > 0
            then to_timestamp((payload->>'expiry_at_ms')::numeric / 1000.0)
            else null end,
        nullif(payload->>'status', ''),
        coalesce((payload->>'danger')::boolean, false),
        coalesce((payload->>'complete')::boolean, false),
        nullif(payload->>'raw_text', ''),
        coalesce(nullif(payload->>'source', ''), 'android_ocr'),
        nullif(payload->>'locale', ''),
        nullif(payload->>'timezone', ''),
        nullif(payload->>'region_country', ''),
        nullif(payload->>'region_language', ''),
        nullif(payload->>'app_version_name', ''),
        nullif(payload->>'app_version_code', '')::integer,
        coalesce(payload->'metadata', '{}'::jsonb)
    );
end;
$$;

revoke all on function public.upsert_validity_device(jsonb) from public;
revoke all on function public.record_validity_print(jsonb) from public;
revoke all on function public.record_validity_check(jsonb) from public;

grant execute on function public.upsert_validity_device(jsonb) to anon, authenticated;
grant execute on function public.record_validity_print(jsonb) to anon, authenticated;
grant execute on function public.record_validity_check(jsonb) to anon, authenticated;

create or replace view public.validity_print_daily_summary as
select
    date_trunc('day', printed_at)::date as printed_day,
    product,
    count(*) as print_events,
    sum(copies) as total_labels,
    count(distinct app_install_id) as devices_used
from public.validity_print_history
group by 1, 2;

create or replace view public.validity_check_daily_summary as
select
    date_trunc('day', checked_at)::date as checked_day,
    product,
    count(*) as checks,
    count(*) filter (where danger) as danger_checks,
    count(*) filter (where complete) as complete_checks,
    count(distinct app_install_id) as devices_used
from public.validity_check_history
group by 1, 2;

revoke all on table public.validity_print_daily_summary from anon, authenticated;
revoke all on table public.validity_check_daily_summary from anon, authenticated;
