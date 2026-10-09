// MaxTools arayüzü (C#).
// MaxTools.ms bu dosyayı Max içinde derler. Tüm olaylar ve animasyonlar burada (C#) işlenir;
// MAXScript tarafında hiç .NET olay işleyicisi bulunmaz (MAXScript GC hatalarının kaynağıydı).
// Butonlar MAXScript'i ManagedServices.MaxscriptSDK.ExecuteMaxscriptCommand ile çağırır: MT_UIAction "<id>"
// MAXScript değerleri GetInt / GetText ile okur; durum çubuğunu SetStatus / SetProgress ile günceller.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows.Forms;

#if MAXFORM
public class MTForm : MaxCustomControls.MaxForm
#else
public class MTForm : Form
#endif
{
    // ----- Tema -----
    static readonly Color cBg = Color.FromArgb(24, 25, 32);
    static readonly Color cSide = Color.FromArgb(17, 18, 24);
    static readonly Color cCard = Color.FromArgb(32, 34, 44);
    static readonly Color cBorder = Color.FromArgb(48, 51, 66);
    static readonly Color cInput = Color.FromArgb(22, 23, 30);
    static readonly Color cBtn = Color.FromArgb(46, 49, 63);
    static readonly Color cBtnHover = Color.FromArgb(62, 66, 84);
    static readonly Color cBtnPress = Color.FromArgb(36, 38, 48);
    static readonly Color cAccent = Color.FromArgb(124, 92, 255);
    static readonly Color cAccentHover = Color.FromArgb(146, 121, 255);
    static readonly Color cAccentPress = Color.FromArgb(104, 74, 230);
    static readonly Color cNavHover = Color.FromArgb(28, 29, 38);
    static readonly Color cNavActive = Color.FromArgb(38, 34, 62);
    static readonly Color cText = Color.FromArgb(232, 233, 240);
    static readonly Color cMuted = Color.FromArgb(138, 141, 158);
    static readonly Color cFaint = Color.FromArgb(90, 93, 110);
    static readonly Color cOk = Color.FromArgb(74, 222, 128);
    static readonly Color cWarn = Color.FromArgb(251, 191, 36);
    static readonly Color cErr = Color.FromArgb(248, 113, 113);
    static readonly Color cBusy = Color.FromArgb(96, 165, 250);
    static readonly Color cDanger = Color.FromArgb(232, 72, 85);
    static readonly Color cTrack = Color.FromArgb(30, 31, 40);

    // ----- MAXScript köprüsü -----
    // 1) ManagedServices.MaxscriptSDK.ExecuteMaxscriptCommand (yüklü değilse adıyla / Max klasöründen yüklenir)
    // 2) Bulunamazsa yedek: UIEvent olayı (MAXScript tek bir işleyiciyle PendingCmd'yi çalıştırır)
    static MethodInfo execMI;
    static string bridgeInfo = string.Empty;
    static string maxRoot;
    public static List<string> TestLog = new List<string>();
    static MTForm current;

    public event EventHandler UIEvent;
    public string PendingCmd = string.Empty;

    public static bool HasBridge()
    {
        FindBridge();
        return execMI != null;
    }

    public void SetMaxRoot(string path) { maxRoot = path; }

    public string BridgeInfo() { FindBridge(); return bridgeInfo; }

    static void FindBridge()
    {
        if (execMI != null) return;
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        Assembly ms = null;
        foreach (Assembly a in AppDomain.CurrentDomain.GetAssemblies())
        {
            try { if (a.GetName().Name == "ManagedServices") { ms = a; sb.Append("found loaded; "); break; } } catch { }
        }
        if (ms == null)
        {
            try { ms = Assembly.Load("ManagedServices"); sb.Append("loaded by name; "); }
            catch (Exception ex) { sb.Append("load by name failed: " + ex.Message + "; "); }
        }
        if (ms == null && !string.IsNullOrEmpty(maxRoot))
        {
            string p = System.IO.Path.Combine(maxRoot, "ManagedServices.dll");
            try { ms = Assembly.LoadFrom(p); sb.Append("loaded from " + p + "; "); }
            catch (Exception ex) { sb.Append("load from file failed: " + ex.Message + "; "); }
        }
        if (ms != null)
        {
            Type t = null;
            try { t = ms.GetType("ManagedServices.MaxscriptSDK"); } catch { }
            if (t == null) sb.Append("type ManagedServices.MaxscriptSDK not found; ");
            else
            {
                execMI = t.GetMethod("ExecuteMaxscriptCommand", new Type[] { typeof(string) });
                if (execMI == null)
                {
                    sb.Append("method not found; available: ");
                    foreach (MethodInfo mi in t.GetMethods(BindingFlags.Public | BindingFlags.Static)) sb.Append(mi.Name + " ");
                }
                else sb.Append("bridge OK");
            }
        }
        bridgeInfo = sb.ToString();
    }

    static void Exec(string cmd)
    {
        FindBridge();
        if (execMI != null)
        {
            try { execMI.Invoke(null, new object[] { cmd }); return; }
            catch (Exception ex) { TestLog.Add("EXEC ERROR: " + ex.Message); }
        }
        // Yedek yol: MAXScript'teki tek olay işleyicisine bildir
        MTForm f = current;
        if (f != null && f.UIEvent != null)
        {
            f.PendingCmd = cmd;
            try { f.UIEvent(f, EventArgs.Empty); } catch (Exception ex) { TestLog.Add("EVENT ERROR: " + ex.Message); }
            return;
        }
        TestLog.Add(cmd);
    }

    // ----- Durum -----
    Panel content, progTrack, progFill, statusDot, indicator;
    Label title, subtitle, statusText;
    Panel[] pages = new Panel[4];
    Panel[] navs = new Panel[4];
    Label[] navIco = new Label[4], navTxt = new Label[4];
    int page = 1;

    // Duyarlı yerleşim
    Panel root, side, hdr, sb, logo;
    Label lblApp, lblVer, lblMenu, lblFooter, closeBtn, updBtn;
    readonly List<Panel>[] pageCards = new List<Panel>[] { new List<Panel>(), new List<Panel>(), new List<Panel>(), new List<Panel>() };
    int buildingPage = 1;
    double lastPct;
    bool compact;
    const int Grip = 5;          // kenar/köşe boyutlandırma payı (piksel)
    const int CardW = 305, CardGap = 14, CardMargin = 10;
    public int LastW = 880, LastH = 610;
    Point dragOff;
    bool dragging;
    NativeWindow ownerWin;

    readonly Dictionary<string, TextBox> texts = new Dictionary<string, TextBox>();
    readonly Dictionary<string, int[]> limits = new Dictionary<string, int[]>();
    readonly Dictionary<string, int> states = new Dictionary<string, int>();
    readonly Dictionary<string, List<Label>> segLabels = new Dictionary<string, List<Label>>();
    readonly Dictionary<string, Panel[]> toggles = new Dictionary<string, Panel[]>();

    // Animasyon hedefleri
    readonly Timer anim = new Timer();
    readonly Dictionary<Control, Color> colorTo = new Dictionary<Control, Color>();
    readonly Dictionary<Control, int> leftTo = new Dictionary<Control, int>();
    readonly Dictionary<Control, int> topTo = new Dictionary<Control, int>();

    public int LastX, LastY;
    public int Page { get { return page; } }

    static readonly string[][] PageInfo = new string[][]
    {
        new string[] { "Modeling", "Detach, merge and scene tools" },
        new string[] { "UV", "Seams, unwrapping, straightening and packing" },
        new string[] { "Naming", "Engine-ready object names" },
        new string[] { "LOD & Collision", "Game-ready optimization tools" }
    };
    static readonly int[] PageIcons = new int[] { 0xE70F, 0xE8A9, 0xE8AC, 0xE7FC };

    public MTForm()
    {
        anim.Interval = 15;
        anim.Tick += OnAnimTick;
        current = this;
        SetStyle(ControlStyles.ResizeRedraw, true);
    }

    // Başlangıç boyutu (MAXScript son boyutu INI'den verir)
    public void SetStartSize(int w, int h)
    {
        if (w >= MinimumSize.Width && h >= MinimumSize.Height) Size = new Size(w, h);
    }

    // Kenarlıksız pencerede kenar/köşeden boyutlandırma
    protected override void WndProc(ref Message m)
    {
        const int WM_NCHITTEST = 0x84;
        if (m.Msg == WM_NCHITTEST && WindowState == FormWindowState.Normal)
        {
            base.WndProc(ref m);
            long lp = m.LParam.ToInt64();
            Point p = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
            bool l = p.X < Grip, r = p.X >= ClientSize.Width - Grip;
            bool t = p.Y < Grip, b = p.Y >= ClientSize.Height - Grip;
            int hit = 0;
            if (t && l) hit = 13; else if (t && r) hit = 14;
            else if (b && l) hit = 16; else if (b && r) hit = 17;
            else if (l) hit = 10; else if (r) hit = 11;
            else if (t) hit = 12; else if (b) hit = 15;
            if (hit != 0) m.Result = (IntPtr)hit;
            return;
        }
        base.WndProc(ref m);
    }

    // İnce dış çerçeve
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using (Pen pen = new Pen(cBorder))
            e.Graphics.DrawRectangle(pen, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
    }

    // ================= Kurulum =================
    public void Build(string version, int startPage)
    {
        SuspendLayout();
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        Text = "MaxTools";
        StartPosition = FormStartPosition.Manual;
        MinimumSize = new Size(420, 420);
        Size = new Size(880, 610);
        BackColor = cSide;
        Padding = new Padding(Grip);
        DoubleBuffered = true;
        KeyPreview = true;

        root = new Panel();
        root.Dock = DockStyle.Fill;
        root.BackColor = cBg;
        Controls.Add(root);

        // Sol menü
        side = Pnl(root, 0, 0, 190, 598, cSide, 0);
        Drag(side);
        logo = Pnl(side, 20, 22, 34, 34, cAccent, 9);
        Lbl(logo, "M", 0, 0, 34, 34, 14f, true, Color.White, ContentAlignment.MiddleCenter, null);
        lblApp = Lbl(side, "MAX TOOLS", 64, 20, 120, 20, 11f, true, cText, ContentAlignment.MiddleLeft, null);
        lblVer = Lbl(side, version, 64, 39, 120, 18, 8f, false, cMuted, ContentAlignment.MiddleLeft, null);
        Drag(lblApp); Drag(lblVer); Drag(logo);
        lblMenu = Lbl(side, "MENU", 24, 80, 100, 16, 7.5f, true, cFaint, ContentAlignment.MiddleLeft, null);

        indicator = Pnl(side, 0, 112, 4, 20, cAccent, 2);
        for (int i = 0; i < 4; i++)
        {
            int idx = i + 1;
            Panel nav = Pnl(side, 12, 102 + i * 46, 166, 40, cSide, 9);
            Label ico = Lbl(nav, char.ConvertFromUtf32(PageIcons[i]), 8, 0, 32, 40, 12f, false, cMuted, ContentAlignment.MiddleCenter, "Segoe MDL2 Assets");
            Label txt = Lbl(nav, PageInfo[i][0], 44, 0, 120, 40, 9.5f, false, cMuted, ContentAlignment.MiddleLeft, null);
            navs[i] = nav; navIco[i] = ico; navTxt[i] = txt;
            foreach (Control c in new Control[] { nav, ico, txt })
            {
                c.Cursor = Cursors.Hand;
                c.Click += delegate { ShowPage(idx); };
                c.MouseEnter += delegate { if (page != idx) AnimColor(nav, cNavHover); };
                c.MouseLeave += delegate { if (page != idx) AnimColor(nav, cSide); };
            }
        }
        lblFooter = Lbl(side, "Fast modeling tools", 24, 560, 160, 18, 8f, false, cFaint, ContentAlignment.MiddleLeft, null);

        // Başlık
        hdr = Pnl(root, 190, 0, 668, 64, cBg, 0);
        Drag(hdr);
        title = Lbl(hdr, "", 24, 10, 450, 30, 15f, true, cText, ContentAlignment.MiddleLeft, null);
        subtitle = Lbl(hdr, "", 25, 38, 450, 20, 9f, false, cMuted, ContentAlignment.MiddleLeft, null);
        Drag(title); Drag(subtitle);
        Label cl = Lbl(hdr, char.ConvertFromUtf32(0xE8BB), 620, 14, 34, 30, 9f, false, cMuted, ContentAlignment.MiddleCenter, "Segoe MDL2 Assets");
        cl.BackColor = cBg;
        cl.Cursor = Cursors.Hand;
        Round(cl, 7);
        cl.MouseEnter += delegate { AnimColor(cl, cDanger); cl.ForeColor = Color.White; };
        cl.MouseLeave += delegate { AnimColor(cl, cBg); cl.ForeColor = cMuted; };
        cl.Click += delegate { Close(); };
        closeBtn = cl;

        // Güncelleme kontrolü butonu (kapatmanın solunda)
        Label up = Lbl(hdr, char.ConvertFromUtf32(0xE895), 582, 14, 34, 30, 10f, false, cMuted, ContentAlignment.MiddleCenter, "Segoe MDL2 Assets");
        up.BackColor = cBg;
        up.Cursor = Cursors.Hand;
        Round(up, 7);
        up.MouseEnter += delegate { AnimColor(up, cBtn); up.ForeColor = cText; };
        up.MouseLeave += delegate { AnimColor(up, cBg); up.ForeColor = cMuted; };
        up.Click += delegate { CheckForUpdates(false); };
        new ToolTip().SetToolTip(up, "Check for updates");
        updBtn = up;

        // İçerik
        content = Pnl(root, 190, 64, 668, 500, cBg, 0);
        BuildModelPage();
        BuildUVPage();
        BuildNamePage();
        BuildGamePage();

        // Durum çubuğu
        sb = Pnl(root, 190, 564, 668, 34, cSide, 0);
        progTrack = Pnl(sb, 0, 0, 668, 2, cTrack, 0);
        progFill = Pnl(progTrack, 0, 0, 0, 2, cAccent, 0);
        statusDot = Pnl(sb, 20, 15, 8, 8, cMuted, 4);
        statusText = Lbl(sb, "Ready.", 36, 2, 610, 32, 8.5f, false, cMuted, ContentAlignment.MiddleLeft, null);

        FormClosing += OnFormClosing;
        // Panel arka plana geçince Max kısayollarını geri aç
        Deactivate += delegate { Exec("enableAccelerators = true"); };
        // Açılışta hiçbir metin kutusu odak almasın (yoksa Max kısayolları kapanırdı)
        Shown += delegate { ActiveControl = null; };
        root.Resize += delegate { Relayout(); };
        ResumeLayout();
        Relayout();

        if (startPage < 1 || startPage > 4) startPage = 1;
        ShowPage(startPage);
        // İlk açılışta animasyonsuz doğru konum/renk
        indicator.Top = navs[startPage - 1].Top + 10;
        navs[startPage - 1].BackColor = cNavActive;
    }

    // Max'e bağlı olarak göster. x/y ekranda değilse ortala.
    public void ShowWith(long ownerHwnd, int x, int y)
    {
        Point pt = new Point(x, y);
        bool onScreen = false;
        foreach (Screen s in Screen.AllScreens) if (s.WorkingArea.Contains(pt)) onScreen = true;
        if (!onScreen)
        {
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            pt = new Point(wa.Left + (wa.Width - Width) / 2, wa.Top + (wa.Height - Height) / 2);
        }
        Location = pt;
#if MAXFORM
        ShowModeless();
#else
        if (ownerHwnd != 0)
        {
            ownerWin = new NativeWindow();
            ownerWin.AssignHandle(new IntPtr(ownerHwnd));
            Show(ownerWin);
        }
        else Show();
#endif
    }

    void OnFormClosing(object sender, FormClosingEventArgs e)
    {
        LastX = Left; LastY = Top;
        LastW = Width; LastH = Height;
        anim.Stop();
        Exec("MT_UIClosed()");
        if (current == this) current = null;
        if (ownerWin != null) { try { ownerWin.ReleaseHandle(); } catch { } ownerWin = null; }
    }

    // ================= MAXScript API =================
    // type: 0 bilgi, 1 tamam, 2 uyarı, 3 hata, 4 çalışıyor
    public void SetStatus(string msg, int type)
    {
        if (IsDisposed) return;
        Color c = type == 1 ? cOk : type == 2 ? cWarn : type == 3 ? cErr : type == 4 ? cBusy : cMuted;
        statusDot.BackColor = c;
        statusText.ForeColor = type == 0 ? cMuted : cText;
        statusText.Text = msg;
        statusDot.Refresh();
        statusText.Refresh();
    }

    public void SetProgress(double pct)
    {
        if (IsDisposed) return;
        pct = Math.Max(0, Math.Min(100, pct));
        lastPct = pct;
        progFill.Width = (int)(progTrack.Width * pct / 100.0);
        progFill.Refresh();
    }

    // Sayı kutusu (sınırlandırılmış), segment (1'den başlayan sıra) ya da açma/kapama (1/0)
    public int GetInt(string name)
    {
        TextBox tb;
        if (texts.TryGetValue(name, out tb) && limits.ContainsKey(name))
        {
            int[] lim = limits[name];
            int v;
            if (!int.TryParse(tb.Text.Trim(), out v)) v = lim[0];
            v = Math.Max(lim[0], Math.Min(lim[1], v));
            tb.Text = v.ToString();
            return v;
        }
        int s;
        if (states.TryGetValue(name, out s)) return s;
        return 0;
    }

    public string GetText(string name)
    {
        TextBox tb;
        return texts.TryGetValue(name, out tb) ? tb.Text : string.Empty;
    }

    public bool Alive() { return !IsDisposed; }

    // MAXScript köprüsü bulundu mu (statik metot yerine örnek üzerinden çağrılabilsin diye)
    public bool BridgeOK() { return HasBridge(); }

    // ================= Online güncelleme =================
    // GitHub'daki version.json okunur; daha yeni build varsa kullanıcıya sorulur, dosyalar indirilip yerine konur.
    string updBase, updDir;
    int updBuild;
    bool updBusy;
    public static bool TestAutoYes;   // yalnızca test: onay pencerelerini atla

    public void ConfigureUpdates(string baseUrl, string installDir, int currentBuild)
    {
        updBase = baseUrl;
        updDir = installDir;
        updBuild = currentBuild;
    }

    static string Fetch(string url)
    {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;   // TLS 1.2
        using (WebClient wc = new WebClient())
        {
            wc.Headers[HttpRequestHeader.CacheControl] = "no-cache";
            wc.Encoding = System.Text.Encoding.UTF8;
            return wc.DownloadString(url + "?t=" + DateTime.UtcNow.Ticks);
        }
    }

    static byte[] FetchBytes(string url)
    {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;
        using (WebClient wc = new WebClient())
        {
            wc.Headers[HttpRequestHeader.CacheControl] = "no-cache";
            return wc.DownloadData(url + "?t=" + DateTime.UtcNow.Ticks);
        }
    }

    // silent: açılıştaki otomatik kontrol (güncelse ya da internet yoksa sessiz kalır)
    public void CheckForUpdates(bool silent)
    {
        if (string.IsNullOrEmpty(updBase) || updBusy) return;
        updBusy = true;
        if (!silent) SetStatus("Checking for updates...", 4);
        System.Threading.Thread th = new System.Threading.Thread(delegate ()
        {
            string json = null, err = null;
            try { json = Fetch(updBase + "version.json"); }
            catch (Exception ex) { err = ex.Message; }
            RunOnUI(delegate { OnCheckDone(json, err, silent); });
        });
        th.IsBackground = true;
        th.Start();
    }

    void RunOnUI(MethodInvoker m)
    {
        try { if (IsHandleCreated && !IsDisposed) BeginInvoke(m); } catch { }
    }

    void OnCheckDone(string json, string err, bool silent)
    {
        updBusy = false;
        if (IsDisposed) return;
        if (json == null)
        {
            if (!silent) SetStatus("Update check failed: " + err, 2);
            return;
        }
        Match mb = Regex.Match(json, "\"build\"\\s*:\\s*(\\d+)");
        Match mv = Regex.Match(json, "\"version\"\\s*:\\s*\"([^\"]*)\"");
        Match mn = Regex.Match(json, "\"notes\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        Match mf = Regex.Match(json, "\"files\"\\s*:\\s*\\[(.*?)\\]", RegexOptions.Singleline);
        if (!mb.Success || !mf.Success)
        {
            if (!silent) SetStatus("Update check failed: invalid version.json", 2);
            return;
        }
        int build = int.Parse(mb.Groups[1].Value);
        string ver = mv.Success ? mv.Groups[1].Value : build.ToString();
        string notes = mn.Success ? Regex.Unescape(mn.Groups[1].Value) : string.Empty;
        if (build <= updBuild)
        {
            if (!silent) SetStatus("MaxTools is up to date (v" + ver + ", build " + build + ").", 1);
            return;
        }
        List<string> files = new List<string>();
        foreach (Match m in Regex.Matches(mf.Groups[1].Value, "\"([^\"]+)\""))
        {
            string f = m.Groups[1].Value.Replace('/', '\\');
            if (f.Contains("..") || Path.IsPathRooted(f)) continue;   // güvenlik: yalnızca kurulum klasörünün içine
            files.Add(f);
        }
        DialogResult dr = TestAutoYes ? DialogResult.Yes : MessageBox.Show(this,
            "MaxTools v" + ver + " (build " + build + ") is available.\n\n" +
            (notes.Length > 0 ? notes + "\n\n" : string.Empty) + "Update now?",
            "MaxTools Update", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
        if (dr == DialogResult.Yes) StartUpdate(files, ver, build);
        else SetStatus("Update v" + ver + " available (use the update button to install).", 0);
    }

    void StartUpdate(List<string> files, string ver, int build)
    {
        updBusy = true;
        SetStatus("Downloading MaxTools v" + ver + "...", 4);
        string stage = Path.Combine(updDir, "_update");
        System.Threading.Thread th = new System.Threading.Thread(delegate ()
        {
            string err = null;
            try
            {
                if (Directory.Exists(stage)) Directory.Delete(stage, true);
                foreach (string f in files)
                {
                    byte[] data = FetchBytes(updBase + f.Replace('\\', '/'));
                    if (data == null || data.Length == 0) throw new Exception("empty file: " + f);
                    string dst = Path.Combine(stage, f);
                    Directory.CreateDirectory(Path.GetDirectoryName(dst));
                    File.WriteAllBytes(dst, data);
                }
            }
            catch (Exception ex) { err = ex.Message; }
            RunOnUI(delegate { ApplyUpdate(files, stage, ver, build, err); });
        });
        th.IsBackground = true;
        th.Start();
    }

    // İndirilen dosyaları yedek alarak yerine koyar; hata olursa yedeği geri yükler
    void ApplyUpdate(List<string> files, string stage, string ver, int build, string err)
    {
        updBusy = false;
        if (err != null)
        {
            SetStatus("Update failed (download): " + err, 3);
            return;
        }
        string backup = Path.Combine(updDir, "_update_backup");
        List<string> done = new List<string>();
        try
        {
            if (Directory.Exists(backup)) Directory.Delete(backup, true);
            foreach (string f in files)
            {
                string cur = Path.Combine(updDir, f);
                string bak = Path.Combine(backup, f);
                if (File.Exists(cur))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(bak));
                    File.Copy(cur, bak, true);
                }
                Directory.CreateDirectory(Path.GetDirectoryName(cur));
                File.Copy(Path.Combine(stage, f), cur, true);
                done.Add(f);
            }
            try { Directory.Delete(stage, true); } catch { }
        }
        catch (Exception ex)
        {
            // Geri al
            foreach (string f in done)
            {
                string bak = Path.Combine(backup, f);
                try { if (File.Exists(bak)) File.Copy(bak, Path.Combine(updDir, f), true); } catch { }
            }
            SetStatus("Update failed (install): " + ex.Message + " - previous version restored.", 3);
            return;
        }
        updBuild = build;
        SetStatus("Updated to v" + ver + " (build " + build + ").", 1);
        if (!TestAutoYes)
            MessageBox.Show(this, "MaxTools was updated to v" + ver + " (build " + build + ").\nThe panel will now reopen.",
                "MaxTools Update", MessageBoxButtons.OK, MessageBoxIcon.Information);
        RunOnUI(delegate { Exec("MT_ReloadAfterUpdate()"); });
    }

    // ================= Sayfalar =================
    Panel NewPage(int idx)
    {
        Panel pg = Pnl(content, 0, 0, 668, 500, cBg, 0);
        pg.Dock = DockStyle.Fill;
        pg.AutoScroll = true;
        pg.AutoScrollMargin = new Size(0, 16);
        pg.Visible = false;
        pages[idx - 1] = pg;
        buildingPage = idx;
        return pg;
    }

    // ================= Duyarlı yerleşim =================
    // Dar pencerede sol menü ikonlara küçülür; kartlar sığdığı kadar sütuna dizilir (1 sütun = alt alta).
    void Relayout()
    {
        if (root == null || side == null) return;
        int W = root.ClientSize.Width, H = root.ClientSize.Height;
        if (W <= 0 || H <= 0) return;
        SuspendLayout();

        compact = W < 640;
        int sideW = compact ? 60 : 190;
        side.SetBounds(0, 0, sideW, H);
        logo.Left = compact ? 13 : 20;
        lblApp.Visible = lblVer.Visible = lblMenu.Visible = lblFooter.Visible = !compact;
        lblFooter.Top = H - 38;
        for (int i = 0; i < 4; i++)
        {
            int nw = compact ? 36 : 166;
            if (navs[i].Width != nw)
            {
                navs[i].Width = nw;
                Round(navs[i], 9);
            }
            navIco[i].Left = compact ? 2 : 8;
            navTxt[i].Visible = !compact;
        }

        int mainW = W - sideW;
        hdr.SetBounds(sideW, 0, mainW, 64);
        closeBtn.Left = mainW - 48;
        updBtn.Left = mainW - 86;
        title.Width = subtitle.Width = Math.Max(100, mainW - 120);

        sb.SetBounds(sideW, H - 34, mainW, 34);
        progTrack.Width = mainW;
        progFill.Width = (int)(mainW * lastPct / 100.0);
        statusText.Width = Math.Max(100, mainW - 50);

        content.SetBounds(sideW, 64, mainW, H - 98);
        for (int p = 0; p < 4; p++) LayoutCards(p);
        ResumeLayout();
    }

    void LayoutCards(int p)
    {
        Panel pg = pages[p];
        List<Panel> cards = pageCards[p];
        if (pg == null || cards.Count == 0) return;

        // Önce kaydırma çubuğu yokmuş gibi yerleştir; içerik taşıyorsa çubuk payını düşüp tekrar yerleştir
        int full = content.ClientSize.Width;
        int needH = PlaceCards(pg, cards, full, true);
        if (needH > content.ClientSize.Height)
            PlaceCards(pg, cards, full - SystemInformation.VerticalScrollBarWidth, false);
        else
            PlaceCards(pg, cards, full, false);
    }

    // Kartları verilen genişliğe yerleştirir; dryRun ise sadece gereken yüksekliği hesaplar
    int PlaceCards(Panel pg, List<Panel> cards, int avail, bool dryRun)
    {
        int cols = (avail - 2 * CardMargin + CardGap) / (CardW + CardGap);
        cols = Math.Max(1, Math.Min(cols, cards.Count));
        int totalW = cols * CardW + (cols - 1) * CardGap;
        int x0 = Math.Max(CardMargin, (avail - totalW) / 2);

        Point scroll = Point.Empty;
        if (!dryRun)
        {
            scroll = pg.AutoScrollPosition;
            pg.AutoScrollPosition = Point.Empty;
        }
        int[] colH = new int[cols];
        for (int k = 0; k < cols; k++) colH[k] = 8;
        foreach (Panel c in cards)
        {
            int k;
            // 2 sütunda tasarımdaki sütun düzeni korunur; diğerlerinde en kısa sütuna yerleşir
            if (cols == 2) k = ((int)c.Tag) - 1;
            else
            {
                k = 0;
                for (int j = 1; j < cols; j++) if (colH[j] < colH[k]) k = j;
            }
            if (!dryRun) c.Location = new Point(x0 + k * (CardW + CardGap), colH[k]);
            colH[k] += c.Height + 16;
        }
        if (!dryRun) pg.AutoScrollPosition = new Point(-scroll.X, -scroll.Y);
        int maxH = 0;
        foreach (int h in colH) maxH = Math.Max(maxH, h);
        return maxH;
    }

    void BuildModelPage()
    {
        Panel pg = NewPage(1);
        Panel c = Card(pg, 1, "Element Detacher", "Splits each element into its own object, centers pivots", 114);
        Btn(c, "Detach Elements", 16, 62, 273, 36, "detach", true);

        c = Card(pg, 1, "Cross-Scene Copy / Paste", "Move objects between Max sessions", 114);
        Btn(c, "Copy", 16, 62, 132, 36, "copy", false);
        Btn(c, "Paste", 157, 62, 132, 36, "paste", false);

        c = Card(pg, 1, "UV Shifter", "Randomly offset UVs to break texture tiling", 114);
        Btn(c, "All Elements", 16, 62, 132, 36, "uvAll", false);
        Btn(c, "Selected Elements", 157, 62, 132, 36, "uvSel", false);

        c = Card(pg, 2, "Quick Merge", "Group or merge into one object", 158);
        Btn(c, "Auto Group", 16, 62, 273, 36, "group", false);
        Btn(c, "Attach + Center Pivot", 16, 106, 273, 36, "attach", false);

        c = Card(pg, 2, "Reference Image", "Creates a textured plane with correct aspect ratio", 114);
        Btn(c, "Pick Image and Add to Scene", 16, 62, 273, 36, "ref", false);

        c = Card(pg, 2, "Drop to Ground", "Groups are treated as a single object", 152);
        Segment(c, 16, 62, 273, "dropMode", new string[] { "World Z = 0", "Surface Below" }, 1);
        Btn(c, "Drop to Ground", 16, 100, 273, 36, "drop", true);
    }

    void BuildUVPage()
    {
        Panel pg = NewPage(2);
        Panel c = Card(pg, 1, "Seams", "Select edges in Unwrap UVW › Edge mode", 158);
        Btn(c, "Mark Seams", 16, 62, 132, 36, "seamAdd", true);
        Btn(c, "Remove Seams", 157, 62, 132, 36, "seamDel", false);
        Btn(c, "Clear Seams", 16, 106, 132, 36, "seamClear", false);
        Btn(c, "Unwrap Seams", 157, 106, 132, 36, "peel", false);

        c = Card(pg, 1, "Hard Edge", "From smoothing borders or by angle", 188);
        Segment(c, 16, 62, 273, "uvAutoMode", new string[] { "Smoothing", "By Angle" }, 1);
        Muted(c, "Angle", 16, 100, 40, 28);
        Num(c, 56, 100, "uvAngle", 30, 1, 179, 88);
        Muted(c, "° and above", 150, 100, 139, 28);
        Btn(c, "Select Hard Edges", 16, 136, 132, 36, "selHard", false);
        Btn(c, "Auto Unwrap", 157, 136, 132, 36, "autoUnwrap", true);

        c = Card(pg, 2, "Pack", "Shape-based: islands fill gaps too", 256);
        Muted(c, "Texture size", 16, 62, 130, 30);
        Segment(c, 157, 62, 132, "uvTex", new string[] { "512", "1K", "2K", "4K" }, 3);
        Muted(c, "Padding (px)", 16, 100, 130, 28);
        Num(c, 157, 100, "uvPad", 8, 0, 64, 132);
        Muted(c, "Rotation", 16, 134, 130, 30);
        Segment(c, 157, 134, 132, "uvRotMode", new string[] { "None", "90°", "Free" }, 2);
        Toggle(c, 16, 170, 273, "uvEq", "Equalize texel density", true);
        Btn(c, "Pack", 16, 204, 273, 36, "pack", true);

        c = Card(pg, 2, "Straighten", "Align shells, rectangularize strips", 186);
        Segment(c, 16, 62, 273, "uvDir", new string[] { "Auto", "Horizontal", "Vertical" }, 1);
        Toggle(c, 16, 100, 273, "uvRect", "Rectangularize strips", true);
        Btn(c, "Straighten Shells", 16, 134, 273, 36, "straight", false);
    }

    void BuildNamePage()
    {
        Panel pg = NewPage(3);
        Panel c = Card(pg, 1, "Prefix / Suffix", "Skips if already present", 186);
        Muted(c, "Prefix", 16, 62, 50, 28);
        Txt(c, 66, 62, 114, "nmPre");
        Combo(c, 189, 62, 100, new string[] { "Presets...", "SM_", "SK_", "SM_Env_", "BP_", "M_", "MI_", "T_" }, "nmPre");
        Muted(c, "Suffix", 16, 98, 50, 28);
        Txt(c, 66, 98, 114, "nmSuf");
        Combo(c, 189, 98, 100, new string[] { "Presets...", "_LOD0", "_Low", "_High", "_Col", "_Mid" }, "nmSuf");
        Btn(c, "Add", 16, 134, 273, 36, "nameFix", true);

        c = Card(pg, 1, "Clean Names", "Fixes accented characters, spaces and symbols", 114);
        Btn(c, "Clean", 16, 62, 273, 36, "nameClean", false);

        c = Card(pg, 2, "Rename + Number", "Name_01, Name_02 ...", 186);
        Muted(c, "Name", 16, 62, 50, 28);
        Txt(c, 66, 62, 223, "nmBase");
        Muted(c, "Start", 16, 98, 50, 28);
        Num(c, 66, 98, "nmStart", 1, 0, 9999, 96);
        Muted(c, "Digits", 172, 98, 40, 28);
        Num(c, 213, 98, "nmPad", 2, 1, 6, 76);
        Btn(c, "Rename", 16, 134, 273, 36, "nameRen", true);

        c = Card(pg, 2, "Find / Replace", "Case sensitive", 186);
        Muted(c, "Find", 16, 62, 50, 28);
        Txt(c, 66, 62, 223, "nmFind");
        Muted(c, "New", 16, 98, 50, 28);
        Txt(c, 66, 98, 223, "nmRepl");
        Btn(c, "Replace", 16, 134, 273, 36, "nameRep", false);
    }

    void BuildGamePage()
    {
        Panel pg = NewPage(4);
        Panel c = Card(pg, 1, "Auto LOD", "Polygon reduction preserving borders and UVs", 432);
        Muted(c, "LOD count", 16, 62, 130, 28);
        Num(c, 157, 62, "lodCount", 3, 1, 4, 132);
        Muted(c, "LOD1 %", 16, 98, 60, 28);
        Num(c, 70, 98, "lodP1", 50, 1, 99, 78);
        Muted(c, "LOD2 %", 157, 98, 60, 28);
        Num(c, 211, 98, "lodP2", 25, 1, 99, 78);
        Muted(c, "LOD3 %", 16, 134, 60, 28);
        Num(c, 70, 134, "lodP3", 12, 1, 99, 78);
        Muted(c, "LOD4 %", 157, 134, 60, 28);
        Num(c, 211, 134, "lodP4", 6, 1, 99, 78);
        Muted(c, "Open edges", 16, 170, 130, 28);
        Segment(c, 157, 168, 132, "lodBorder", new string[] { "Lock", "Protect", "Free" }, 1);
        Toggle(c, 16, 206, 273, "lodUV", "Preserve UV seams", true);
        Toggle(c, 16, 234, 273, "lodNorm", "Preserve normals / hard edges", true);
        Toggle(c, 16, 262, 273, "lodMat", "Preserve material ID borders", true);
        Toggle(c, 16, 290, 273, "lodL0", "Rename original to _LOD0", true);
        Toggle(c, 16, 318, 273, "lodColl", "Convert result to Editable Poly", true);
        Toggle(c, 16, 346, 273, "lodOff", "Lay out side by side", false);
        Btn(c, "Create LODs", 16, 380, 273, 36, "lod", true);

        c = Card(pg, 2, "Collision Generator", "Unreal naming: UCX_ / UBX_ / USP_", 300);
        Segment(c, 16, 62, 273, "colType", new string[] { "Convex", "Parts", "Box", "Sphere" }, 1);
        Muted(c, "Convex detail", 16, 100, 130, 28);
        Num(c, 157, 100, "colDetail", 24, 6, 64, 132);
        Muted(c, "Parts resolution", 16, 136, 130, 28);
        Num(c, 157, 136, "colGrid", 32, 4, 64, 132);
        Toggle(c, 16, 170, 273, "colMerge", "Merge parts into one object", true);
        Lbl(c, "Convex: solid objects (rocks, barrels, furniture).\nParts: walls with door/window openings.",
            16, 204, 273, 36, 8f, false, cMuted, ContentAlignment.TopLeft, null);
        Btn(c, "Create Collision", 16, 248, 273, 36, "col", true);
    }

    void ShowPage(int i)
    {
        for (int k = 1; k <= 4; k++)
        {
            if (pages[k - 1] != null) pages[k - 1].Visible = (k == i);
            AnimColor(navs[k - 1], k == i ? cNavActive : cSide);
            navTxt[k - 1].ForeColor = k == i ? cText : cMuted;
            navIco[k - 1].ForeColor = k == i ? cAccent : cMuted;
        }
        page = i;
        ActiveControl = null;
        title.Text = PageInfo[i - 1][0];
        subtitle.Text = PageInfo[i - 1][1];
        AnimTop(indicator, navs[i - 1].Top + 10);
    }

    // ================= Kontroller =================
    static void Round(Control c, int r)
    {
        int w = c.Width, h = c.Height, d = r * 2;
        if (d <= 0 || w <= 0 || h <= 0) return;
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddArc(0, 0, d, d, 180, 90);
            gp.AddArc(w - d, 0, d, d, 270, 90);
            gp.AddArc(w - d, h - d, d, d, 0, 90);
            gp.AddArc(0, h - d, d, d, 90, 90);
            gp.CloseFigure();
            c.Region = new Region(gp);
        }
    }

    static Panel Pnl(Control par, int x, int y, int w, int h, Color col, int radius)
    {
        Panel p = new Panel();
        p.SetBounds(x, y, w, h);
        p.BackColor = col;
        if (radius > 0) Round(p, radius);
        par.Controls.Add(p);
        return p;
    }

    static Label Lbl(Control par, string txt, int x, int y, int w, int h, float size, bool bold, Color col, ContentAlignment align, string family)
    {
        Label l = new Label();
        l.AutoSize = false;
        l.UseMnemonic = false;
        l.SetBounds(x, y, w, h);
        l.Text = txt;
        l.Font = new Font(family ?? "Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
        l.ForeColor = col;
        l.BackColor = Color.Transparent;
        l.TextAlign = align;
        par.Controls.Add(l);
        return l;
    }

    static Label Muted(Control par, string txt, int x, int y, int w, int h)
    {
        return Lbl(par, txt, x, y, w, h, 9f, false, cMuted, ContentAlignment.MiddleLeft, null);
    }

    void Drag(Control c)
    {
        c.MouseDown += delegate (object s, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            dragging = true;
            dragOff = new Point(Cursor.Position.X - Left, Cursor.Position.Y - Top);
        };
        c.MouseMove += delegate (object s, MouseEventArgs e)
        {
            if (dragging) Location = new Point(Cursor.Position.X - dragOff.X, Cursor.Position.Y - dragOff.Y);
        };
        c.MouseUp += delegate { dragging = false; };
    }

    Label Btn(Control par, string txt, int x, int y, int w, int h, string action, bool primary)
    {
        Label b = Lbl(par, txt, x, y, w, h, 9f, primary, primary ? Color.White : cText, ContentAlignment.MiddleCenter, null);
        Color baseC = primary ? cAccent : cBtn;
        Color hoverC = primary ? cAccentHover : cBtnHover;
        Color pressC = primary ? cAccentPress : cBtnPress;
        b.BackColor = baseC;
        b.Cursor = Cursors.Hand;
        Round(b, 7);
        b.MouseEnter += delegate { AnimColor(b, hoverC); };
        b.MouseLeave += delegate { AnimColor(b, baseC); };
        b.MouseDown += delegate { colorTo.Remove(b); b.BackColor = pressC; };
        b.MouseUp += delegate { AnimColor(b, hoverC); };
        b.Click += delegate
        {
            SetProgress(0);
            Exec("MT_UIAction \"" + action + "\"");
        };
        return b;
    }

    TextBox Txt(Control par, int x, int y, int w, string name)
    {
        Panel bg = Pnl(par, x, y, w, 28, cInput, 6);
        TextBox t = new TextBox();
        t.BorderStyle = BorderStyle.None;
        t.BackColor = cInput;
        t.ForeColor = cText;
        t.Font = new Font("Segoe UI", 9.5f);
        t.SetBounds(9, 6, w - 18, 18);
        HookFocus(t);
        bg.Controls.Add(t);
        texts[name] = t;
        return t;
    }

    static void HookFocus(TextBox t)
    {
        t.GotFocus += delegate { Exec("enableAccelerators = false"); };
        t.LostFocus += delegate { Exec("enableAccelerators = true"); };
    }

    void Num(Control par, int x, int y, string name, int val, int mn, int mx, int w)
    {
        Panel bg = Pnl(par, x, y, w, 28, cInput, 6);
        Label minus = Lbl(bg, "−", 0, 0, 26, 28, 11f, false, cMuted, ContentAlignment.MiddleCenter, null);
        Label plus = Lbl(bg, "+", w - 26, 0, 26, 28, 11f, false, cMuted, ContentAlignment.MiddleCenter, null);
        TextBox t = new TextBox();
        t.BorderStyle = BorderStyle.None;
        t.BackColor = cInput;
        t.ForeColor = cText;
        t.Font = new Font("Segoe UI", 9.5f);
        t.TextAlign = HorizontalAlignment.Center;
        t.SetBounds(26, 6, w - 52, 18);
        t.Text = val.ToString();
        HookFocus(t);
        bg.Controls.Add(t);
        texts[name] = t;
        limits[name] = new int[] { mn, mx };
        foreach (Label l in new Label[] { minus, plus })
        {
            Label lb = l;
            int dir = (lb == minus) ? -1 : 1;
            lb.Cursor = Cursors.Hand;
            lb.MouseEnter += delegate { lb.ForeColor = cText; };
            lb.MouseLeave += delegate { lb.ForeColor = cMuted; };
            lb.Click += delegate
            {
                int v = GetInt(name) + dir;
                v = Math.Max(mn, Math.Min(mx, v));
                t.Text = v.ToString();
            };
        }
    }

    // Hazır değer kutusu: seçilen değeri hedef metin kutusuna yazar
    void Combo(Control par, int x, int y, int w, string[] items, string target)
    {
        ComboBox c = new ComboBox();
        c.DropDownStyle = ComboBoxStyle.DropDownList;
        c.FlatStyle = FlatStyle.Flat;
        c.BackColor = cInput;
        c.ForeColor = cText;
        c.Font = new Font("Segoe UI", 9f);
        c.SetBounds(x, y + 2, w, 24);
        c.DrawMode = DrawMode.OwnerDrawFixed;
        c.Items.AddRange(items);
        c.SelectedIndex = 0;
        c.DrawItem += delegate (object s, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            e.DrawBackground();
            using (SolidBrush br = new SolidBrush(cText))
                e.Graphics.DrawString(c.Items[e.Index].ToString(), c.Font, br, e.Bounds.X + 4, e.Bounds.Y + 3);
        };
        c.SelectedIndexChanged += delegate
        {
            if (c.SelectedIndex > 0)
            {
                TextBox tb;
                if (texts.TryGetValue(target, out tb)) tb.Text = c.SelectedItem.ToString();
                c.SelectedIndex = 0;
            }
        };
        par.Controls.Add(c);
    }

    void Toggle(Control par, int x, int y, int w, string name, string txt, bool on)
    {
        Panel trk = Pnl(par, x, y + 4, 34, 18, on ? cAccent : cBtn, 9);
        Panel knob = Pnl(trk, on ? 18 : 2, 2, 14, 14, Color.White, 7);
        Label lbl = Lbl(par, txt, x + 44, y, w - 44, 26, 9f, false, cText, ContentAlignment.MiddleLeft, null);
        states[name] = on ? 1 : 0;
        toggles[name] = new Panel[] { trk, knob };
        foreach (Control c in new Control[] { trk, knob, lbl })
        {
            c.Cursor = Cursors.Hand;
            c.Click += delegate
            {
                bool st = states[name] == 0;
                states[name] = st ? 1 : 0;
                AnimLeft(knob, st ? 18 : 2);
                AnimColor(trk, st ? cAccent : cBtn);
            };
        }
    }

    void Segment(Control par, int x, int y, int w, string name, string[] labels, int sel)
    {
        int n = labels.Length;
        Panel bg = Pnl(par, x, y, w, 30, cInput, 7);
        int sw = (w - 4) / n;
        List<Label> list = new List<Label>();
        for (int i = 0; i < n; i++)
        {
            int idx = i + 1;
            Label s = Lbl(bg, labels[i], 2 + i * sw, 2, sw, 26, 8.5f, false, idx == sel ? Color.White : cMuted, ContentAlignment.MiddleCenter, null);
            s.BackColor = idx == sel ? cAccent : cInput;
            s.Cursor = Cursors.Hand;
            Round(s, 6);
            s.MouseEnter += delegate { if (states[name] != idx) AnimColor(s, cBtn); };
            s.MouseLeave += delegate { if (states[name] != idx) AnimColor(s, cInput); };
            s.Click += delegate { SegSelect(name, idx); };
            list.Add(s);
        }
        segLabels[name] = list;
        states[name] = sel;
    }

    void SegSelect(string name, int idx)
    {
        states[name] = idx;
        List<Label> list = segLabels[name];
        for (int i = 0; i < list.Count; i++)
        {
            bool on = (i + 1) == idx;
            AnimColor(list[i], on ? cAccent : cInput);
            list[i].ForeColor = on ? Color.White : cMuted;
        }
    }

    // Kart: başlık + açıklama; içerik y=62'den başlar. Sütun yüksekliği otomatik izlenir.
    // Kart yeri Relayout'ta hesaplanır; col = 2 sütunlu düzendeki tercih edilen sütun
    Panel Card(Panel pg, int col, string titleTxt, string sub, int h)
    {
        Panel c = Pnl(pg, 0, 0, CardW, h, cCard, 12);
        c.Tag = col;
        Pnl(c, 16, 17, 3, 16, cAccent, 1);
        Lbl(c, titleTxt, 26, 12, 265, 24, 10.5f, true, cText, ContentAlignment.MiddleLeft, null);
        Lbl(c, sub, 16, 36, 280, 18, 8.5f, false, cMuted, ContentAlignment.MiddleLeft, null);
        pageCards[buildingPage - 1].Add(c);
        return c;
    }

    // ================= Animasyon =================
    void AnimColor(Control c, Color to) { colorTo[c] = to; anim.Start(); }
    void AnimLeft(Control c, int to) { leftTo[c] = to; anim.Start(); }
    void AnimTop(Control c, int to) { topTo[c] = to; anim.Start(); }

    static int Step(int cur, int tgt)
    {
        int d = tgt - cur;
        if (Math.Abs(d) <= 1) return tgt;
        int s = (int)(d * 0.28);
        if (s == 0) s = d > 0 ? 1 : -1;
        return cur + s;
    }

    void OnAnimTick(object sender, EventArgs e)
    {
        if (IsDisposed) { anim.Stop(); return; }
        foreach (Control c in new List<Control>(colorTo.Keys))
        {
            Color cur = c.BackColor, t = colorTo[c];
            Color nc = Color.FromArgb(Step(cur.R, t.R), Step(cur.G, t.G), Step(cur.B, t.B));
            c.BackColor = nc;
            if (nc.R == t.R && nc.G == t.G && nc.B == t.B) colorTo.Remove(c);
        }
        foreach (Control c in new List<Control>(leftTo.Keys))
        {
            c.Left = Step(c.Left, leftTo[c]);
            if (c.Left == leftTo[c]) leftTo.Remove(c);
        }
        foreach (Control c in new List<Control>(topTo.Keys))
        {
            c.Top = Step(c.Top, topTo[c]);
            if (c.Top == topTo[c]) topTo.Remove(c);
        }
        if (colorTo.Count == 0 && leftTo.Count == 0 && topTo.Count == 0) anim.Stop();
    }
}
