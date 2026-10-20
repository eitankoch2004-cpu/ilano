/* ============================================================
   ILANO — ניטור תקלות
   ------------------------------------------------------------
   מה זה עושה: כל שגיאה שקורית אצל משתמש נשמרת בטבלה
   app_errors ב-Supabase, ומופיעה בפאנל הניהול.

   🔒 נשלח רק: הודעת השגיאה, מיקום בקוד (stack), נתיב העמוד
      ודפדפן. לעולם לא תוכן, שמות, מסמכים או מה שהוקלד.
      הכתובת נשלחת בלי ? ו-# — שם יושבים קודי הזמנה וטוקנים.

   ⚠️ חייב להיטען ראשון ב-<head>, כדי לתפוס שגיאות מכל מה
      שנטען אחריו.

   ידני: logIssue("תיאור") — לשגיאה שהקוד תפס בעצמו.
   ============================================================ */

(function(){
  var APP    = "ilano";
  var SB_URL = "https://egefetbuvuxromcwtsie.supabase.co";
  /* המפתח הציבורי (anon) — בטוח בדפדפן. ההגנה היא ב-RLS. */
  var SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVnZWZldGJ1dnV4cm9tY3d0c2llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA1MzIyNDMsImV4cCI6MjEwNjEwODI0M30.UTdsjC-itR5taABeFHNzDqVI2zr0FPHFGnSZtF2SGzA";

  /* עד 20 דיווחים לטעינת עמוד, ואותה הודעה פעם אחת בלבד */
  var MAX = 20, sent = 0, seen = {};

  function report(msg, stack){
    try{
      msg = String(msg || "").slice(0, 500);
      if (!msg || sent >= MAX || seen[msg]) return;
      /* "Script error." = שגיאה מקובץ של אתר אחר, בלי שום פרט שימושי */
      if (msg === "Script error.") return;
      /* תוספים של הדפדפן — לא הקוד שלנו */
      if (/extension:\/\//.test(String(stack || ""))) return;
      seen[msg] = 1;
      sent++;

      var args = {
        p_app:     APP,
        p_message: msg,
        p_stack:   String(stack || "").slice(0, 4000),
        p_page:    location.origin + location.pathname,
        p_ua:      navigator.userAgent
      };

      /* עם הלקוח של Supabase — כך נשמר גם מי המשתמש */
      if (window.sb && window.sb.rpc){
        window.sb.rpc("log_error", args).then(function(){}, function(){});
        return;
      }
      /* לפני שהלקוח נטען — ישירות, כאורח */
      fetch(SB_URL + "/rest/v1/rpc/log_error", {
        method: "POST",
        keepalive: true,
        headers: {
          "apikey": SB_KEY,
          "Authorization": "Bearer " + SB_KEY,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(args)
      }).catch(function(){});
    }catch(e){
      /* 🔴 הניטור לעולם לא מפיל את האפליקציה */
    }
  }

  /* שגיאה בקוד */
  window.addEventListener("error", function(e){
    /* תמונה או קובץ שלא נטענו — אין להם message, מדלגים */
    if (!e.message) return;
    report(e.message, e.error && e.error.stack);
  });

  /* פעולה אסינכרונית שנכשלה ואף אחד לא טיפל בה */
  window.addEventListener("unhandledrejection", function(e){
    var r = e.reason;
    report((r && r.message) || r, r && r.stack);
  });

  window.logIssue = report;
})();
