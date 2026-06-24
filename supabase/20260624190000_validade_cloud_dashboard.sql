create or replace function public.get_validity_cloud_dashboard(payload jsonb default '{}'::jsonb)
returns jsonb
language sql
security definer
set search_path = public
as $$
with params as (
    select least(greatest(coalesce((payload->>'days')::int, 7), 1), 30) as days
),
summary_data as (
    select jsonb_build_object(
        'devices', (select count(*) from public.validity_devices),
        'active_devices_24h', (
            select count(*)
            from public.validity_devices
            where last_seen_at >= now() - interval '24 hours'
        ),
        'prints_total', (select count(*) from public.validity_print_history),
        'labels_total', (select coalesce(sum(copies), 0) from public.validity_print_history),
        'prints_24h', (
            select count(*)
            from public.validity_print_history
            where printed_at >= now() - interval '24 hours'
        ),
        'labels_24h', (
            select coalesce(sum(copies), 0)
            from public.validity_print_history
            where printed_at >= now() - interval '24 hours'
        ),
        'checks_24h', (
            select count(*)
            from public.validity_check_history
            where checked_at >= now() - interval '24 hours'
        ),
        'expired_labels', (
            select coalesce(sum(copies), 0)
            from public.validity_print_history
            where expiry_at < now()
        ),
        'labels_24h_to_expire', (
            select coalesce(sum(copies), 0)
            from public.validity_print_history
            where expiry_at >= now()
              and expiry_at < now() + interval '24 hours'
        ),
        'labels_7d_to_expire', (
            select coalesce(sum(copies), 0)
            from public.validity_print_history
            where expiry_at >= now()
              and expiry_at < now() + interval '7 days'
        )
    ) as value
),
device_rows as (
    select
        d.app_install_id,
        coalesce(
            nullif(trim(concat_ws(' ', nullif(d.brand, ''), nullif(d.model, ''))), ''),
            'Aparelho ' || left(d.app_install_id::text, 8)
        ) as device_label,
        coalesce(nullif(d.manufacturer, ''), '') as manufacturer,
        coalesce(nullif(d.brand, ''), '') as brand,
        coalesce(nullif(d.model, ''), '') as model,
        coalesce(nullif(d.region_country, ''), '') as region_country,
        d.last_seen_at,
        to_char(d.last_seen_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as last_seen_label,
        count(p.id)::int as prints,
        coalesce(sum(p.copies), 0)::int as labels,
        coalesce(sum(p.copies) filter (
            where p.expiry_at >= now()
              and p.expiry_at < now() + interval '24 hours'
        ), 0)::int as labels_24h,
        coalesce(sum(p.copies) filter (
            where p.expiry_at >= now()
              and p.expiry_at < now() + interval '7 days'
        ), 0)::int as labels_7d,
        min(p.expiry_at) filter (where p.expiry_at >= now()) as next_expiry_at,
        (
            select p2.product
            from public.validity_print_history p2
            where p2.app_install_id = d.app_install_id
              and p2.expiry_at >= now()
            order by p2.expiry_at asc, p2.printed_at desc
            limit 1
        ) as next_product
    from public.validity_devices d
    left join public.validity_print_history p on p.app_install_id = d.app_install_id
    group by d.app_install_id, d.manufacturer, d.brand, d.model, d.region_country, d.last_seen_at
),
devices_data as (
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'device_label', device_label,
            'manufacturer', manufacturer,
            'brand', brand,
            'model', model,
            'region_country', region_country,
            'last_seen_label', last_seen_label,
            'prints', prints,
            'labels', labels,
            'labels_24h', labels_24h,
            'labels_7d', labels_7d,
            'next_product', coalesce(next_product, ''),
            'next_expiry_label', coalesce(to_char(next_expiry_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), '')
        )
        order by coalesce(next_expiry_at, now() + interval '100 years'), last_seen_at desc
    ), '[]'::jsonb) as value
    from (
        select *
        from device_rows
        order by coalesce(next_expiry_at, now() + interval '100 years'), last_seen_at desc
        limit 12
    ) rows
),
expiring_data as (
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'product', product,
            'labels', labels,
            'expiry_label', expiry_label,
            'printed_label', printed_label,
            'device_label', device_label,
            'hours_left', hours_left
        )
        order by expiry_at asc, printed_at desc
    ), '[]'::jsonb) as value
    from (
        select
            p.product,
            p.copies::int as labels,
            p.expiry_at,
            p.printed_at,
            to_char(p.expiry_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as expiry_label,
            to_char(p.printed_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as printed_label,
            floor(extract(epoch from (p.expiry_at - now())) / 3600)::int as hours_left,
            coalesce(
                nullif(trim(concat_ws(' ', nullif(d.brand, ''), nullif(d.model, ''))), ''),
                'Aparelho ' || left(p.app_install_id::text, 8)
            ) as device_label
        from public.validity_print_history p
        left join public.validity_devices d on d.app_install_id = p.app_install_id
        cross join params
        where p.expiry_at >= now() - interval '12 hours'
          and p.expiry_at < now() + (params.days || ' days')::interval
        order by p.expiry_at asc, p.printed_at desc
        limit 30
    ) rows
),
recent_prints_data as (
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'product', product,
            'copies', copies,
            'printed_label', printed_label,
            'expiry_label', expiry_label,
            'device_label', device_label
        )
        order by printed_at desc
    ), '[]'::jsonb) as value
    from (
        select
            p.product,
            p.copies::int as copies,
            p.printed_at,
            to_char(p.printed_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as printed_label,
            to_char(p.expiry_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as expiry_label,
            coalesce(
                nullif(trim(concat_ws(' ', nullif(d.brand, ''), nullif(d.model, ''))), ''),
                'Aparelho ' || left(p.app_install_id::text, 8)
            ) as device_label
        from public.validity_print_history p
        left join public.validity_devices d on d.app_install_id = p.app_install_id
        order by p.printed_at desc
        limit 30
    ) rows
),
recent_checks_data as (
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'product', product,
            'checked_label', checked_label,
            'expiry_label', expiry_label,
            'danger', danger,
            'complete', complete,
            'status', status,
            'device_label', device_label
        )
        order by checked_at desc
    ), '[]'::jsonb) as value
    from (
        select
            c.product,
            c.checked_at,
            to_char(c.checked_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as checked_label,
            coalesce(to_char(c.expiry_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), '') as expiry_label,
            c.danger,
            c.complete,
            coalesce(c.status, '') as status,
            coalesce(
                nullif(trim(concat_ws(' ', nullif(d.brand, ''), nullif(d.model, ''))), ''),
                'Aparelho ' || left(c.app_install_id::text, 8)
            ) as device_label
        from public.validity_check_history c
        left join public.validity_devices d on d.app_install_id = c.app_install_id
        order by c.checked_at desc
        limit 20
    ) rows
)
select jsonb_build_object(
    'generated_label', to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    'summary', summary_data.value,
    'devices', devices_data.value,
    'expiring', expiring_data.value,
    'recent_prints', recent_prints_data.value,
    'recent_checks', recent_checks_data.value
)
from summary_data, devices_data, expiring_data, recent_prints_data, recent_checks_data;
$$;

revoke all on function public.get_validity_cloud_dashboard(jsonb) from public;
grant execute on function public.get_validity_cloud_dashboard(jsonb) to anon, authenticated;
