// Chained Teams Panel - side panel for the Chained Teams host mod.
// Writes commands to data\panel_cmd.txt, reads data\state.json.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Web.Script.Serialization;

namespace ChainedTeamsPanel
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string data = null; string selftest = null;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--data" && i + 1 < args.Length) data = args[++i];
                else if (args[i] == "--selftest" && i + 1 < args.Length) selftest = args[++i];
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (selftest != null)
            {
                PanelForm f = new PanelForm(selftest);
                return f.SelfTest();
            }
            Application.Run(new PanelForm(data));
            return 0;
        }
    }

    class PanelForm : Form
    {
        static readonly Color Bg = Color.FromArgb(30, 31, 34);
        static readonly Color Bg2 = Color.FromArgb(43, 45, 49);
        static readonly Color Fg = Color.FromArgb(225, 225, 228);
        static readonly Color Dim = Color.FromArgb(150, 152, 158);
        static readonly Color Accent = Color.FromArgb(70, 110, 190);
        static readonly Color RedC = Color.FromArgb(220, 90, 90);
        static readonly Color BlueC = Color.FromArgb(100, 150, 240);

        string dataDir;       // null if not found
        string personalDir;   // null if personal build absent
        Dictionary<string, object> state;
        DateTime lastGood = DateTime.MinValue;
        bool stale = true;
        string lastError = "";

        ToolTip tips = new ToolTip();
        Dictionary<Button, EventHandler> handlers = new Dictionary<Button, EventHandler>();
        Panel tabStrip, body;
        List<Button> tabButtons = new List<Button>();
        List<Panel> pages = new List<Panel>();
        Label status; ListBox logBox;
        CheckBox topMost;
        System.Windows.Forms.Timer poll;

        // Race
        Label raceTime, raceInfo; ListBox splitsBlue, splitsRed;
        // Players
        ListView players; ComboBox tpSkip;
        // Practice
        ListBox skips; TextBox markName;
        // Fun
        Dictionary<string, TrackBar> sliders = new Dictionary<string, TrackBar>();
        Dictionary<string, Label> sliderLabels = new Dictionary<string, Label>();
        Dictionary<string, CheckBox> toggles = new Dictionary<string, CheckBox>();
        string dragging = null; bool syncing = false;
        // Achievements
        ListBox achList;

        public PanelForm(string dataArg)
        {
            Text = "Chained Teams Panel";
            Width = 360; Height = 760;
            MinimumSize = new Size(320, 500);
            BackColor = Bg; ForeColor = Fg;
            Font = new Font("Segoe UI", 9f);
            StartPosition = FormStartPosition.Manual;
            Location = new Point(Screen.PrimaryScreen.WorkingArea.Right - Width - 10, Screen.PrimaryScreen.WorkingArea.Top + 40);

            ResolveDataDir(dataArg);
            BuildUi();
            TopMost = true;

            poll = new System.Windows.Forms.Timer();
            poll.Interval = 1000;
            poll.Tick += delegate { PollState(); };
            poll.Start();
            PollState();
        }

        // ---------- locating ----------
        void ResolveDataDir(string arg)
        {
            List<string> cands = new List<string>();
            if (!string.IsNullOrEmpty(arg)) cands.Add(arg);
            else
            {
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                cands.Add(Path.Combine(exeDir, @"ue4ss\Mods\ChainedTeams\data"));
                cands.Add(Path.Combine(exeDir, @"..\launcher\ue4ss\Mods\ChainedTeams\data"));
            }
            dataDir = null;
            foreach (string c in cands)
            {
                try { if (Directory.Exists(c)) { dataDir = Path.GetFullPath(c); break; } } catch { }
            }
            personalDir = null;
            if (dataDir != null)
            {
                try
                {
                    string p = Path.GetFullPath(Path.Combine(dataDir, @"..\..\ChainedPersonal"));
                    if (Directory.Exists(p)) personalDir = p;
                }
                catch { }
            }
        }

        // ---------- commands ----------
        public void Send(string cmd) { WriteLine(dataDir == null ? null : Path.Combine(dataDir, "panel_cmd.txt"), cmd); }
        void SendPersonal(string cmd) { WriteLine(personalDir == null ? null : Path.Combine(personalDir, "command.txt"), cmd); }

        void WriteLine(string path, string cmd)
        {
            if (path == null) { SetStatus("Mod data folder not found - command not sent."); return; }
            byte[] bytes = new UTF8Encoding(false).GetBytes(cmd + "\n");
            for (int attempt = 0; attempt < 10; attempt++)
            {
                try
                {
                    using (FileStream fs = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
                        fs.Write(bytes, 0, bytes.Length);
                    SetStatus("Sent: " + cmd);
                    return;
                }
                catch (IOException) { Thread.Sleep(50); }
                catch (UnauthorizedAccessException) { Thread.Sleep(50); }
            }
            SetStatus("Could not write command (file locked): " + cmd);
        }

        void SetStatus(string s) { if (status != null) status.Text = s; }

        // ---------- UI helpers ----------
        Button Btn(Control parent, string text, string tip, EventHandler click)
        {
            Button b = new Button();
            b.Text = text; b.FlatStyle = FlatStyle.Flat; b.BackColor = Bg2; b.ForeColor = Fg;
            b.FlatAppearance.BorderColor = Color.FromArgb(70, 72, 78);
            b.Height = 30; b.Margin = new Padding(3); b.AutoSize = false; b.Width = 100;
            if (click != null) { b.Click += click; handlers[b] = click; }
            tips.SetToolTip(b, tip);
            parent.Controls.Add(b);
            return b;
        }

        FlowLayoutPanel Row(Control parent)
        {
            FlowLayoutPanel f = new FlowLayoutPanel();
            f.AutoSize = true; f.AutoSizeMode = AutoSizeMode.GrowAndShrink; f.WrapContents = true;
            f.Dock = DockStyle.Top; f.Padding = new Padding(2); f.BackColor = Bg;
            parent.Controls.Add(f); f.BringToFront();
            return f;
        }

        Label Heading(Control parent, string text)
        {
            Label l = new Label(); l.Text = text; l.ForeColor = Dim; l.Dock = DockStyle.Top; l.Height = 22;
            l.TextAlign = ContentAlignment.BottomLeft; l.Padding = new Padding(4, 0, 0, 0);
            parent.Controls.Add(l); l.BringToFront();
            return l;
        }

        ListBox List(Control parent, int h, string tip)
        {
            ListBox lb = new ListBox(); lb.Dock = DockStyle.Top; lb.Height = h; lb.BackColor = Bg2; lb.ForeColor = Fg;
            lb.BorderStyle = BorderStyle.None; lb.IntegralHeight = false;
            tips.SetToolTip(lb, tip);
            parent.Controls.Add(lb); lb.BringToFront();
            return lb;
        }

        Panel AddPage(string name)
        {
            Panel p = new Panel(); p.Dock = DockStyle.Fill; p.BackColor = Bg; p.AutoScroll = true; p.Visible = false;
            p.Padding = new Padding(6);
            body.Controls.Add(p); pages.Add(p);
            int idx = pages.Count - 1;
            Button b = new Button(); b.Text = name; b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0;
            b.AutoSize = true; b.AutoSizeMode = AutoSizeMode.GrowAndShrink; b.Margin = new Padding(0); b.Padding = new Padding(2, 2, 2, 2);
            b.ForeColor = Fg; b.BackColor = Bg;
            b.Click += delegate { ShowPage(idx); };
            tabStrip.Controls.Add(b); tabButtons.Add(b);
            return p;
        }

        void ShowPage(int idx)
        {
            for (int i = 0; i < pages.Count; i++)
            {
                pages[i].Visible = i == idx;
                tabButtons[i].BackColor = i == idx ? Accent : Bg;
            }
        }

        // ---------- build ----------
        void BuildUi()
        {
            // bottom area
            Panel bottom = new Panel(); bottom.Dock = DockStyle.Bottom; bottom.Height = 120; bottom.BackColor = Bg; bottom.Padding = new Padding(6, 2, 6, 6);
            Controls.Add(bottom);
            logBox = new ListBox(); logBox.Dock = DockStyle.Fill; logBox.BackColor = Bg2; logBox.ForeColor = Dim; logBox.BorderStyle = BorderStyle.None; logBox.IntegralHeight = false;
            tips.SetToolTip(logBox, "Last messages from the mod.");
            bottom.Controls.Add(logBox);
            status = new Label(); status.Dock = DockStyle.Top; status.Height = 36; status.ForeColor = Fg; status.Text = "Starting...";
            tips.SetToolTip(status, "Connection status and the last command sent.");
            bottom.Controls.Add(status);

            // top bar
            FlowLayoutPanel top = new FlowLayoutPanel(); top.Dock = DockStyle.Top; top.Height = 34; top.BackColor = Bg; top.Padding = new Padding(4, 4, 4, 0);
            topMost = new CheckBox(); topMost.Text = "Always on top"; topMost.Checked = true; topMost.AutoSize = true; topMost.ForeColor = Fg; topMost.Margin = new Padding(3, 6, 10, 0);
            topMost.CheckedChanged += delegate { TopMost = topMost.Checked; };
            tips.SetToolTip(topMost, "Keep this panel above the game window.");
            top.Controls.Add(topMost);
            Button snap = Btn(top, "Snap right", "Move the panel to the right edge of the main screen.", delegate { SnapRight(); });
            snap.Width = 90; snap.Height = 26;

            tabStrip = new FlowLayoutPanel(); tabStrip.Dock = DockStyle.Top; tabStrip.Height = 30; tabStrip.BackColor = Bg; tabStrip.Padding = new Padding(4, 2, 4, 0);
            body = new Panel(); body.Dock = DockStyle.Fill; body.BackColor = Bg;
            Controls.Add(body); Controls.Add(tabStrip); Controls.Add(top);

            BuildRace(AddPage("Race"));
            BuildPlayers(AddPage("Players"));
            BuildPractice(AddPage("Practice"));
            BuildFun(AddPage("Fun"));
            BuildOutfits(AddPage("Outfits"));
            if (personalDir != null) BuildAch(AddPage("Achievements"));
            ShowPage(0);
        }

        void SnapRight()
        {
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(wa.Right - Width, wa.Top);
            Height = wa.Height;
        }

        void BuildRace(Panel p)
        {
            raceTime = new Label(); raceTime.Text = "--:--.-"; raceTime.Font = new Font("Segoe UI", 28f, FontStyle.Bold);
            raceTime.Dock = DockStyle.Top; raceTime.Height = 60; raceTime.TextAlign = ContentAlignment.MiddleCenter;
            tips.SetToolTip(raceTime, "Current race time.");
            p.Controls.Add(raceTime);
            raceInfo = new Label(); raceInfo.Dock = DockStyle.Top; raceInfo.Height = 20; raceInfo.ForeColor = Dim; raceInfo.TextAlign = ContentAlignment.MiddleCenter;
            p.Controls.Add(raceInfo); raceInfo.BringToFront();
            FlowLayoutPanel r = Row(p);
            Btn(r, "Start", "Start the race countdown.", delegate { Send("start"); });
            Btn(r, "Reset", "Stop the race and send everyone back to the start.", delegate { Send("reset"); });
            Btn(r, "Balance", "Split players into even Red and Blue teams.", delegate { Send("balance"); });
            Btn(r, "Rematch", "Reset and start again with the same teams.", delegate { Send("rematch"); });
            Btn(r, "Show splits", "Print the split times in chat.", delegate { Send("splits"); });
            Heading(p, "Blue splits");
            splitsBlue = List(p, 130, "Checkpoint times for team Blue.");
            Heading(p, "Red splits");
            splitsRed = List(p, 130, "Checkpoint times for team Red.");
        }

        void BuildPlayers(Panel p)
        {
            players = new ListView(); players.View = View.Details; players.FullRowSelect = true; players.MultiSelect = false; players.HideSelection = false;
            players.Dock = DockStyle.Top; players.Height = 220; players.BackColor = Bg2; players.ForeColor = Fg; players.BorderStyle = BorderStyle.None;
            players.Columns.Add("Name", 150); players.Columns.Add("Team", 70); players.Columns.Add("Progress", 80);
            tips.SetToolTip(players, "Players in the session. Select one to use the buttons below.");
            p.Controls.Add(players);
            FlowLayoutPanel r = Row(p);
            Btn(r, "Make Red", "Move the selected player to team Red.", delegate { MakeTeam("red"); });
            Btn(r, "Make Blue", "Move the selected player to team Blue.", delegate { MakeTeam("blue"); });
            Heading(p, "Teleport selected player to spot");
            FlowLayoutPanel r2 = Row(p);
            tpSkip = new ComboBox(); tpSkip.DropDownStyle = ComboBoxStyle.DropDownList; tpSkip.Width = 200; tpSkip.BackColor = Bg2; tpSkip.ForeColor = Fg; tpSkip.FlatStyle = FlatStyle.Flat; tpSkip.Margin = new Padding(3, 7, 3, 3);
            tips.SetToolTip(tpSkip, "Saved spot to send the player to.");
            r2.Controls.Add(tpSkip);
            Btn(r2, "Teleport to spot...", "Teleport the selected player to the chosen spot.", delegate { TpPlayer(); }).Width = 120;
        }

        string SelectedPlayer()
        {
            if (players.SelectedItems.Count == 0) { SetStatus("Select a player first."); return null; }
            return players.SelectedItems[0].Text;
        }
        void MakeTeam(string t) { string n = SelectedPlayer(); if (n != null) Send("team " + n + " " + t); }
        void TpPlayer()
        {
            string n = SelectedPlayer(); if (n == null) return;
            if (tpSkip.SelectedItem == null) { SetStatus("Choose a spot first."); return; }
            Send("tpplayer " + n + " " + tpSkip.SelectedItem.ToString());
        }

        void BuildPractice(Panel p)
        {
            FlowLayoutPanel r = Row(p);
            Btn(r, "Save", "Save your current position (quick save).", delegate { Send("save"); });
            Btn(r, "Load", "Go back to your saved position.", delegate { Send("load"); });
            Btn(r, "Top", "Teleport to the top of the map.", delegate { Send("top"); });
            Heading(p, "Saved spots");
            skips = List(p, 220, "Saved spots. Select one, then Teleport or Delete.");
            FlowLayoutPanel r2 = Row(p);
            Btn(r2, "Teleport", "Teleport to the selected spot.", delegate { SkipCmd("tp"); });
            Btn(r2, "Delete", "Delete the selected spot.", delegate { SkipCmd("delmark"); });
            Heading(p, "New spot name");
            FlowLayoutPanel r3 = Row(p);
            markName = new TextBox(); markName.Width = 200; markName.BackColor = Bg2; markName.ForeColor = Fg; markName.BorderStyle = BorderStyle.FixedSingle; markName.Margin = new Padding(3, 7, 3, 3);
            tips.SetToolTip(markName, "Name for the new spot (no spaces).");
            r3.Controls.Add(markName);
            Btn(r3, "Mark here", "Save your current position under this name.", delegate { MarkHere(); });
        }

        void SkipCmd(string verb)
        {
            if (skips.SelectedItem == null) { SetStatus("Select a spot first."); return; }
            Send(verb + " " + skips.SelectedItem.ToString());
        }
        void MarkHere()
        {
            string n = markName.Text.Trim().Replace(' ', '_');
            if (n.Length == 0) { SetStatus("Type a spot name first."); return; }
            Send("mark " + n);
        }

        void BuildFun(Panel p)
        {
            AddSlider(p, "gravity", "Gravity", 10, 300, "Gravity multiplier (0.10 - 3.00). Sent when you let go.");
            AddSlider(p, "speed", "Speed", 50, 300, "Run speed multiplier (0.50 - 3.00). Sent when you let go.");
            AddSlider(p, "jump", "Jump", 50, 400, "Jump height multiplier (0.50 - 4.00). Sent when you let go.");
            AddSlider(p, "scale", "Scale", 30, 300, "Player size multiplier (0.30 - 3.00). Sent when you let go.");
            AddSlider(p, "chain", "Chain length", 50, 200, "Chain length multiplier (0.50 - 2.00). Sent when you let go.");
            FlowLayoutPanel r = Row(p);
            AddToggle(r, "ice", "Ice floor", "Make floors slippery.");
            AddToggle(r, "push", "Pushing", "Let players shove each other.");
            AddToggle(r, "chaos", "Chaos mode", "Random fun effects every so often.");
            FlowLayoutPanel r2 = Row(p);
            Btn(r2, "Fling everyone", "Launch every player into the air.", delegate { Send("fling"); }).Width = 110;
            Btn(r2, "Fling Red", "Launch team Red.", delegate { Send("flingteam red"); });
            Btn(r2, "Fling Blue", "Launch team Blue.", delegate { Send("flingteam blue"); });
            Btn(r2, "Reset all fun", "Put every fun setting back to normal.", delegate { Send("resetfun"); }).Width = 110;
        }

        void AddSlider(Panel p, string key, string label, int min, int max, string tip)
        {
            Label l = Heading(p, label + ": 1.00");
            TrackBar t = new TrackBar(); t.Minimum = min; t.Maximum = max; t.Value = 100; t.TickStyle = TickStyle.None;
            t.Dock = DockStyle.Top; t.Height = 30; t.BackColor = Bg; t.SmallChange = 5; t.LargeChange = 25;
            tips.SetToolTip(t, tip); tips.SetToolTip(l, tip);
            p.Controls.Add(t); t.BringToFront();
            sliders[key] = t; sliderLabels[key] = l;
            string k = key; string lab = label;
            t.ValueChanged += delegate { l.Text = lab + ": " + Fmt(t.Value / 100.0); };
            t.MouseDown += delegate { dragging = k; };
            t.MouseUp += delegate { dragging = null; SliderRelease(k); };
            t.KeyUp += delegate { SliderRelease(k); };
        }

        static string Fmt(double v) { return v.ToString("0.00", CultureInfo.InvariantCulture); }

        void SliderRelease(string key) { Send("set " + key + " " + Fmt(sliders[key].Value / 100.0)); }

        void AddToggle(Control parent, string key, string text, string tip)
        {
            CheckBox c = new CheckBox(); c.Text = text; c.AutoSize = true; c.ForeColor = Fg; c.Margin = new Padding(3, 6, 8, 3);
            tips.SetToolTip(c, tip);
            string k = key;
            c.CheckedChanged += delegate { if (!syncing) Send("set " + k + " " + (c.Checked ? "on" : "off")); };
            parent.Controls.Add(c); toggles[key] = c;
        }

        void BuildOutfits(Panel p)
        {
            FlowLayoutPanel r = Row(p);
            Btn(r, "Random outfit (me)", "Give yourself a random outfit.", delegate { Send("outfit random"); }).Width = 150;
            Btn(r, "Random outfits (everyone)", "Give every player a random outfit.", delegate { Send("outfit randomall"); }).Width = 170;
        }

        void BuildAch(Panel p)
        {
            FlowLayoutPanel r = Row(p);
            Btn(r, "Refresh list", "Ask the mod to rewrite the achievement list.", delegate { SendPersonal("ach"); });
            Btn(r, "Unlock selected", "Unlock the selected achievement.", delegate { AchSelected(); }).Width = 110;
            Btn(r, "Unlock all", "Unlock every achievement.", delegate { SendPersonal("ach all"); });
            Btn(r, "Wings", "Give yourself wings.", delegate { SendPersonal("wings"); });
            achList = List(p, 380, "Achievements. [x] = unlocked.");
        }

        void AchSelected()
        {
            if (achList.SelectedItem == null) { SetStatus("Select an achievement first."); return; }
            string s = achList.SelectedItem.ToString().Trim();
            int sp = s.IndexOf(' ');
            string n = sp > 0 ? s.Substring(0, sp) : s;
            int num;
            if (!int.TryParse(n, out num)) { SetStatus("Could not read achievement number."); return; }
            SendPersonal("ach " + num);
        }

        // ---------- state ----------
        void PollState()
        {
            if (dataDir == null)
            {
                SetStatus("Mod data folder not found. Put this exe next to ChainedTeams.exe or use --data <path>.");
                return;
            }
            string path = Path.Combine(dataDir, "state.json");
            try
            {
                if (File.Exists(path))
                {
                    string txt;
                    using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                        txt = sr.ReadToEnd();
                    Dictionary<string, object> d = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(txt);
                    if (d != null)
                    {
                        state = d;
                        lastGood = File.GetLastWriteTime(path);
                        lastError = "";
                    }
                }
            }
            catch (Exception ex) { lastError = ex.GetType().Name; }

            stale = state == null || (DateTime.Now - lastGood).TotalSeconds > 5;
            if (stale)
            {
                string s = "Waiting for game...";
                if (status != null && !status.Text.StartsWith("Sent:")) SetStatus(s);
                else if (status != null) SetStatus(s + "  (" + status.Text + ")");
            }
            else if (status != null && !status.Text.StartsWith("Sent:"))
                SetStatus("Connected - mod " + Str(state, "version") + (Bool(state, "inGame") ? "" : " (not in game)"));
            if (state != null) Apply();
            if (personalDir != null && achList != null) LoadAch();
        }

        void LoadAch()
        {
            try
            {
                string f = Path.Combine(personalDir, "achievements.txt");
                if (!File.Exists(f)) return;
                string[] lines = File.ReadAllLines(f);
                if (SameItems(achList, lines)) return;
                int sel = achList.SelectedIndex;
                achList.Items.Clear();
                foreach (string l in lines) if (l.Trim().Length > 0) achList.Items.Add(l.Trim());
                if (sel < achList.Items.Count) achList.SelectedIndex = sel;
            }
            catch { }
        }

        static string Str(Dictionary<string, object> d, string k)
        {
            object o; if (d != null && d.TryGetValue(k, out o) && o != null) return Convert.ToString(o, CultureInfo.InvariantCulture); return "";
        }
        static bool Bool(Dictionary<string, object> d, string k)
        {
            object o; if (d != null && d.TryGetValue(k, out o) && o is bool) return (bool)o; return false;
        }
        static double Num(Dictionary<string, object> d, string k, double def)
        {
            object o; if (d != null && d.TryGetValue(k, out o) && o != null) { try { return Convert.ToDouble(o, CultureInfo.InvariantCulture); } catch { } } return def;
        }
        static ArrayList Arr(Dictionary<string, object> d, string k)
        {
            object o; if (d != null && d.TryGetValue(k, out o)) { ArrayList a = o as ArrayList; if (a != null) return a; } return new ArrayList();
        }

        static bool SameItems(ListBox lb, IList<string> items)
        {
            List<string> clean = new List<string>();
            foreach (string s in items) if (s.Trim().Length > 0) clean.Add(s.Trim());
            if (lb.Items.Count != clean.Count) return false;
            for (int i = 0; i < clean.Count; i++) if ((string)lb.Items[i] != clean[i]) return false;
            return true;
        }
        static void SetItems(ListBox lb, List<string> items)
        {
            if (SameItems(lb, items)) return;
            object sel = lb.SelectedItem;
            lb.BeginUpdate(); lb.Items.Clear();
            foreach (string s in items) lb.Items.Add(s);
            if (sel != null && lb.Items.Contains(sel)) lb.SelectedItem = sel;
            lb.EndUpdate();
        }

        void Apply()
        {
            // race
            string rt = Str(state, "raceTime");
            raceTime.Text = rt.Length > 0 ? rt : "--:--.-";
            raceInfo.Text = !Bool(state, "isRace") ? "Not in race mode" : (Bool(state, "raceRunning") ? "Race running" : "Race not started");
            Dictionary<string, object> splits = null;
            object so; if (state.TryGetValue("splits", out so)) splits = so as Dictionary<string, object>;
            SetItems(splitsBlue, SplitLines(splits, "BLUE"));
            SetItems(splitsRed, SplitLines(splits, "RED"));

            // players
            List<string[]> rows = new List<string[]>();
            foreach (object po in Arr(state, "players"))
            {
                Dictionary<string, object> pd = po as Dictionary<string, object>; if (pd == null) continue;
                rows.Add(new string[] { Str(pd, "name"), Str(pd, "team"), Num(pd, "pct", 0).ToString("0.0", CultureInfo.InvariantCulture) + " %" });
            }
            string selName = players.SelectedItems.Count > 0 ? players.SelectedItems[0].Text : null;
            bool same = players.Items.Count == rows.Count;
            for (int i = 0; same && i < rows.Count; i++)
                for (int j = 0; j < 3; j++) if (players.Items[i].SubItems[j].Text != rows[i][j]) { same = false; break; }
            if (!same)
            {
                players.BeginUpdate(); players.Items.Clear();
                foreach (string[] r in rows)
                {
                    ListViewItem it = new ListViewItem(r);
                    it.ForeColor = r[1].ToUpperInvariant() == "RED" ? RedC : (r[1].ToUpperInvariant() == "BLUE" ? BlueC : Fg);
                    players.Items.Add(it);
                    if (r[0] == selName) it.Selected = true;
                }
                players.EndUpdate();
            }

            // skips
            List<string> sk = new List<string>();
            foreach (object o in Arr(state, "skips")) if (o != null) sk.Add(o.ToString());
            SetItems(skips, sk);
            bool skSame = tpSkip.Items.Count == sk.Count;
            for (int i = 0; skSame && i < sk.Count; i++) if ((string)tpSkip.Items[i] != sk[i]) skSame = false;
            if (!skSame)
            {
                object sel = tpSkip.SelectedItem;
                tpSkip.Items.Clear(); foreach (string s in sk) tpSkip.Items.Add(s);
                if (sel != null && tpSkip.Items.Contains(sel)) tpSkip.SelectedItem = sel;
            }

            // settings
            object setO; Dictionary<string, object> set = null;
            if (state.TryGetValue("settings", out setO)) set = setO as Dictionary<string, object>;
            if (set != null)
            {
                syncing = true;
                foreach (KeyValuePair<string, TrackBar> kv in sliders)
                {
                    if (dragging == kv.Key || kv.Value.Focused && Control.MouseButtons != MouseButtons.None) continue;
                    if (!set.ContainsKey(kv.Key)) continue;
                    int v = (int)Math.Round(Num(set, kv.Key, 1.0) * 100);
                    v = Math.Max(kv.Value.Minimum, Math.Min(kv.Value.Maximum, v));
                    if (kv.Value.Value != v) kv.Value.Value = v;
                }
                foreach (KeyValuePair<string, CheckBox> kv in toggles)
                    if (set.ContainsKey(kv.Key) && kv.Value.Checked != Bool(set, kv.Key)) kv.Value.Checked = Bool(set, kv.Key);
                syncing = false;
            }

            // log
            List<string> lg = new List<string>();
            foreach (object o in Arr(state, "log")) if (o != null) lg.Add(o.ToString());
            if (lg.Count > 6) lg = lg.GetRange(lg.Count - 6, 6);
            SetItems(logBox, lg);
        }

        static List<string> SplitLines(Dictionary<string, object> splits, string team)
        {
            List<string> res = new List<string>();
            if (splits == null) return res;
            object o; if (!splits.TryGetValue(team, out o)) return res;
            ArrayList a = o as ArrayList; if (a == null) return res;
            foreach (object e in a)
            {
                ArrayList pair = e as ArrayList;
                if (pair != null && pair.Count >= 2) res.Add(pair[1] + "   " + pair[0]);
                else if (e != null) res.Add(e.ToString());
            }
            return res;
        }

        // ---------- self test ----------
        public int SelfTest()
        {
            if (dataDir == null) { Console.Error.WriteLine("data dir not found"); return 2; }
            PollState();
            try
            {
                IntPtr hh = Handle; foreach (Control c in AllControls(this)) hh = c.Handle;
                PollState();
                foreach (Control c in AllControls(this))
                {
                    Button b = c as Button;
                    if (b == null || tabButtons.Contains(b) || b.Text == "Snap right") continue;
                    if (b.Text == "Make Red" || b.Text == "Make Blue" || b.Text.StartsWith("Teleport"))
                    {
                        if (players.Items.Count > 0) players.Items[0].Selected = true;
                        if (tpSkip.Items.Count > 0) tpSkip.SelectedIndex = tpSkip.Items.Count - 1;
                        if (skips.Items.Count > 0) skips.SelectedIndex = 0;
                    }
                    if (b.Text == "Delete" && skips.Items.Count > 1) skips.SelectedIndex = 1;
                    if (b.Text == "Mark here") markName.Text = "my spot";
                    if (b.Text == "Unlock selected" && achList.Items.Count > 0) achList.SelectedIndex = 2 < achList.Items.Count ? 2 : 0;
                    EventHandler h; if (handlers.TryGetValue(b, out h)) h(b, EventArgs.Empty);
                }
                foreach (KeyValuePair<string, TrackBar> kv in sliders)
                {
                    TrackBar t = kv.Value;
                    t.Value = (t.Minimum + t.Maximum) / 2 + 3;
                    SliderRelease(kv.Key);
                }
                foreach (CheckBox c in toggles.Values) c.Checked = !c.Checked;
                foreach (CheckBox c in toggles.Values) c.Checked = !c.Checked;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex.ToString()); return 1; }
            return 0;
        }

        static IEnumerable<Control> AllControls(Control root)
        {
            foreach (Control c in root.Controls)
            {
                yield return c;
                foreach (Control k in AllControls(c)) yield return k;
            }
        }
    }
}
