-- ============================================================
--  ILANO — מערכת ניהול: מנויים ותשלומים
--  ------------------------------------------------------------
--  מה זה עושה:
--    1. יוצר טבלת subscriptions — מי שילם, כמה, עד מתי
--    2. יוצר תצוגת admin_users — כל המשתמשים במקום אחד
--    3. מגדיר הרשאות: רק אדמין רואה את זה
--
--  ⚠️ סיסמאות לא נשמרות ולא נחשפות. Supabase שומרת אותן
--     כ-hash חד-כיווני, וזה הדבר הנכון. במקום זה יש
--     כפתור "שלח קישור איפוס" בפאנל הניהול.
--
--  איך מריצים: Supabase → SQL Editor → להדביק → Run
-- ============================================================


-- ============================================================
--  1. מי אדמין
-- ============================================================
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  added_at   timestamptz not null default now(),
  note       text
);

alter table public.admins enable row level security;

-- פונקציה שבודקת אם המשתמש הנוכחי אדמין.
-- security definer = רצה בהרשאות של היוצר, כדי שלא
-- תיווצר לופ אינסופי של בדיקות הרשאה.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins where user_id = auth.uid()
  );
$$;

-- אדמין רואה את רשימת האדמינים. אף אחד אחר לא.
drop policy if exists "admins read" on public.admins;
create policy "admins read" on public.admins
  for select using (public.is_admin());


-- ============================================================
--  2. מנויים ותשלומים
-- ============================================================
create table if not exists public.subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  household_id  uuid references public.households(id) on delete set null,

  -- מה הוא קיבל
  plan          text not null default 'free'
                check (plan in ('free','trial','monthly','yearly','lifetime')),
  status        text not null default 'active'
                check (status in ('active','past_due','canceled','expired')),

  -- כמה שילם — באגורות, כדי למנוע שגיאות עיגול.
  -- 4900 אגורות = 49 ₪
  amount_agorot integer not null default 0 check (amount_agorot >= 0),
  currency      text    not null default 'ILS',

  -- לכמה זמן
  started_at    timestamptz not null default now(),
  expires_at    timestamptz,          -- null = ללא הגבלה (lifetime)

  -- מאיפה הכסף הגיע
  provider      text,                 -- 'bit' / 'paybox' / 'card' / 'manual'
  provider_ref  text,                 -- מספר אסמכתא מספק התשלום
  note          text,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists subs_user_idx    on public.subscriptions(user_id);
create index if not exists subs_status_idx  on public.subscriptions(status);
create index if not exists subs_expires_idx on public.subscriptions(expires_at);

alter table public.subscriptions enable row level security;

-- המשתמש רואה רק את המנוי שלו
drop policy if exists "own subscription" on public.subscriptions;
create policy "own subscription" on public.subscriptions
  for select using (user_id = auth.uid());

-- אדמין רואה הכל
drop policy if exists "admin reads subs" on public.subscriptions;
create policy "admin reads subs" on public.subscriptions
  for select using (public.is_admin());

-- רק אדמין כותב. ⚠️ קריטי: בלי זה כל משתמש יכול
-- לתת לעצמו מנוי lifetime בחינם דרך ה-API.
-- מפורדות לפי פעולה ולא "for all", כדי שיהיה חד-משמעי
-- ש-insert נאכף דרך with check (ל-insert אין using).
drop policy if exists "admin writes subs"  on public.subscriptions;
drop policy if exists "admin insert subs"  on public.subscriptions;
drop policy if exists "admin update subs"  on public.subscriptions;
drop policy if exists "admin delete subs"  on public.subscriptions;

create policy "admin insert subs" on public.subscriptions
  for insert with check (public.is_admin());

create policy "admin update subs" on public.subscriptions
  for update using (public.is_admin()) with check (public.is_admin());

create policy "admin delete subs" on public.subscriptions
  for delete using (public.is_admin());

-- updated_at מתעדכן לבד
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists subs_touch on public.subscriptions;
create trigger subs_touch before update on public.subscriptions
  for each row execute function public.touch_updated_at();


-- ============================================================
--  3. התצוגה שפאנל הניהול קורא
--     ⚠️ security_invoker = on — התצוגה נאכפת לפי
--     ההרשאות של מי שקורא אותה, לא של מי שיצר אותה.
--     בלי זה כל משתמש היה רואה את כל המשתמשים.
-- ============================================================
create or replace view public.admin_users
with (security_invoker = on)
as
select
  u.id                                    as user_id,
  u.email,
  coalesce(
    u.raw_user_meta_data->>'full_name',
    trim(concat(
      u.raw_user_meta_data->>'first_name', ' ',
      u.raw_user_meta_data->>'last_name'
    ))
  )                                       as full_name,
  u.created_at                            as signed_up_at,
  u.last_sign_in_at,
  (u.email_confirmed_at is not null)      as email_verified,

  h.id                                    as household_id,
  h.name                                  as household_name,

  -- כמה בני משפחה הוסיף
  (select count(*) from public.members m
    where m.household_id = h.id)          as members_count,

  -- שמות בני המשפחה, מופרדים בפסיק
  (select string_agg(m.name, ', ' order by m.name)
     from public.members m
    where m.household_id = h.id)          as members_names,

  -- כמה מסמכים העלה
  (select count(*) from public.documents d
    where d.household_id = h.id)          as docs_count,

  -- התשלום הפעיל האחרון
  s.plan,
  s.status                                as sub_status,
  s.amount_agorot,
  (s.amount_agorot / 100.0)               as amount_ils,
  s.started_at                            as paid_at,
  s.expires_at,
  s.provider,
  s.provider_ref,

  -- כמה ימים נשארו. שלילי = פג.
  case
    when s.expires_at is null then null
    else extract(day from (s.expires_at - now()))::int
  end                                     as days_left

from auth.users u
left join public.households h
       on h.created_by = u.id
left join lateral (
  select * from public.subscriptions s2
   where s2.user_id = u.id
   order by s2.created_at desc
   limit 1
) s on true
where public.is_admin();     -- 🔴 שורת ההגנה: לא אדמין → אפס שורות

comment on view public.admin_users is
  'תצוגת ניהול. סיסמאות לא נחשפות — Supabase שומרת אותן כ-hash.';


-- ============================================================
--  4. להפוך את עצמך לאדמין
--     ⚠️ להחליף את המייל בשלך לפני ההרצה
-- ============================================================
insert into public.admins (user_id, note)
select id, 'owner'
  from auth.users
 where email = 'eitankoch2004@gmail.com'
on conflict (user_id) do nothing;


-- ============================================================
--  5. בדיקות — להריץ אחרי ההתקנה
-- ============================================================

-- א. אני אדמין? אמור להחזיר true
-- select public.is_admin();

-- ב. רשימת המשתמשים. אמורה להחזיר שורות.
-- select email, full_name, members_count, plan, amount_ils, days_left
--   from public.admin_users;

-- ג. 🔴 הבדיקה החשובה: אילו טבלאות חשופות?
--    כל טבלה ב-public חייבת rls_enabled = true.
--    אם משהו שם false — זו דלת פתוחה למידע רפואי.
-- select
--   c.relname                                as table_name,
--   c.relrowsecurity                         as rls_enabled,
--   (select count(*) from pg_policies p
--     where p.schemaname='public' and p.tablename=c.relname) as policies
-- from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
-- order by c.relrowsecurity, c.relname;

-- ד. טבלה עם RLS פעיל אבל אפס policies = אף אחד לא רואה כלום.
--    טבלה בלי RLS = כולם רואים הכל. שתיהן בעיה.
