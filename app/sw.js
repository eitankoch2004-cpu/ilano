/* ============================================================
   ILANO — Service Worker
   ------------------------------------------------------------
   מה זה עושה: שומר עותק של האפליקציה במכשיר, כך שהיא
   נפתחת מיד — גם כשאין אינטרנט.

   ⚠️ הנתונים עצמם (בני בית, פעולות) תמיד מגיעים מהשרת.
   כאן נשמר רק "השלד": העמוד, הספרייה, האייקונים.
   ============================================================ */

var CACHE = "ilano-v1";
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
        if (k !== CACHE) return caches.delete(k);
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

  /* השלד — קודם מהמטמון, ומתעדכן ברקע */
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
