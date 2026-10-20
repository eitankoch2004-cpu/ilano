-- ============================================================
--  ILANO — תיקון: permission denied for table users
--  ------------------------------------------------------------
--  הבעיה: התצוגה admin_users קוראת מ-auth.users, אבל Supabase
--  חוסמת גישה לסכמת auth מהדפדפן — גם לאדמין.
--
--  הפתרון: פונקציה עם security definer שרצה בהרשאות גבוהות,
--  אבל 🔴 בודקת is_admin() בשורה הראשונה ומסרבת לכל אחד אחר.
--
--  איך מריצים: Supabase → SQL Editor → להדביק → Run
-- ============================================================

-- התצוגה הישנה לא עובדת מהדפדפן — מסירים אותה
drop view if exists public.admin_users;

create or replace function public.admin_users()
returns table (
  user_id        uuid,
  email          text,
  full_name      text,
  signed_up_at   timestamptz,
  last_sign_in_at timestamptz,
  email_verified boolean,
  household_id   uuid,
  household_name text,
  members_count  bigint,
  members_names  text,
  docs_count     bigint,
  plan           text,
  sub_status     text,
  amount_agorot  integer,
  amount_ils     numeric,
  paid_at        timestamptz,
  expires_at     timestamptz,
  provider       text,
  provider_ref   text,
  days_left      int
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- 🔴 שורת ההגנה. בלעדיה כל משתמש היה רואה את כולם.
  if not public.is_admin() then
    raise exception 'not authorized';
  end if;

  return query
  select
    u.id,
    u.email::text,
    coalesce(
      u.raw_user_meta_data->>'full_name',
      nullif(trim(concat(
        u.raw_user_meta_data->>'first_name', ' ',
        u.raw_user_meta_data->>'last_name'
      )), '')
    )::text,
    u.created_at,
    u.last_sign_in_at,
    (u.email_confirmed_at is not null),

    h.id,
    h.name::text,

    (select count(*) from public.members m where m.household_id = h.id),
    (select string_agg(m.name, ', ' order by m.name)
       from public.members m where m.household_id = h.id)::text,
    (select count(*) from public.documents d where d.household_id = h.id),

    s.plan::text,
    s.status::text,
    s.amount_agorot,
    (s.amount_agorot / 100.0)::numeric,
    s.started_at,
    s.expires_at,
    s.provider::text,
    s.provider_ref::text,

    case
      when s.expires_at is null then null
      else extract(day from (s.expires_at - now()))::int
    end

  from auth.users u
  -- משפחה אחת לכל משתמש: זו שיצר, ואם אין — זו שהצטרף אליה
  -- בהזמנה (דרך members.user_id). limit 1 = שורה אחת למשתמש,
  -- גם אם יצר כמה משפחות.
  left join lateral (
    select h2.* from public.households h2
     where h2.created_by = u.id
        or h2.id in (select m.household_id from public.members m
                      where m.user_id = u.id)
     order by (h2.created_by = u.id) desc, h2.id
     limit 1
  ) h on true
  left join lateral (
    select * from public.subscriptions s2
     where s2.user_id = u.id
     order by s2.created_at desc
     limit 1
  ) s on true
  order by u.created_at desc;
end $$;

-- רק משתמש מחובר יכול לנסות. הפונקציה עצמה חוסמת מי שאינו אדמין.
revoke all on function public.admin_users() from public, anon;
grant execute on function public.admin_users() to authenticated;

comment on function public.admin_users() is
  'רשימת המשתמשים לפאנל הניהול. זורקת שגיאה למי שאינו אדמין.';


-- ============================================================
--  בדיקה — רק מהפאנל בדפדפן. ב-SQL Editor זה ייכשל עם
--  not authorized, כי שם אין משתמש מחובר. זה תקין.
-- ============================================================
-- select email, full_name, members_count, plan, amount_ils from public.admin_users();
