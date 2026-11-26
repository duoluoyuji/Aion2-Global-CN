using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("AION 2 国际服简繁一键汉化工具")]
[assembly: AssemblyDescription("AION 2 (Steam / PURPLE 正式版) 简繁中文一键汉化工具")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("B站@吃素的佩奇")]
[assembly: AssemblyProduct("Aion2CNTool")]
[assembly: AssemblyCopyright("Copyright © 2026 B站@吃素的佩奇")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("0.0.2.0")]
[assembly: AssemblyFileVersion("0.0.2.0")]

namespace Aion2CN {
    public class ClientTarget {
        public string ClientType { get; set; }
        public string Path { get; set; }
        public string State { get; set; }

        public override string ToString() {
            // 列表里只放来源与路径，保证完整路径一行显示；汉化状态看右侧"当前状态"
            return "[" + ClientType + "] " + Path;
        }
    }

    public class MainForm : Form {
        private Panel topPanel;
        private Label lblTitle;
        private Button btnBili;

        private GroupBox grpClients;
        private CheckedListBox chkListClients;
        private Button btnRescan;
        private Button btnBrowse;

        private ComboBox cmbScheme;
        private Label lblState;

        private GroupBox grpActions;
        private TextBox rtbDisc;
        private Label lblReadHint;
        private System.Windows.Forms.Timer tmrDisc;
        private System.Windows.Forms.Timer tmrPoll;
        private int readCountdown = 3;
        private bool discRead = false;
        private bool discUnlocked = false;
        private CheckBox chkAgree;
        private Button btnApply;
        private Button btnApplyTw;
        private Button btnRestore;

        private GroupBox grpLog;
        private TextBox txtLog;

        private List<ClientTarget> detectedRoots;
        private string toolDir;
        private string currentVersion = "0.0.2";
        private string[] appIds = new string[] { "3393110", "4972320" };

        // 两个语言入口互斥：en 与 ja 的同名 locres 同时存在时，英文会按 key 回退覆盖日文，
        // 所以部署任一入口前必须先物理移除另一入口的文件（日志逐条记录）。
        private static readonly string[] LocresEn = new string[] {
            @"Engine\Content\Localization\Engine\Platforms\Windows\en\Engine.locres",
            @"Engine\Content\Localization\Engine\Platforms\Windows\en-US\Engine.locres"
        };
        private static readonly string[] LocresJa = new string[] {
            @"Engine\Content\Localization\Engine\Platforms\Windows\ja\Engine.locres",
            @"Engine\Content\Localization\Engine\Platforms\Windows\ja-JP\Engine.locres"
        };
        private static readonly string[] AllLocres = new string[] {
            @"Engine\Content\Localization\Engine\Platforms\Windows\en\Engine.locres",
            @"Engine\Content\Localization\Engine\Platforms\Windows\en-US\Engine.locres",
            @"Engine\Content\Localization\Engine\Platforms\Windows\ja\Engine.locres",
            @"Engine\Content\Localization\Engine\Platforms\Windows\ja-JP\Engine.locres"
        };

        private string EntryKey { get { return cmbScheme.SelectedIndex == 1 ? "ja" : "en"; } }
        private string EntryName { get { return EntryKey == "ja" ? "日文入口" : "英文入口"; } }
        private string EntryCulture { get { return EntryKey == "ja" ? "日本語" : "English"; } }
        private static string LangNameOf(string lang) { return lang == "zh-TW" ? "繁体中文" : "简体中文"; }
        private string[] EntryLocres { get { return EntryKey == "ja" ? LocresJa : LocresEn; } }
        private string[] OtherLocres { get { return EntryKey == "ja" ? LocresEn : LocresJa; } }

        public MainForm() {
            detectedRoots = new List<ClientTarget>();
            string baseDir = "";
            try { baseDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location); } catch { }
            if (string.IsNullOrEmpty(baseDir)) baseDir = AppDomain.CurrentDomain.BaseDirectory;
            toolDir = baseDir.TrimEnd('\\', '/');

            InitializeComponent();
            ApplyDpiScale();
        }

        // 系统 DPI 缩放（125% / 150% 等）：只缩放一次，避免 WinForms 自动缩放只缩字体不缩控件导致重叠
        private void ApplyDpiScale() {
            float s = 1f;
            using (Graphics g = this.CreateGraphics()) { s = g.DpiX / 96f; }
            string forced = Environment.GetEnvironmentVariable("AION2_DPI");
            if (!string.IsNullOrEmpty(forced)) {
                float f;
                if (float.TryParse(forced, out f) && f > 0.5f && f < 3f) s = f;
            }
            if (Math.Abs(s - 1f) < 0.02f) return;
            this.SuspendLayout();
            ScaleControls(this, s);
            this.ClientSize = new Size((int)Math.Round(this.ClientSize.Width * s), (int)Math.Round(this.ClientSize.Height * s));
            this.ResumeLayout(true);
        }

        private static void ScaleControls(Control parent, float s) {
            foreach (Control c in parent.Controls) {
                if (c.Dock == DockStyle.Top || c.Dock == DockStyle.Bottom)
                    c.Height = (int)Math.Round(c.Height * s);
                else if (c.Dock == DockStyle.Left || c.Dock == DockStyle.Right)
                    c.Width = (int)Math.Round(c.Width * s);
                else if (c.Dock == DockStyle.None) {
                    c.Location = new Point((int)Math.Round(c.Left * s), (int)Math.Round(c.Top * s));
                    c.Size = new Size((int)Math.Round(c.Width * s), (int)Math.Round(c.Height * s));
                }
                Font f = c.Font;
                c.Font = new Font(f.FontFamily, f.Size * s, f.Style);
                ScaleControls(c, s);
            }
        }

        // 默认选中：英文入口 + 简体中文（下拉框里可随时切换）
        private void ApplyDefaults() {
            cmbScheme.SelectedIndex = 0;
            UpdateStateLabel();
        }

        private void InitializeComponent() {
            this.Text = "永恒之塔2 (AION 2) 国际服 · 简繁汉化 v" + currentVersion + " - B站@吃素的佩奇";
            this.Size = new Size(760, 700);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.AutoScaleMode = AutoScaleMode.None;
            this.BackColor = Color.FromArgb(243, 244, 246);
            this.ForeColor = Color.FromArgb(31, 41, 55);
            this.Font = new Font("Microsoft YaHei UI", 9.5f);

            // ================= 顶部横幅 =================
            topPanel = new Panel();
            topPanel.Dock = DockStyle.Top;
            topPanel.Height = 70;
            topPanel.BackColor = Color.FromArgb(255, 255, 255);

            lblTitle = new Label();
            lblTitle.Text = "永恒之塔2 (AION 2) 国际服 · 简繁汉化";
            lblTitle.Font = new Font("Microsoft YaHei UI", 16f, FontStyle.Bold);
            lblTitle.ForeColor = Color.FromArgb(17, 24, 39);
            lblTitle.Location = new Point(20, 10);
            lblTitle.AutoSize = true;

            var lblSub = new Label();
            lblSub.Text = "";
            lblSub.Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);
            lblSub.ForeColor = Color.FromArgb(37, 99, 235);
            lblSub.Location = new Point(22, 44);
            lblSub.AutoSize = true;

