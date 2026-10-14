/* ============================================================
   ILANO — Service Worker
   ------------------------------------------------------------
   מה זה עושה: שומר עותק של האפליקציה במכשיר, כך שהיא
   נפתחת מיד — גם כשאין אינטרנט.

   ⚠️ הנתונים עצמם (בני בית, פעולות) תמיד מגיעים מהשרת.
   כאן נשמר רק "השלד": העמוד, הספרייה, האייקונים.
   ============================================================ */

/* ⚠️ להעלות את המספר רק כשמשנים את הקובץ הזה עצמו.
   v3 = מוחק מכל המכשירים עותקים ישנים של admin.html */
var CACHE = "ilano-v3";
var SHELL = [
  "./",
  "./index.html",
  "./manifest.json",
  "./db/supabase.min.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png"
];

/* התקנה — שומרים את השלד */
self.addEventListener("install", function(e){
  e.waitUntil(
    caches.open(CACHE).then(function(c){
      return c.addAll(SHELL).catch(function(){
        /* קובץ חסר לא יפיל את ההתקנה */
      });
    }).then(function(){ return self.skipWaiting(); })
  );
});

/* הפעלה — מוחקים גרסאות ישנות */
self.addEventListener("activate", function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.map(function(k){
        /* ⚠️ מטמון ה-OCR נשמר בין גרסאות — אחרת כל עדכון
           מאלץ הורדה מחדש של 15MB בסריקה הראשונה */
        if (k === CACHE || k.indexOf("-ocr") > -1) return;
        return caches.delete(k);
      }));
    }).then(function(){ return self.clients.claim(); })
  );
});

/* שליפה */
self.addEventListener("fetch", function(e){
  var url = e.request.url;

  /* 🔴 קריאות לשרת הנתונים — תמיד מהרשת, לעולם לא מהמטמון.
     מידע רפואי ישן מסוכן יותר משגיאת רשת. */
  if (url.indexOf("supabase.co") > -1 || e.request.method !== "GET"){
    return;
  }

  /* 📦 מנוע קריאת הטקסט (Tesseract) ומודל השפה העברית.
     אלה קבצים גדולים — 10-15MB — שלא משתנים לעולם.
     קודם מהמטמון, ואחרי הורדה אחת הסריקה הבאה מיידית.
     בלי זה כל סריקה מורידה אותם מחדש והקריאה נראית תקועה. */
  if (url.indexOf("tesseract") > -1 ||
      url.indexOf("tessdata")  > -1 ||
      /\.traineddata(\.gz)?$/.test(url)){
    e.respondWith(
      caches.open(CACHE + "-ocr").then(function(c){
        return c.match(e.request).then(function(hit){
          if (hit) return hit;
          return fetch(e.request).then(function(res){
            /* ⚠️ opaque response (status 0) נשמר גם — זה תקין ל-CDN */
            if (res && (res.status === 200 || res.type === "opaque")){
              c.put(e.request, res.clone()).catch(function(){});
            }
            return res;
          });
        });
      })
    );
    return;
  }

  /* 🔒 פאנל הניהול — לעולם לא נשמר. אדמין חייב לראות קוד עדכני,
     ואין סיבה שהפאנל יעבוד בלי אינטרנט. */
  if (url.indexOf("admin.html") > -1){
    return;
  }

  /* 📄 עמודים (HTML) — קודם מהרשת, כדי שכל תיקון יגיע מיד.
     no-cache = לבדוק מול GitHub אם יש גרסה חדשה, ולא לחכות
     10 דקות. אם אין רשת, או שהיא לא עונה תוך 4 שניות — מהמטמון. */
  if (e.request.mode === "navigate"){
    e.respondWith(
      caches.match(e.request).then(function(hit){
        var live = fetch(url, {cache: "no-cache"}).then(function(res){
          if (res && res.status === 200){
            var copy = res.clone();
            caches.open(CACHE).then(function(c){ c.put(e.request, copy); });
          }
          return res;
        });
        if (!hit) return live;
        var slow = new Promise(function(done){
          setTimeout(function(){ done(hit); }, 4000);
        });
        return Promise.race([
          live.catch(function(){ return hit; }),
          slow
        ]);
      })
    );
    return;
  }

  /* השלד (ספרייה, אייקונים) — קודם מהמטמון, ומתעדכן ברקע */
  e.respondWith(
    caches.match(e.request).then(function(hit){
      var live = fetch(e.request).then(function(res){
        if (res && res.status === 200){
          var copy = res.clone();
          caches.open(CACHE).then(function(c){ c.put(e.request, copy); });
        }
        return res;
      }).catch(function(){ return hit; });
      return hit || live;
    })
  );
});
