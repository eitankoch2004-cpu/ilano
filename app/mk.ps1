$js = Get-Content -Path 'C:\Users\User\AppData\Local\Temp\code.js' -Encoding UTF8 -Raw
$b = [System.Text.Encoding]::UTF8.GetBytes($js)
$b64 = [Convert]::ToBase64String($b)
$html = @"
<!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<title>בדיקת תחביר</title><style>
body{font-family:system-ui;background:#0A1E38;color:#fff;padding:34px;line-height:1.9}
.ok{color:#7FE6A8;font-weight:900;font-size:26px}
.bad{color:#FF8A7A;font-weight:900;font-size:20px}
pre{background:#000;padding:16px;border-radius:10px;font-size:13px;
overflow:auto;direction:ltr;text-align:left;margin-top:14px}
h2{font-size:20px;margin:0 0 20px}
</style></head><body>
<h2>בדיקת תחביר — קוד האפליקציה</h2>
<div id="r">בודק…</div>
<script>
var B64 = "$b64";
try{
  var bin = atob(B64);
  var bytes = new Uint8Array(bin.length);
  for (var i=0;i<bin.length;i++) bytes[i] = bin.charCodeAt(i);
  var code = new TextDecoder("utf-8").decode(bytes);
  try{
    new Function(code);
    document.getElementById("r").innerHTML =
      '<div class="ok">✓ הקוד תקין</div>' +
      '<p style="color:#8FD9D4;font-size:14px">' + code.length.toLocaleString() +
      ' תווים · אין שגיאות תחביר · מוכן להעלאה</p>';
  }catch(e){
    document.getElementById("r").innerHTML =
      '<div class="bad">✗ שגיאה בקוד</div><pre>' + e.message + '</pre>';
  }
}catch(e){
  document.getElementById("r").innerHTML = '<div class="bad">' + e.message + '</div>';
}
</script></body></html>
"@
Set-Content -Path 'C:\Users\User\OneDrive\Documents\GitHub\ilano\app\syntax-check.html' -Value $html -Encoding UTF8
