# 🚀 Windows MCP Server & Remote AI Desktop Controller

دليل التثبيت الشامل والتشغيل التلقائي لخادم **Windows MCP Server** الذي يحول جهازك إلى خادم ذكاء اصطناعي تفاعلي متكامل للتحكم بسطح المكتب وكافة برامج الويندوز (**Excel, Word, Outlook, Telegram, المتصفحات، الملفات، PowerShell، الخدمات، وإدارة النظام بالكامل**) عن بُعد عبر **Claude** و **ChatGPT** دون الحاجة لفتح أي منفذ (Port) في الراوتر.

المشروع مبني اعتماداً على المحرك الرسمي مفتوح المصدر:
[deploymenttheory/windows-mcp-server](https://github.com/deploymenttheory/windows-mcp-server)

---

## 📦 مشروع محمول بالكامل (100% Portable)
تمت برمجة هذا المشروع بالكامل ليكون مستقلاً ومحمولاً (`Self-Contained & Path-Independent`):
- يمكن لأي شخص أخذ نسخة من المجلد أو تحميله على أي جهاز كمبيوتر أو لابتوب يعمل بنظام Windows.
- لا توجد أي مسارات ثابتة (Hardcoded Paths) — يتعرف النظام تلقائياً على موقعه أينما وُضع.
- يعمل على الفور بمجرد النقر المزدوج على ملف **`install.bat`** أو تشغيل **`install.ps1`**.

---

## ⚡ 1. التثبيت السريع (Turnkey One-Liner / Double-Click)

### الطريقة الأولى (الأسلم والأسهل):
1. قم بتحميل أو استنساخ المشروع:
   ```bash
   git clone https://github.com/ahmadElsharawy/WinMCP.git
   cd WinMCP
   ```
2. انقر نقراً مزدوجاً فوق ملف **`install.bat`**.

### الطريقة الثانية (عبر PowerShell):
افتح نافذة **PowerShell** داخل مجلد المشروع، ونفذ:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; .\install.ps1
```

### ماذا يفعل التثبيت التلقائي؟
1. **يكتشف المسار تلقائياً**: يحدد مجلد المشروع ومسارات البرامج دون أي تدخل منك.
2. **يجهز نفق Cloudflare Tunnel**: يتيح لك الاختيار بين نفق فوري مجاني (Quick Tunnel) أو نطاقك الخاص (Custom Domain).
3. **يتحقق من بيئة العمل**: يفحص وجود Python ويثبت المكتبات الخفيفة اللازمة (`flask`, `requests`).
4. **ينزل المحركات الرسمية**: يوفر أحدث باينري لـ `windows-mcp-server.exe` و `cloudflared.exe` و `nssm.exe`.
5. **يولد مفتاح أمان مشفر**: ينشئ مفتاح أمان عشوائي فائق التشفير (256-bit Bearer Token) في ملف محمي `.env`.
6. **يفعل التشغيل التلقائي المزدوج في الخلفية (Background Services)**:
   - يبرمج مهمة في مجدول مهام ويندوز (**Windows Task Scheduler**) باسم `WindowsMCPServer`.
   - ينشئ مشغلاً صامتاً (`WinMCP_AutoStart.vbs`) في مجلد بدء التشغيل (**Startup Folder**).
   - يضمن استمرار الخادم دائماً وتشغيله التلقائي عند تشغيل الكمبيوتر وبعد كل ريستارت.
7. **يضيف أداة الإدارة `winmcp` إلى الـ PATH**: لتتمكن من كتابة `winmcp` من أي مكان في النظام.
8. **يشغل الخادم فوراً**: ويطبع لك الروابط الجاهزة للنسخ إلى Claude و ChatGPT مع مفتاح الأمان.

---

## 🔄 2. خيارات التشغيل في الخلفية وخدمات الويندوز (Background Services & Reboot Survival)

يوفر المشروع نظامين متكاملين للتشغيل في الخلفية لضمان ملاءمته لكافة الاستخدامات:

### الوضع الأول: التشغيل التفاعلي الذاتي (Interactive Desktop Service - مفعل افتراضياً)
- **كيف يعمل**: يتم تشغيله تلقائياً مع بدء تشغيل الويندوز/تسجيل الدخول في الخلفية وبشكل صامت تام.
- **الميزة الحصرية**: يمتلك وصولاً كاملاً إلى جلسة المستخدم الحقيقية (User Desktop Session)، مما يتيح للذكاء الاصطناعي:
  - فتح والتعامل المباشر مع برامج سطح المكتب: **Excel, Word, Outlook, Telegram, Chrome, Edge**.
  - رؤية شجرة عناصر الواجهة التفاعلية (`Snapshot`).
  - أخذ لقطات حقيقية لسطح المكتب (`Screenshot`).
  - محاكاة النقر والكتابة بالأزرار والماوس دون أي عزل أمني (No Session 0 Isolation).
- **التحكم**:
  ```powershell
  winmcp autostart enable   # تفعيل التشغيل التلقائي مع الويندوز
  winmcp autostart disable  # إلغاء التشغيل التلقائي
  ```

### الوضع الثاني: خدمة ويندوز الدائمة (Native Windows Service عبر NSSM)
- **كيف يعمل**: يسجل الخادم كخدمة نظام حقيقية باسم `WinMCP-Service` داخل مدير خدمات الويندوز (`services.msc`).
- **الميزة الحصرية**: يقلع مع إقلاع نظام التشغيل وقبل تسجيل دخول أي مستخدم (مناسب للسيرفرات والأجهزة السحابية التي تعمل دون شاشة/Headless).
- **التحكم**:
  ```powershell
  winmcp service install    # تثبيت وتشغيل كخدمة ويندوز دائمة (يطلب صلاحية Admin تلقائياً)
  winmcp service start      # بدء تشغيل الخدمة
  winmcp service stop       # إيقاف الخدمة
  winmcp service uninstall  # حذف الخدمة من النظام
  ```

---

## 🌐 3. خيارات نفق Cloudflare Tunnel (بدون Port Forwarding)

يعمل المشروع خلف أي راوتر منزلي أو شبكة شركات دون الحاجة لفتح بورتات إطلاقاً:

### الخيار (1): Quick Tunnel (مجاني وفوري - بدون دومين وبدون حساب) [موصى به]
- **كيف يعمل**: ينشئ نفقاً مؤقتاً مشفراً على نطاق `*.trycloudflare.com`.
- **المميزات**: يعمل فوراً بضغطة زر دون أي متطلبات، ويعطيك رابط HTTPS آمن ومحمي بالمفتاح السري.
- **ملاحظة**: يمكنك معرفة الرابط النشط في أي وقت بكتابة:
  ```powershell
  winmcp status
  ```

### الخيار (2): Custom Domain Tunnel (نطاقك الخاص الدائم)
إذا كنت تمتلك دومين وتريد رابطاً ثابتاً لا يتغير أبداً (مثل `https://mcp.yourdomain.com`):
1. في لوحة [Cloudflare Zero Trust](https://one.dash.cloudflare.com) -> Networks -> Tunnels:
   - أنشئ نفقاً جديداً وانسخ الـ **Tunnel Token** (يبدأ بـ `eyJh...`).
   - اربط الـ Public Hostname مع: Service Type = `HTTP`, URL = `localhost:8765`.
2. أدخل الـ Token واسم الدومين عند تشغيل سكريبت التثبيت وسيقوم بضبطه دائماً.

---

## 🛠️ 4. لوحة وأداة الإدارة السريعة (`winmcp`)

تم تجهيز أداة CLI متطورة تتيح لك إدارة السيرفر من أي موجه أوامر في أي مسار:

```powershell
# عرض لوحة الحالة الشاملة والرابط الخارجي النشط وحالة الخدمات
winmcp status

# تشغيل الخادم والنفق السحابي يدوياً
winmcp start

# إيقاف الخادم والنفق بالكامل
winmcp stop

# إعادة تشغيل السيرفر وتحديث النفق
winmcp restart

# تثبيت الخادم كخدمة ويندوز نظامية 24/7
winmcp service install

# إزالة خدمة الويندوز
winmcp service uninstall

# تفعيل / إلغاء التشغيل التلقائي مع تسجيل الدخول
winmcp autostart enable
winmcp autostart disable

# متابعة أوامر الـ AI وسجلات التدقيق لحظياً (Live Logs)
winmcp logs

# عرض مفتاح الأمان (Bearer Token) لنسخه
winmcp token

# توليد مفتاح أمان عشوائي جديد فائق التشفير (256-bit Random)
winmcp token new

# تعيين مفتاح أمان مخصص من كتابتك واختيارك (Custom Token)
winmcp token set <your_custom_key>

# فتح معالج تغيير مفتاح الأمان التفاعلي
winmcp token change

# حذف وإلغاء تثبيت المشروع من كامل جذوره وتصفير النظام
winmcp uninstall

# أو ببساطة: انقر نقراً مزدوجاً على ملف change_token.bat أو uninstall.bat من سطح المكتب!

# عرض رسالة المساعدة وجميع الخيارات
winmcp help
```

---

## 🔑 4.1 إدارة وتغيير مفتاح الأمان (Token Management)

يمكنك تغيير مفتاح الأمان (Bearer Token) في أي وقت وبمنتهى السهولة بطريقتين:

1. **توليد مفتاح عشوائي مشفر تلقائياً (Random 256-bit Token)**:
   - عبر موجه الأوامر:
     ```powershell
     winmcp token new
     ```
   - ينشئ مفتاحاً عشوائياً قوياً من 64 خانة بنظام التشفير الآمن ويعيد تشغيل السيرفر فوراً.

2. **تعيين مفتاح أمان مخصص من كتابتك (Custom Token)**:
   - عبر موجه الأوامر:
     ```powershell
     winmcp token set MySecretPassword123
     ```
   - أو تشغيل المعالج التفاعلي:
     ```powershell
     winmcp token change
     ```
   - أو بالنقر المزدوج على ملف **`change_token.bat`** واختيار `[2]` لكتابة المفتاح المخصص الذي تفضله.

> **ملاحظة**: يقوم السيرفر بحفظ المفتاح الجديد في ملف الإعدادات `.env` وتحديث الجلسة وإعادة تشغيل الخادم تلقائياً دون أي تدخل يدوي!

---

## 🗑️ 4.2 إلغاء التثبيت وحذف المشروع من كامل جذوره (Complete Root Uninstaller)

إذا أردت تصفير النظام أو حذف المشروع وإلغاء تثبيته بالكامل لإعادة التجربة من الصفر:

### 1. الطريقة السريعة (نقر مزدوج):
انقر نقراً مزدوجاً فوق ملف:
👉 **`uninstall.bat`**

### 2. عبر موجه الأوامر:
```powershell
winmcp uninstall
# أو
.\uninstall.ps1
```

### ماذا يفعل معالج الحذف من الجذور؟
1. **يقفل وينهي كافة العمليات الجارية**: (`windows-mcp-server`, `cloudflared`, `python/gateway`).
2. **يحذف خدمة الويندوز الرسمية**: يزيل خدمة `WinMCP-Service` تماماً من `services.msc`.
3. **يحذف مهمة التشغيل التلقائي**: يلغي مهمة `WindowsMCPServer` من مجدول مهام ويندوز (Task Scheduler).
4. **يحذف المشغل الصامت من مجلد بدء التشغيل**: يمسح ملف `WinMCP_AutoStart.vbs` من `shell:startup`.
5. **ينظف متغيرات النظام (User PATH)**: يزيل مسار المشروع من بيئة المستخدم كي لا يترك أي أثر.
6. **يمسح ملفات الإعداد والسجلات المؤقتة**: يحذف ملف `.env` وجميع ملفات `logs` والكاش.

### خيارات الحذف المتاحة:
- **[1] Reset & Clean (موصى به لإعادة التجربة):** ينظف كافة الخدمات والارتباطات ويصفر ملف الإعدادات، ويترك لك ملفات السورس كود جاهزة لتعيد تشغيل `install.bat` وتبدأ من الصفر بنقاء تام.
- **[2] Full Purge (حذف نهائي شامل):** ينفذ كافة الخطوات السابقة، ويقوم بمسح مجلد المشروع بالكامل من القرص الصلب.

---

## 🤖 5. خطوات الربط مع نماذج الذكاء الاصطناعي

### 1. الربط مع ChatGPT (Custom GPTs / Actions)
1. ادخل إلى **ChatGPT** -> Explore GPTs -> Create -> Configure -> Actions -> Create new action.
2. في حقل الـ **Endpoint / Servers**:
   ```
   https://<YOUR_TUNNEL_URL>/mcp
   ```
3. في حقل الـ **Authentication**:
   - اختر **Bearer Token**.
   - الصق التوكن الخاص بك (الموجود في أمر `winmcp token`).
4. سيتعرف ChatGPT فوراً على الـ 37 أداة ويصبح قادراً على تشغيل البرامج وأتمتة المهام.

---

### 2. الربط مع Claude Web (`claude.ai` Custom Connectors)
1. ادخل إلى حسابك في **claude.ai** -> **Settings** -> **Integrations** (أو **Connectors**).
2. اختر **Add Custom MCP Connector**.
3. الصق الرابط الكامل مع التوكن المدمج:
   ```
   https://<YOUR_TUNNEL_URL>/sse?token=<YOUR_TOKEN>
   ```
4. سيتصل Claude بالسيرفر عبر **Server-Sent Events (SSE)** ويحصل على قائمة الأدوات الـ 37 تلقائياً.

---

### 3. الربط مع Claude Desktop (محلياً على نفس الجهاز)
في ملف `%APPDATA%\Claude\claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "windows": {
      "command": "C:\\path\\to\\WinMCP\\bin\\windows-mcp-server.exe",
      "args": ["stdio", "--toolsets", "all"]
    }
  }
}
```
*(استبدل `C:\\path\\to\\WinMCP` بالمسار الفعلي لمجلد المشروع لديك).*

---

## 🔒 6. مصفوفة الأمان وسجل التدقيق (Security & Audit)

- **الحماية القصوى**: لا يمكن لأي جهة في العالم تنفيذ أي أمر دون مفتاح الـ 256-bit Bearer Token. الطلبات غير المصرح بها ترفض فوراً بكود `401 Unauthorized`.
- **تصنيف الأدوات**:
  - **READ ONLY**: استعلامات النظام، قائمة العمليات، الشاشات، لقطات الشاشة، وشجرة عناصر الواجهة.
  - **LOW RISK**: تشغيل التطبيقات، النقر، الكتابة، التنقل، والضغط على الأزرار.
  - **HIGH RISK**: أوامر PowerShell، تعديل الملفات، الريجستري، إنهاء العمليات، وإدارة الخدمات.
- **سجل تدقيق شامل**: كل عملية تسجل لحظياً في `logs/gateway-audit.log` مع حجب كلمات المرور والبيانات الحساسة تلقائياً (`***MASKED***`).
