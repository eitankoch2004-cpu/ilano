-- ============================================================
--  ILANO — ניטור תקלות
--  ------------------------------------------------------------
--  מה זה עושה:
--    1. טבלת app_errors — כל שגיאה שקרתה אצל משתמש
--    2. פונקציה log_error() — הדרך היחידה לכתוב לטבלה
--    3. הרשאות: רק אדמין קורא. אף אחד לא כותב ישירות.
--
--  🔒 פרטיות: נשמרים רק הודעת שגיאה, מיקום בקוד (stack),
--     נתיב העמוד ודפדפן. לעולם לא תוכן, שמות או מסמכים.
--
--  איך מריצים: Supabase → SQL Editor → להדביק → Run
--  אפשר להריץ שוב בלי נזק.
-- ============================================================


-- ============================================================
--  1. הטבלה
-- ============================================================
create table if not exists public.app_errors (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  app         text not null,          -- 'ilano' / 'luma' / ...
  message     text not null,
  stack       text,
  page        text,                   -- נתיב בלבד, בלי ? ו-#
  user_agent  text,
  user_id     uuid                    -- null = לא מחובר
);

create index if not exists app_errors_created_idx
  on public.app_errors (created_at desc);

alter table public.app_errors enable row level security;

-- רק אדמין קורא.
-- ⚠️ אין policy לכתיבה בכוונה: כותבים רק דרך log_error(),
--    שמגבילה גודל וכמות.
drop policy if exists "admin reads errors" on public.app_errors;
create policy "admin reads errors" on public.app_errors
  for select using (public.is_admin());

-- אדמין יכול למחוק תקלות שטופלו
drop policy if exists "admin deletes errors" on public.app_errors;
create policy "admin deletes errors" on public.app_errors
  for delete using (public.is_admin());

-- ⚠️ בפרויקט הזה Supabase לא נותן הרשאות אוטומטיות לטבלה חדשה.
--    בלי השורה הזו גם האדמין מקבל permission denied בפאנל.
--    ה-RLS למעלה עדיין קובע שרק אדמין רואה שורות.
--    ל-anon (מי שלא מחובר) לא נותנים כלום — הוא כותב רק דרך log_error().
grant select, delete on public.app_errors to authenticated;


-- ============================================================
--  2. הפונקציה שהאפליקציה קוראת לה
-- ============================================================
create or replace function public.log_error(
  p_app     text,
  p_message text,
  p_stack   text default null,
  p_page    text default null,
  p_ua      text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_message is null or length(trim(p_message)) = 0 then
    return;
  end if;

  -- אותה שגיאה מאותו משתמש ודפדפן בדקה האחרונה → מדלגים
  if exists (
    select 1 from public.app_errors e
     where e.message = left(p_message, 500)
       and e.user_id is not distinct from auth.uid()
       and e.user_agent is not distinct from left(p_ua, 300)
       and e.created_at > now() - interval '60 seconds'
  ) then
    return;
  end if;

  -- 🔴 תקרה: עד 500 שגיאות בשעה בסך הכל.
  --    כדי שאף אחד לא יוכל למלא את מסד הנתונים החינמי.
  if (select count(*) from public.app_errors
       where created_at > now() - interval '1 hour') >= 500 then
    return;
  end if;

  insert into public.app_errors (app, message, stack, page, user_agent, user_id)
  values (
    left(coalesce(p_app, 'unknown'), 40),
    left(p_message, 500),
    left(p_stack, 4000),
    left(p_page, 300),
    left(p_ua, 300),
    auth.uid()
  );
end $$;

-- גם מי שלא מחובר יכול לדווח — שגיאה במסך הכניסה חשובה במיוחד
revoke all on function public.log_error(text, text, text, text, text) from public;
grant execute on function public.log_error(text, text, text, text, text)
  to anon, authenticated;

comment on table public.app_errors is
  'ניטור תקלות. נכתב רק דרך log_error(). רק אדמין קורא.';


-- ============================================================
--  3. בדיקה — אמורה להחזיר שורה אחת עם "בדיקה מה-SQL Editor"
-- ============================================================
select public.log_error('ilano', 'בדיקה מה-SQL Editor');

select id, created_at, app, message
  from public.app_errors
 order by id desc
 limit 5;
