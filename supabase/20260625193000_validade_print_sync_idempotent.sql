alter table public.validity_print_history
    add column if not exists client_event_id text;

create unique index if not exists validity_print_history_client_event_id_idx
    on public.validity_print_history (client_event_id)
    where client_event_id is not null;

create or replace function public.record_validity_print(payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_app_install_id uuid := nullif(payload->>'app_install_id', '')::uuid;
    v_client_event_id text := nullif(payload->>'client_event_id', '');
begin
    if v_app_install_id is null then
        raise exception 'app_install_id required';
    end if;

    insert into public.validity_devices (app_install_id, first_seen_at, last_seen_at)
    values (v_app_install_id, now(), now())
    on conflict (app_install_id) do update set last_seen_at = now();

    insert into public.validity_print_history (
        app_install_id,
        client_event_id,
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
        v_client_event_id,
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
    )
    on conflict (client_event_id) where client_event_id is not null do nothing;
end;
$$;

revoke all on function public.record_validity_print(jsonb) from public;
grant execute on function public.record_validity_print(jsonb) to anon, authenticated;