            btnBili = new Button();
            btnBili.Text = "关注作者B站";
            btnBili.Location = new Point(610, 18);
            btnBili.Size = new Size(115, 36);
            btnBili.BackColor = Color.FromArgb(251, 114, 153);
            btnBili.ForeColor = Color.White;
            btnBili.FlatStyle = FlatStyle.Flat;
            btnBili.FlatAppearance.BorderSize = 0;
            btnBili.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            btnBili.Cursor = Cursors.Hand;
            btnBili.Click += (s, e) => {
                try { Process.Start("https://space.bilibili.com/3379443"); } catch {}
            };

            topPanel.Controls.Add(lblSub);
            topPanel.Controls.Add(lblTitle);
            topPanel.Controls.Add(btnBili);
            this.Controls.Add(topPanel);

            // ================= 客户端扫描区域 =================
            grpClients = new GroupBox();
            grpClients.Text = " 游戏客户端检测 (支持 Steam / 紫P 同时检测) ";
            grpClients.Location = new Point(20, 78);
            grpClients.Size = new Size(705, 120);
            grpClients.ForeColor = Color.FromArgb(31, 41, 55);
            grpClients.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);

            chkListClients = new CheckedListBox();
            chkListClients.Location = new Point(15, 25);
            chkListClients.Size = new Size(535, 82);
            chkListClients.CheckOnClick = true;
            chkListClients.HorizontalScrollbar = true;
            chkListClients.BackColor = Color.FromArgb(255, 255, 255);
            chkListClients.ForeColor = Color.FromArgb(17, 24, 39);
            chkListClients.Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);

            // 重新扫描按钮：纯白卡片式底色 + 浅灰边框 + 灰黑文字
            btnRescan = new Button();
            btnRescan.Text = "重新扫描";
            btnRescan.Location = new Point(565, 18);
            btnRescan.Size = new Size(125, 36);
            btnRescan.BackColor = Color.FromArgb(255, 255, 255);
            btnRescan.ForeColor = Color.FromArgb(55, 65, 81);
            btnRescan.FlatStyle = FlatStyle.Flat;
            btnRescan.FlatAppearance.BorderColor = Color.FromArgb(209, 213, 219);
            btnRescan.FlatAppearance.BorderSize = 1;
            btnRescan.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            btnRescan.Cursor = Cursors.Hand;
            btnRescan.Click += (s, e) => { RunScan(); };

            // 手动选择路径按钮：纯白卡片式底色 + 浅灰边框 + 灰黑文字
            btnBrowse = new Button();
            btnBrowse.Text = "手动选择路径";
            btnBrowse.Location = new Point(565, 62);
            btnBrowse.Size = new Size(125, 36);
            btnBrowse.BackColor = Color.FromArgb(255, 255, 255);
            btnBrowse.ForeColor = Color.FromArgb(55, 65, 81);
            btnBrowse.FlatStyle = FlatStyle.Flat;
            btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(209, 213, 219);
            btnBrowse.FlatAppearance.BorderSize = 1;
            btnBrowse.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            btnBrowse.Cursor = Cursors.Hand;
            btnBrowse.Click += (s, e) => { BrowsePath(); };

            grpClients.Controls.Add(chkListClients);
            grpClients.Controls.Add(btnRescan);
            grpClients.Controls.Add(btnBrowse);
            this.Controls.Add(grpClients);

            // ================= 游戏入口选择（下拉：英文入口 / 日文入口） =================
            var lblPick = new Label();
            lblPick.Text = "选择汉化语言";
            lblPick.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            lblPick.ForeColor = Color.FromArgb(31, 41, 55);
            lblPick.Location = new Point(22, 210);
            lblPick.AutoSize = true;

            cmbScheme = new ComboBox();
            cmbScheme.DropDownStyle = ComboBoxStyle.DropDownList;
            cmbScheme.Location = new Point(150, 206);
            cmbScheme.Size = new Size(280, 28);
            cmbScheme.Font = new Font("Microsoft YaHei UI", 10f, FontStyle.Regular);
            cmbScheme.Items.Add("英文入口");
            cmbScheme.Items.Add("日文入口");
            cmbScheme.SelectedIndexChanged += (s2, e2) => { UpdateStateLabel(); };

            lblState = new Label();
            lblState.Text = "当前状态：检测中…";
            lblState.Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);
            lblState.ForeColor = Color.FromArgb(55, 65, 81);
            lblState.Location = new Point(445, 211);
            lblState.Size = new Size(280, 22);

            this.Controls.Add(lblPick);
            this.Controls.Add(cmbScheme);
            this.Controls.Add(lblState);

            // ================= 操作按钮与免责区域 =================
            grpActions = new GroupBox();
            grpActions.Text = " 风险说明与操作 ";
            grpActions.Location = new Point(20, 246);
            grpActions.Size = new Size(705, 232);
            grpActions.ForeColor = Color.FromArgb(31, 41, 55);
            grpActions.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);

            // 免责说明：不显示滚动条，鼠标滚轮 / 拖动阅读；必须读到最底部并等 3 秒才解锁勾选
            rtbDisc = new TextBox();
            rtbDisc.ReadOnly = true;
            rtbDisc.Multiline = true;
            rtbDisc.BorderStyle = BorderStyle.FixedSingle;
            rtbDisc.ScrollBars = ScrollBars.Vertical;
            // 有滚动条才能用滚轮滚动，但把滚动条隐藏掉（视觉上没有"下滑条"）
            rtbDisc.HandleCreated += (s, e) => { ShowScrollBar(rtbDisc.Handle, 1, false); };
            rtbDisc.WordWrap = true;
            rtbDisc.TabStop = false;
            rtbDisc.Location = new Point(15, 22);
            rtbDisc.Size = new Size(675, 104);
            rtbDisc.BackColor = Color.White;
            rtbDisc.ForeColor = Color.FromArgb(55, 65, 81);
            rtbDisc.Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);
            rtbDisc.Text = "英文入口对应游戏语言 English，日文入口对应 日本語；两个入口互斥，安装时会先移除另一个入口的文件。\r\n\r\n" +
                "执行汉化安装或还原前，请务必确保已完全退出 永恒之塔2 游戏进程。\r\n\r\n" +
                "本工具完全免费开源，仅供交流学习，严禁任何形式的倒卖牟利。\r\n\r\n" +
                "任何对游戏客户端的修改行为均可能存在不可预知的风险（包括但不限于游戏运行异常或账号封禁风险）。请使用者自行评估。";
            rtbDisc.KeyUp += (s, e) => { CheckDiscBottom(); };
            rtbDisc.MouseUp += (s, e) => { CheckDiscBottom(); };
            rtbDisc.MouseWheel += (s, e) => {
                // 滚动条被隐藏，这里自己处理滚轮（每格 2 行）
                HandledMouseEventArgs he = e as HandledMouseEventArgs;
                if (he != null) he.Handled = true;
                SendMessage(rtbDisc.Handle, 0x00B6, IntPtr.Zero, (IntPtr)(e.Delta > 0 ? -2 : 2));
                CheckDiscBottom();
            };

            // 兜底轮询：滚轮 / 键盘滚动都会在 300ms 内被检测到
            tmrPoll = new System.Windows.Forms.Timer();
            tmrPoll.Interval = 300;
            tmrPoll.Tick += (s, e) => {
                if (discRead || discUnlocked) tmrPoll.Stop();
                else CheckDiscBottom();
            };

            // 阅读提示 / 倒计时
            lblReadHint = new Label();
            lblReadHint.Text = "↓ 请向下滚动阅读本条说明，读到底部后 3 秒解锁勾选";
            lblReadHint.Font = new Font("Microsoft YaHei UI", 8.5f, FontStyle.Regular);
            lblReadHint.ForeColor = Color.FromArgb(180, 83, 9);
            lblReadHint.Location = new Point(15, 128);
            lblReadHint.Size = new Size(675, 18);

            tmrDisc = new System.Windows.Forms.Timer();
            tmrDisc.Interval = 1000;
            tmrDisc.Tick += (s, e) => {
                readCountdown--;
                if (readCountdown > 0) {
                    lblReadHint.Text = "已阅读到底部，" + readCountdown + " 秒后可勾选…";
                    lblReadHint.ForeColor = Color.FromArgb(180, 83, 9);
                } else {
                    tmrDisc.Stop();
                    discUnlocked = true;
                    chkAgree.Enabled = true;
                    lblReadHint.Text = "阅读完成，现在可以勾选下方协议。";
                    lblReadHint.ForeColor = Color.FromArgb(22, 163, 74);
                }
            };

            // 风险知晓协议：必须阅读完成后才可勾选
            chkAgree = new CheckBox();
            chkAgree.Text = "我已知晓并自愿承担汉化修改可能带来的一切风险";
            chkAgree.Location = new Point(15, 152);
            chkAgree.AutoSize = true;
            chkAgree.Enabled = false;
            chkAgree.Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);
            chkAgree.ForeColor = Color.FromArgb(180, 83, 9);
            chkAgree.CheckedChanged += (s, e) => {
                if (chkAgree.Checked) {
                    btnApply.Enabled = true;
                    btnApply.BackColor = Color.FromArgb(22, 163, 74);
                    btnApply.ForeColor = Color.White;
                    btnApplyTw.Enabled = true;
                    btnApplyTw.BackColor = Color.FromArgb(37, 99, 235);
                    btnApplyTw.ForeColor = Color.White;
                    AppendLog("已确认知晓风险，汉化功能已解锁。");
                } else {
                    btnApply.Enabled = false;
                    btnApply.BackColor = Color.FromArgb(229, 231, 235);
                    btnApply.ForeColor = Color.FromArgb(156, 163, 175);
                    btnApplyTw.Enabled = false;
                    btnApplyTw.BackColor = Color.FromArgb(229, 231, 235);
                    btnApplyTw.ForeColor = Color.FromArgb(156, 163, 175);
                    AppendLog("已取消勾选协议，汉化功能已锁定。");
                }
            };

            // 一键应用简体
            btnApply = new Button();
            btnApply.Text = "一键应用简体";
            btnApply.Location = new Point(15, 180);
            btnApply.Size = new Size(217, 34);
            btnApply.BackColor = Color.FromArgb(229, 231, 235);
            btnApply.ForeColor = Color.FromArgb(156, 163, 175);
            btnApply.FlatStyle = FlatStyle.Flat;
            btnApply.FlatAppearance.BorderSize = 0;
            btnApply.Font = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold);
            btnApply.Cursor = Cursors.Hand;
            btnApply.Enabled = false;
            btnApply.Click += (s, e) => { ExecuteInstall("zh"); };

            // 一键应用繁体
            btnApplyTw = new Button();
            btnApplyTw.Text = "一键应用繁体";
            btnApplyTw.Location = new Point(239, 180);
            btnApplyTw.Size = new Size(217, 34);
            btnApplyTw.BackColor = Color.FromArgb(229, 231, 235);
            btnApplyTw.ForeColor = Color.FromArgb(156, 163, 175);
            btnApplyTw.FlatStyle = FlatStyle.Flat;
            btnApplyTw.FlatAppearance.BorderSize = 0;
            btnApplyTw.Font = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold);
            btnApplyTw.Cursor = Cursors.Hand;
            btnApplyTw.Enabled = false;
            btnApplyTw.Click += (s, e) => { ExecuteInstall("zh-TW"); };

            // 一键还原：永远可用（无需勾选协议），醒目鲜红色
            btnRestore = new Button();
            btnRestore.Text = "一键还原";
            btnRestore.Location = new Point(463, 180);
            btnRestore.Size = new Size(217, 34);
            btnRestore.BackColor = Color.FromArgb(220, 38, 38);
            btnRestore.ForeColor = Color.White;
            btnRestore.FlatStyle = FlatStyle.Flat;
            btnRestore.FlatAppearance.BorderSize = 0;
            btnRestore.Font = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold);
            btnRestore.Cursor = Cursors.Hand;
            btnRestore.Enabled = true;
            btnRestore.Click += (s, e) => { ExecuteRestore(); };

            grpActions.Controls.Add(rtbDisc);
            grpActions.Controls.Add(lblReadHint);
            grpActions.Controls.Add(chkAgree);
            grpActions.Controls.Add(btnApply);
            grpActions.Controls.Add(btnApplyTw);
            grpActions.Controls.Add(btnRestore);
            this.Controls.Add(grpActions);

            // ================= 实时日志区域 =================
            grpLog = new GroupBox();
            grpLog.Text = " 实时日志与状态显示 ";
            grpLog.Location = new Point(20, 488);
            grpLog.Size = new Size(705, 158);
            grpLog.ForeColor = Color.FromArgb(31, 41, 55);
            grpLog.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);

            txtLog = new TextBox();
            txtLog.Location = new Point(15, 22);
            txtLog.Size = new Size(675, 124);
            txtLog.Multiline = true;
            txtLog.ReadOnly = true;
            txtLog.ScrollBars = ScrollBars.Vertical;
            txtLog.BackColor = Color.FromArgb(17, 24, 39);
            txtLog.ForeColor = Color.FromArgb(52, 211, 153);
            txtLog.Font = new Font("Consolas", 9f);

            grpLog.Controls.Add(txtLog);
            this.Controls.Add(grpLog);

            this.Load += (s, e) => {
                ApplyDefaults();
                // 只读文本框获得焦点会被系统全选，出现整片高亮；这里清空选择并移走焦点
                rtbDisc.Select(0, 0);
                rtbDisc.HideSelection = true;
                this.ActiveControl = btnRestore;
                CheckDiscBottom();
                tmrPoll.Start();
                AppendLog("欢迎使用 AION 2 国际服简繁汉化工具 v" + currentVersion + "！");
                AppendLog("当前入口: " + EntryName + "（对应游戏语言 " + EntryCulture + "）");
                AppendLog("★ 完全免费开源，严禁倒卖牟利 | 制作维护: B站@吃素的佩奇");
                AppendLog("==========================================================");
                RunScan();
                CheckUpdate();
            };
        }

        private void CheckUpdate() {
            var th = new Thread(() => {
                string remoteJson = null;
                try { System.Net.ServicePointManager.SecurityProtocol = (System.Net.SecurityProtocolType)3072; } catch {}
                string[] urls = new string[] {
                    "https://raw.githubusercontent.com/duoluoyuji/Aion2-Global-CN/main/version.json",
                    "https://gh-proxy.com/https://raw.githubusercontent.com/duoluoyuji/Aion2-Global-CN/main/version.json"
                };
                foreach (string u in urls) {
                    try {
                        var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(u);
                        req.Timeout = 2000;
                        req.UserAgent = "Aion2CNTool";
                        using (var resp = req.GetResponse())
                        using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) {
                            string txt = sr.ReadToEnd();
                            if (!string.IsNullOrEmpty(txt)) { remoteJson = txt; break; }
                        }
                    } catch {}
                }
                if (remoteJson == null) return;
                try {
                    string rv = null, ann = "";
                    var m1 = Regex.Match(remoteJson, "\"version\"\\s*:\\s*\"([^\"]+)\"");
                    if (m1.Success) rv = m1.Groups[1].Value;
                    var m2 = Regex.Match(remoteJson, "\"announcement\"\\s*:\\s*\"([^\"]*)\"");
                    if (m2.Success) ann = m2.Groups[1].Value;
                    ann = ann.Replace("\\n", "\n");
                    if (string.IsNullOrEmpty(rv)) return;
                    Version r, l;
                    bool newer;
                    // 只接受同主版本号的更新（v0.x）：旧仓库的 v2.x 属于另一套英文入口包，不能当成本工具的新版本
                    if (Version.TryParse(rv, out r) && Version.TryParse(currentVersion, out l)) newer = (r.Major == l.Major && r > l);
                    else newer = false;
                    if (!newer) return;
                    this.BeginInvoke((Action)(() => {
                        AppendLog("发现新版本 v" + rv + "（当前 v" + currentVersion + "）");
                        var res = MessageBox.Show("发现 AION 2 汉化工具最新版本：v" + rv +
                            "\n\n公告内容：\n" + ann + "\n\n是否立即打开下载页面？",
                            "版本更新提示 - B站@吃素的佩奇", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                        if (res == DialogResult.Yes) {
                            try { Process.Start("https://github.com/duoluoyuji/Aion2-Global-CN/releases"); } catch {}
                        }
                    }));
                } catch {}
            });
            th.IsBackground = true;
            th.Start();
        }

        private void AppendLog(string msg) {
            string line = "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg + "\r\n";
            txtLog.AppendText(line);
        }

        // ================= 安全文件操作辅助方法（解决只读属性与文件锁占用） =================
        private void WriteLog(string msg) {
            try {
                File.AppendAllText(Path.Combine(toolDir, "汉化日志.txt"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + Environment.NewLine, Encoding.UTF8);
            } catch {}
        }

        private static string GetFileSha256(string path) {
            try {
                using (var sha = System.Security.Cryptography.SHA256.Create())
                using (var fs = File.OpenRead(path)) {
                    byte[] h = sha.ComputeHash(fs);
                    var sb = new StringBuilder();
                    foreach (byte b in h) sb.Append(b.ToString("X2"));
                    return sb.ToString();
                }
            } catch { return ""; }
        }

        private static void SafeCopyFile(string src, string dst) {
            if (!File.Exists(src)) {
                throw new FileNotFoundException("源文件不存在: " + src);
            }

            string dstDir = Path.GetDirectoryName(dst);
            if (!Directory.Exists(dstDir)) {
                Directory.CreateDirectory(dstDir);
            }

            // 1. 如果目标已存在，先行清除其只读和隐藏属性（这是导致“访问被拒绝”的最常见元凶）
            if (File.Exists(dst)) {
                try {
                    File.SetAttributes(dst, FileAttributes.Normal);
                } catch {}
            }

            // 2. 先写临时文件，校验一致后再替换；失败时不动原文件（避免留下 0 字节）
            string tmp = dst + ".new";
            Exception lastEx = null;
            for (int retry = 1; retry <= 4; retry++) {
                try {
                    if (File.Exists(tmp)) {
                        try { File.SetAttributes(tmp, FileAttributes.Normal); File.Delete(tmp); } catch {}
                    }
                    using (var fsIn = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.Read))
                    using (var fsOut = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None)) {
                        fsIn.CopyTo(fsOut, 1 << 20);
                        fsOut.Flush(true);
                    }
                    if (GetFileSha256(tmp) != GetFileSha256(src))
                        throw new IOException("复制校验不一致（文件可能未完整写入）: " + dst);

                    string old = dst + ".old";
                    if (File.Exists(old)) { try { File.Delete(old); } catch {} }
                    if (File.Exists(dst)) {
                        try { File.Delete(dst); }
                        catch { File.Move(dst, old); }
                    }
                    File.Move(tmp, dst);
                    try { File.SetAttributes(dst, FileAttributes.Normal); } catch {}
                    return;
                } catch (Exception ex) {
                    lastEx = ex;
                    if (retry < 4) Thread.Sleep(300);
                }
            }
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch {}
            if (lastEx != null) throw lastEx;
        }

        private static void SafeDeleteFile(string path) {
            if (File.Exists(path)) {
                try {
                    File.SetAttributes(path, FileAttributes.Normal);
                    File.Delete(path);
                } catch {}
            }
        }

        private void BrowsePath() {
            using (var dlg = new FolderBrowserDialog()) {
                dlg.Description = "请选择 AION 2 游戏根目录（包含 Aion2 文件夹的那一层目录）：";
                dlg.ShowNewFolderButton = false;
                if (dlg.ShowDialog() == DialogResult.OK) {
                    string sel = dlg.SelectedPath.TrimEnd('\\', '/');
                    string root = ResolveGameRoot(sel);
                    if (root != null) {
                        foreach (var cur in detectedRoots) {
                            if (string.Equals(cur.Path.TrimEnd('\\', '/'), root, StringComparison.OrdinalIgnoreCase)) {
                                MessageBox.Show("该客户端路径已存在于列表中！", "已存在", MessageBoxButtons.OK, MessageBoxIcon.Information);
                                return;
                            }
                        }
                        var target = new ClientTarget { ClientType = "手动指定客户端", Path = root };
                        detectedRoots.Add(target);
                        chkListClients.Items.Add(target.ToString(), true);
                        AppendLog("手动添加游戏目录成功: " + root);
                    } else {
                        MessageBox.Show("所选目录里没有 Aion2\\Content\\Paks，不是有效的 AION 2 游戏目录。\n\n最简单的办法：Steam 里右键游戏 → 管理 → 浏览本地文件，复制地址栏的路径，再重试。", "路径无效", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                }
            }
        }

        private List<string> GetSelectedTargets() {
            var res = new List<string>();
            for (int i = 0; i < chkListClients.Items.Count; i++) {
                if (chkListClients.GetItemChecked(i)) {
                    if (i < detectedRoots.Count) {
                        res.Add(detectedRoots[i].Path);
                    }
                }
            }
            return res;
        }

        private void ReleaseFileLocks() {
            AppendLog("正在检查游戏冲突进程并释放文件锁...");
            string[] conflictList = new string[] { 
                "Aion2", "Aion2-Win64-Shipping", "AION2", "AION2-Win64-Shipping", 
                "NCLauncher", "NCLauncher2", "Purple", "PurpleApp" 
            };
            foreach (var name in conflictList) {
                try {
                    foreach (var p in Process.GetProcessesByName(name)) {
                        AppendLog("-> 检测到运行中的进程: " + name + " (PID: " + p.Id + ")，正在安全关闭...");
                        try {
                            p.Kill();
                            p.WaitForExit(1000);
                        } catch {}
                    }
                } catch {}
            }
            Thread.Sleep(300);
        }

        private void RunScan() {
            chkListClients.Items.Clear();
            detectedRoots.Clear();
            AppendLog("正在执行全盘与注册表深度扫描...");

            detectedRoots = ScanAllGameRoots();

            if (detectedRoots.Count == 0) {
                AppendLog("【提示】未自动扫描到 AION 2 游戏目录。请点击右侧「手动选择路径」按钮指定。");
            } else {
                foreach (var t in detectedRoots) {
                    t.State = GetClientState(t.Path);
                    chkListClients.Items.Add(t.ToString(), true);
                    AppendLog("-> 发现客户端: [" + t.ClientType + "] " + t.Path + "  状态: " + t.State);
                }
                AppendLog("扫描完成！成功识别到 " + detectedRoots.Count + " 个有效游戏客户端版本。");
            }
            UpdateStateLabel();
        }

        private void AddTargetIfNotExists(List<ClientTarget> list, string clientType, string path) {
            if (string.IsNullOrEmpty(path)) return;
            string cleanPath = path.TrimEnd('\\', '/');
            foreach (var cur in list) {
                if (string.Equals(cur.Path.TrimEnd('\\', '/'), cleanPath, StringComparison.OrdinalIgnoreCase)) {
                    return;
                }
            }
            list.Add(new ClientTarget { ClientType = clientType, Path = cleanPath });
        }

        // 只要根目录下有 Aion2\Content\Paks 就算有效客户端（不依赖语言包目录）
        private bool IsGameRoot(string p) {
            if (string.IsNullOrEmpty(p)) return false;
            return Directory.Exists(Path.Combine(p, @"Aion2\Content\Paks"));
        }

        // 把用户选中的目录纠正成真正的游戏根目录（兼容选到 Aion2、common、steamapps）
        private string ResolveGameRoot(string sel) {
            if (string.IsNullOrEmpty(sel)) return null;
            sel = sel.TrimEnd('\\', '/');
            if (string.Equals(Path.GetFileName(sel), "steamapps", StringComparison.OrdinalIgnoreCase)) {
                sel = Path.Combine(sel, "common");
            }
            var cands = new List<string>();
            cands.Add(sel);
            string p1 = Path.GetDirectoryName(sel);
            if (!string.IsNullOrEmpty(p1)) {
                cands.Add(p1);
                string p2 = Path.GetDirectoryName(p1);
                if (!string.IsNullOrEmpty(p2)) cands.Add(p2);
            }
            foreach (var c in cands) {
                if (IsGameRoot(c)) return c;
                try {
                    if (Directory.Exists(c)) {
                        var subs = new List<string>();
                        foreach (var d in Directory.GetDirectories(c)) {
                            if (IsGameRoot(d)) subs.Add(d);
                        }
                        if (subs.Count == 1) return subs[0];
                    }
                } catch {}
            }
            return null;
        }

        private List<ClientTarget> ScanAllGameRoots() {
            var results = new List<ClientTarget>();
            var drives = DriveInfo.GetDrives();

            // 1. Steam 扫描
            AppendLog("[扫描] 正在全盘检索 Steam 游戏库清单...");
            var steamAppsCandidates = new List<string>();
            foreach (var d in drives) {
                if (!d.IsReady) continue;
                string root = d.RootDirectory.FullName;
                string[] candidates = new string[] {
                    Path.Combine(root, @"SteamLibrary\steamapps"),
                    Path.Combine(root, "steamapps"),
                    Path.Combine(root, @"Program Files (x86)\Steam\steamapps"),
                    Path.Combine(root, @"Program Files\Steam\steamapps"),
                    Path.Combine(root, @"Steam\steamapps")
                };
                foreach (var c in candidates) {
                    if (Directory.Exists(c) && !steamAppsCandidates.Contains(c)) {
                        steamAppsCandidates.Add(c);
                    }
                }
            }

            try {
                using (var steamKey = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) {
                    if (steamKey != null) {
                        object p = steamKey.GetValue("SteamPath");
                        if (p != null) {
                            string sa = Path.Combine(p.ToString().Replace('/', '\\'), "steamapps");
                            if (Directory.Exists(sa) && !steamAppsCandidates.Contains(sa)) {
                                steamAppsCandidates.Add(sa);
                            }
                        }
                    }
                }
            } catch {}

            // 1.1 读取 Steam 库清单 libraryfolders.vdf，兼容自定义库名/其它盘的游戏库
            var vdfFiles = new List<string>();
            try {
                foreach (var sa0 in steamAppsCandidates.ToArray()) {
                    string steamRoot = Path.GetDirectoryName(sa0);
                    if (!string.IsNullOrEmpty(steamRoot)) {
                        vdfFiles.Add(Path.Combine(steamRoot, @"config\libraryfolders.vdf"));
                        vdfFiles.Add(Path.Combine(sa0, "libraryfolders.vdf"));
                    }
                }
                using (var steamKey2 = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) {
                    if (steamKey2 != null) {
                        object sp2 = steamKey2.GetValue("SteamPath");
                        if (sp2 != null) {
                            string sp = sp2.ToString().Replace('/', '\\');
                            vdfFiles.Add(Path.Combine(sp, @"config\libraryfolders.vdf"));
                        }
                    }
                }
            } catch {}
            foreach (var v in vdfFiles) {
                if (!File.Exists(v)) continue;
                try {
                    string vt = File.ReadAllText(v);
                    foreach (Match m in Regex.Matches(vt, "\"path\"\\s+\"([^\"]+)\"")) {
                        string lib = m.Groups[1].Value.Replace("\\\\", "\\");
                        string saAdd = Path.Combine(lib, "steamapps");
                        if (Directory.Exists(saAdd) && !steamAppsCandidates.Contains(saAdd)) {
                            steamAppsCandidates.Add(saAdd);
                        }
                    }
                } catch {}
            }

            foreach (var sa in steamAppsCandidates) {
                foreach (var aid in appIds) {
                    string acf = Path.Combine(sa, "appmanifest_" + aid + ".acf");
                    if (File.Exists(acf)) {
                        try {
                            string content = File.ReadAllText(acf);
                            var m = Regex.Match(content, "\"installdir\"\\s+\"([^\"]+)\"");
                            if (m.Success) {
                                string gameDir = Path.Combine(Path.Combine(sa, "common"), m.Groups[1].Value);
                                if (IsGameRoot(gameDir)) {
                                    string label = (aid == "3393110") ? "Steam 国际正式服" : "Steam 测试服";
                                    AddTargetIfNotExists(results, label, gameDir);
                                }
                            }
                        } catch {}
                    }
                }

                string common = Path.Combine(sa, "common");
                if (Directory.Exists(common)) {
                    try {
                        foreach (var dir in Directory.GetDirectories(common)) {
                            if (IsGameRoot(dir)) {
                                string dirName = Path.GetFileName(dir);
                                AddTargetIfNotExists(results, "Steam 游戏库 (" + dirName + ")", dir);
                            }
                        }
                    } catch {}
                }
            }

            // 2. PURPLE (紫P) 扫描
            AppendLog("[扫描] 正在执行 NCSoft PURPLE (紫P) 注册表与磁盘检索...");
            CheckPlayncKey(Registry.LocalMachine, @"SOFTWARE\plaync", results);
            CheckPlayncKey(Registry.LocalMachine, @"SOFTWARE\WOW6432Node\plaync", results);
            CheckPlayncKey(Registry.CurrentUser, @"SOFTWARE\plaync", results);

            CheckUninstallKey(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", results);
            CheckUninstallKey(Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", results);
            CheckUninstallKey(Registry.CurrentUser, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", results);

            // 磁盘通用路径检索
            foreach (var d in drives) {
                if (!d.IsReady) continue;
                string r = d.RootDirectory.FullName;
                string[] purpleCandidates = new string[] {
                    Path.Combine(r, "AION 2"),
                    Path.Combine(r, "Aion2"),
                    Path.Combine(r, @"Games\AION 2"),
                    Path.Combine(r, @"Games\Aion2"),
                    Path.Combine(r, @"PurpleGames\AION 2"),
                    Path.Combine(r, @"PurpleGames\Aion2"),
                    Path.Combine(r, @"Purple\Games\AION 2"),
                    Path.Combine(r, @"NC\AION 2"),
                    Path.Combine(r, @"NCSOFT\AION 2"),
                    Path.Combine(r, @"NCSOFT\Purple\Games\AION 2"),
                    Path.Combine(r, @"Program Files\NCSOFT\Purple\AION 2"),
                    Path.Combine(r, @"Program Files (x86)\NCSOFT\Purple\AION 2")
                };
                foreach (var pc in purpleCandidates) {
                    if (IsGameRoot(pc)) {
                        AddTargetIfNotExists(results, "NCSoft PURPLE 客户端 (磁盘扫描)", pc);
                    }
                }
            }

            // 3. 兜底：每个盘浅层看两层，兼容任意自定义安装位置
            string[] skipNames = new string[] { "Windows", "$Recycle.Bin", "System Volume Information", "Config.Msi", "Recovery", "PerfLogs", "AppData" };
            foreach (var d in drives) {
                if (!d.IsReady) continue;
                string[] tops;
                try { tops = Directory.GetDirectories(d.RootDirectory.FullName); } catch { continue; }
                foreach (var t in tops) {
                    string tn = Path.GetFileName(t);
                    if (Array.IndexOf(skipNames, tn) >= 0) continue;
                    if (IsGameRoot(t)) {
                        AddTargetIfNotExists(results, "磁盘扫描 (" + tn + ")", t);
                        continue;
                    }
                    try {
                        foreach (var g in Directory.GetDirectories(t)) {
                            if (IsGameRoot(g)) {
                                AddTargetIfNotExists(results, "磁盘扫描 (" + tn + "\\" + Path.GetFileName(g) + ")", g);
                            }
                        }
                    } catch {}
                }
            }

            return results;
        }

        private void CheckPlayncKey(RegistryKey rootKey, string subKeyPath, List<ClientTarget> results) {
            try {
                using (var k = rootKey.OpenSubKey(subKeyPath)) {
                    if (k != null) {
                        foreach (var sub in k.GetSubKeyNames()) {
                            using (var app = k.OpenSubKey(sub)) {
                                if (app != null) {
                                    object baseDir = app.GetValue("BaseDir");
                                    if (baseDir != null) {
                                        string b = baseDir.ToString().TrimEnd('\\', '/');
                                        if (IsGameRoot(b)) {
                                            AddTargetIfNotExists(results, "NCSoft PURPLE 客户端 (注册表定位)", b);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {}
        }

        private void CheckUninstallKey(RegistryKey rootKey, string subKeyPath, List<ClientTarget> results) {
            try {
                using (var k = rootKey.OpenSubKey(subKeyPath)) {
                    if (k != null) {
                        foreach (var sub in k.GetSubKeyNames()) {
                            using (var app = k.OpenSubKey(sub)) {
                                if (app != null) {
                                    object name = app.GetValue("DisplayName");
                                    object loc = app.GetValue("InstallLocation");
                                    if (name != null && loc != null) {
                                        string n = name.ToString();
                                        string l = loc.ToString().TrimEnd('\\', '/');
                                        if ((n.IndexOf("AION", StringComparison.OrdinalIgnoreCase) >= 0 || n.IndexOf("Purple", StringComparison.OrdinalIgnoreCase) >= 0) &&
                                            IsGameRoot(l)) {
                                            AddTargetIfNotExists(results, "NCSoft PURPLE 客户端 (系统卸载表)", l);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {}
        }

        private static string ShortRel(string rel) {
            const string prefix = @"Engine\Content\Localization\Engine\Platforms\Windows\";
            if (rel.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return rel.Substring(prefix.Length);
            return rel;
        }

        private string PayloadPath(string entry, string lang) {
            return Path.Combine(toolDir, "payload", entry, lang, "Engine.locres");
        }

        private static bool HasAnyLocres(string root, string[] rels) {
            foreach (string r in rels) {
                if (File.Exists(Path.Combine(root, r))) return true;
            }
            return false;
        }

        private static bool MatchAllLocres(string root, string[] rels, string hash) {
            if (string.IsNullOrEmpty(hash)) return false;
            foreach (string r in rels) {
                string p = Path.Combine(root, r);
                if (!File.Exists(p) || GetFileSha256(p) != hash) return false;
            }
            return true;
        }

        // 判断当前客户端状态：分别看英文入口 / 日文入口两组 locres 在不在、是不是本工具装的。
        // 游戏本体不自带松散 locres，所以「两组都不存在」就是官方原版。
        private string GetClientState(string root) {
            if (!IsGameRoot(root)) return "目录无效";

            bool enHere = HasAnyLocres(root, LocresEn);
            bool jaHere = HasAnyLocres(root, LocresJa);
            if (!enHere && !jaHere) return "官方原版";
            if (enHere && jaHere) return "异常：两个入口的文件同时存在";

            string[] rels = enHere ? LocresEn : LocresJa;
            string entry = enHere ? "en" : "ja";
            string prefix = enHere ? "英文入口" : "日文入口";
            if (MatchAllLocres(root, rels, GetFileSha256(PayloadPath(entry, "zh")))) return prefix + " · 简体中文";
            if (MatchAllLocres(root, rels, GetFileSha256(PayloadPath(entry, "zh-TW")))) return prefix + " · 繁体中文";
            return "未知汉化文件";
        }

        // 还原 = 删掉全部四个入口文件。删掉即回落官方原版，不需要任何备份。
        private int RestoreClientFiles(string root) {
            int removed = 0;
            foreach (string rel in AllLocres) {
                string p = Path.Combine(root, rel);
                if (!File.Exists(p)) continue;
                SafeDeleteFile(p);
                if (!File.Exists(p)) {
                    removed++;
                    AppendLog("[移除] " + ShortRel(rel) + "   已删除");
                    WriteLog("移除 " + root + " : " + rel);
                }
            }
            return removed;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool ShowScrollBar(IntPtr hWnd, int wBar, bool bShow);
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        // 判断是否已滚动到说明文字最底部
        private void CheckDiscBottom() {
            if (discRead || discUnlocked || rtbDisc.TextLength == 0) return;
            int lastLine = rtbDisc.GetLineFromCharIndex(rtbDisc.TextLength - 1);
            int lineStart = rtbDisc.GetFirstCharIndexFromLine(lastLine);
            int idx = rtbDisc.GetCharIndexFromPosition(new Point(3, rtbDisc.ClientSize.Height - 3));
            if (idx >= lineStart) StartReadCountdown();
        }

        private void StartReadCountdown() {
            if (discRead) return;
            discRead = true;
            readCountdown = 3;
            lblReadHint.Text = "已阅读到底部，3 秒后可勾选…";
            lblReadHint.ForeColor = Color.FromArgb(180, 83, 9);
            tmrDisc.Start();
        }

        private void UpdateStateLabel() {
            var list = GetSelectedTargets();
            if (list.Count == 0) { lblState.Text = "当前状态：未选择客户端"; return; }
            lblState.Text = "当前状态：" + GetClientState(list[0]);
        }

        // 读取游戏语言：Aion2 下可能有 Saved / Saved_Steam / Saved_TW 等多个配置目录
        private List<string> GetGameCultures() {
            var result = new List<string>();
            try {
                string baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Aion2");
                if (!Directory.Exists(baseDir)) return result;
                foreach (string d in Directory.GetDirectories(baseDir)) {
                    string ini = Path.Combine(d, @"Config\Windows\Engine.ini");
                    if (!File.Exists(ini)) continue;
                    string t;
                    try { t = File.ReadAllText(ini); } catch { continue; }
                    Match m = Regex.Match(t, "(?im)^\\s*Culture\\s*=\\s*\"?([^\"\r\n]+)\"?");
                    if (m.Success) {
                        string v = m.Groups[1].Value.Trim();
                        if (v.Length > 0 && !result.Contains(v)) result.Add(v);
                    }
                }
            } catch {}
            return result;
        }

        private static string CultureName(string c) {
            switch (c.ToLower()) {
                case "en": return "English (en)";
                case "en-us": return "English (en-US)";
                case "ja": return "日本語 (ja)";
                case "ja-jp": return "日本語 (ja-JP)";
                case "ko": return "한국어 (ko)";
                case "ko-kr": return "한국어 (ko-KR)";
                default: return c;
            }
        }

        private void ExecuteInstall(string lang) {
            var targets = GetSelectedTargets();
            if (targets.Count == 0) {
                MessageBox.Show("请至少勾选一个目标游戏客户端！", "未选择客户端", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string entry = EntryKey;
            string entryName = EntryName, langName = LangNameOf(lang), culture = EntryCulture;
            string[] writeRels = EntryLocres, dropRels = OtherLocres;
            string dropName = (entry == "ja") ? "英文入口" : "日文入口";

            // 安装前自检：Engine.locres 必须是完整文件（约 15 MB，防止压缩包没解压完整/被杀软清空）
            string payload = PayloadPath(entry, lang);
            if (!File.Exists(payload) || new FileInfo(payload).Length < 1000000) {
                string msg = "安装包不完整，找不到有效的 Engine.locres：" + payload;
                AppendLog("【错误】安装包不完整: " + msg);
                WriteLog("安装包不完整: " + msg);
                MessageBox.Show(msg + "\n\n请重新解压压缩包，并检查杀毒软件是否拦截。", "安装包不完整", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            // 只接受真正的 AION 2 客户端目录
            foreach (string root in targets) {
                if (!IsGameRoot(root)) {
                    AppendLog("【拦截】不是有效的 AION 2 目录: " + root);
                    MessageBox.Show("不是有效的 AION 2 游戏目录：\n" + root +
                        "\n\n请在 Steam / PURPLE 中校验游戏文件完整性，再重新安装汉化。",
                        "客户端目录无效", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
            }

            // 语言一致性提醒：只提示，不修改 Engine.ini
            bool langMismatch = false;
            var cultures = GetGameCultures();
            if (cultures.Count == 0) {
                AppendLog("[语言] 未读取到游戏语言配置，跳过语言校验。");
            } else {
                var names = new List<string>();
                foreach (string c in cultures) names.Add(CultureName(c));
                string cText = string.Join(" / ", names.ToArray());
                AppendLog("[语言] 游戏当前语言: " + cText);
                bool ok = false;
                foreach (string c in cultures) {
                    string lc = c.ToLower();
                    if (entry == "ja" ? lc.StartsWith("ja") : lc.StartsWith("en")) ok = true;
                }
                if (!ok) {
                    langMismatch = true;
                    var r = MessageBox.Show("检测到游戏当前语言为「" + cText + "」，但你选择的是「" + entryName + "」。\n\n" +
                        "本工具不会修改游戏语言设置。安装后请先把游戏内语言改为「" + culture + "」并完全退出游戏，汉化才会显示。\n\n" +
                        "是否仍然继续安装？",
                        "语言与入口不一致", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                    if (r != DialogResult.Yes) {
                        AppendLog("用户取消：语言与入口不一致。");
                        return;
                    }
                }
            }

            ReleaseFileLocks();

            AppendLog(">>> 部署方案: " + entryName + " · " + langName + "（先移除" + dropName + "残留）");

            int count = 0;
            try {
                for (int i = 0; i < targets.Count; i++) {
                    string root = targets[i];
                    count++;
                    AppendLog("==========================================================");
                    AppendLog(">>> 正在处理目标客户端 [" + count + "/" + targets.Count + "]: " + root);

                    // 互斥：先移除另一入口的文件，否则英文会按 key 回退覆盖日文
                    foreach (string rel in dropRels) {
                        string p = Path.Combine(root, rel);
                        if (File.Exists(p)) {
                            SafeDeleteFile(p);
                            if (File.Exists(p)) throw new IOException("无法移除冲突文件（可能被占用）: " + rel);
                            AppendLog("[移除] " + ShortRel(rel) + "   已删除（" + dropName + "残留）");
                            WriteLog("移除 " + root + " : " + rel);
                        }
                    }
                    // 再写本入口的两个 locres，不碰 pak、不碰字体、不改 Engine.ini
                    foreach (string rel in writeRels) {
                        SafeCopyFile(payload, Path.Combine(root, rel));
                        AppendLog("[写入] " + ShortRel(rel) + "   " + new FileInfo(payload).Length.ToString("N0") + " B   OK");
                    }
                    WriteLog("安装 " + root + " : " + entryName + " · " + langName + "  " +
                        GetFileSha256(Path.Combine(root, writeRels[0])) + " (" + new FileInfo(payload).Length + " 字节)");
                    AppendLog("-> 该客户端部署完成！");
                }

                AppendLog("==========================================================");
                AppendLog("安装完成: " + entryName + " · " + langName + " (共 " + count + " 个客户端)");
                AppendLog("游戏未在运行，现在直接启动游戏即可。");
                UpdateStateLabel();

                string done = "安装完成：" + entryName + " · " + langName + "\n共处理 " + count + " 个客户端。\n游戏未在运行，现在直接启动游戏即可。";
                if (langMismatch) done += "\n\n注意：请先把游戏内语言改为「" + culture + "」，否则看不到中文。";
                MessageBox.Show(done + "\n\n制作：B站@吃素的佩奇", "安装完成 - B站@吃素的佩奇", MessageBoxButtons.OK, MessageBoxIcon.Information);
            } catch (Exception ex) {
                AppendLog("【错误】文件写入失败: " + ex.Message);
                WriteLog("安装失败: " + ex.Message);
                MessageBox.Show("汉化部署失败！\n\n【可能原因与解决办法】：\n1. 游戏或启动器仍在后台运行（文件被占用）：请结束相关进程后重试；\n2. 文件夹被设置了只读属性或权限不足：请右键【以管理员身份运行】本工具；\n3. 杀毒软件拦截了游戏文件修改。\n\n详细系统报错：" + ex.Message + "\n\n日志文件：" + Path.Combine(toolDir, "汉化日志.txt"), "写入受阻", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ExecuteRestore() {
            var targets = GetSelectedTargets();
            if (targets.Count == 0) {
                MessageBox.Show("请至少勾选一个目标游戏客户端！", "未选择客户端", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            ReleaseFileLocks();

            int count = 0, restored = 0;
            try {
                for (int i = 0; i < targets.Count; i++) {
                    string root = targets[i];
                    count++;
                    AppendLog("==========================================================");
                    AppendLog(">>> 正在还原目标客户端 [" + count + "/" + targets.Count + "]: " + root);

                    int removed = RestoreClientFiles(root);
                    if (removed > 0) {
                        restored++;
                        AppendLog("-> 已删除汉化文件，该客户端回落为官方原版。");
                    } else {
                        AppendLog("-> 没有发现汉化文件，该客户端本来就是官方原版。");
                    }
                }

                AppendLog("==========================================================");
                if (restored > 0) AppendLog("已还原为官方原版 (共处理 " + restored + " 个客户端)");
                else AppendLog("没有发现汉化文件，未做任何改动。");
                UpdateStateLabel();

                if (restored > 0)
                    MessageBox.Show("已还原为官方原版 (共处理 " + restored + " 个客户端)！\n\n游戏未在运行，现在直接启动游戏即可。\n\n制作：B站@吃素的佩奇", "还原成功 - B站@吃素的佩奇", MessageBoxButtons.OK, MessageBoxIcon.Information);
                else
                    MessageBox.Show("没有发现汉化文件，未做任何改动。\n这些客户端本来就是官方原版。", "无需还原 - B站@吃素的佩奇", MessageBoxButtons.OK, MessageBoxIcon.Information);
            } catch (Exception ex) {
                AppendLog("【错误】还原文件失败: " + ex.Message);
                MessageBox.Show("还原失败！\n\n【可能原因与解决办法】：\n1. 游戏或启动器仍在后台运行：请彻底退出后再重试；\n2. 权限不足：请右键【以管理员身份运行】本工具。\n\n详细系统报错：" + ex.Message, "还原受阻", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    static class Program {
        [STAThread]
        static void Main() {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => {
                Exception ex = e.ExceptionObject as Exception;
                string msg = (ex != null) ? ex.Message : "未知异常";
                MessageBox.Show("程序发生异常: " + msg + "\n建议以管理员身份重新运行。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            };

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
