// Updater.cs - checks GitHub for a newer Chained Teams release and installs it before launching.
// Keeps the player's own data (saved spots etc. in any "data" folder) and keeps extra mods enabled in mods.txt.
// Any problem (offline, GitHub down) just skips the update.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Web.Script.Serialization;

static class Updater
{
    const string LatestApi = "https://api.github.com/repos/Kash7H/chained-teams/releases/latest";

    public static void Run(string baseDir)
    {
        try
        {
            foreach (string old in Directory.GetFiles(baseDir, "*.old"))
            {
                try { File.Delete(old); } catch { }
            }

            string verFile = Path.Combine(baseDir, "version.txt");
            string local = File.Exists(verFile) ? File.ReadAllText(verFile).Trim() : "0.0.0";

            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
            WebClient wc = new WebClient();
            wc.Headers.Add("User-Agent", "ChainedTeams-Updater");
            string json = wc.DownloadString(LatestApi);
            Dictionary<string, object> rel = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
            string latest = ((string)rel["tag_name"]).TrimStart('v', 'V');

            if (!IsNewer(latest, local))
            {
                Console.WriteLine("Chained Teams is up to date (v" + local + ").");
                return;
            }

            string url = null;
            foreach (object a in (ArrayList)rel["assets"])
            {
                Dictionary<string, object> asset = (Dictionary<string, object>)a;
                string name = (string)asset["name"];
                if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                {
                    url = (string)asset["browser_download_url"];
                    break;
                }
            }
            if (url == null) return;

            Console.WriteLine("Updating Chained Teams v" + local + " -> v" + latest + "...");
            string tmp = Path.Combine(Path.GetTempPath(), "ChainedTeamsUpdate");
            if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
            Directory.CreateDirectory(tmp);
            string zip = Path.Combine(tmp, "update.zip");
            wc.DownloadFile(url, zip);
            string extracted = Path.Combine(tmp, "x");
            ZipFile.ExtractToDirectory(zip, extracted);

            // the zip has one top folder (ChainedTeams\...)
            string root = extracted;
            string[] dirs = Directory.GetDirectories(extracted);
            if (dirs.Length == 1 && Directory.GetFiles(extracted).Length == 0) root = dirs[0];

            string self = Process.GetCurrentProcess().MainModule.FileName;
            int copied = CopyTree(root, root, baseDir, self);
            File.WriteAllText(verFile, latest);
            Console.WriteLine("Updated to v" + latest + " (" + copied + " files).");
        }
        catch (Exception e)
        {
            Console.WriteLine("Update check skipped (" + e.Message + ").");
        }
    }

    static bool IsNewer(string a, string b)
    {
        try { return new Version(a) > new Version(b); }
        catch { return false; }
    }

    static int CopyTree(string dir, string root, string baseDir, string self)
    {
        int n = 0;
        foreach (string file in Directory.GetFiles(dir))
        {
            string rel = file.Substring(root.Length).TrimStart('\\');
            string relLower = rel.ToLowerInvariant();
            if (relLower.Contains("\\data\\")) continue;                    // player's saved spots etc.
            string target = Path.Combine(baseDir, rel);
            if (Path.GetFileName(rel).Equals("ChainedTeams.exe", StringComparison.OrdinalIgnoreCase))
                target = self;                                             // replace whichever launcher is running

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                if (relLower.EndsWith("mods\\mods.txt") && File.Exists(target))
                {
                    MergeModsTxt(file, target);
                }
                else
                {
                    if (string.Equals(Path.GetFullPath(target), Path.GetFullPath(self), StringComparison.OrdinalIgnoreCase))
                    {
                        string old = self + ".old";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(self, old);                              // a running exe can be renamed, not overwritten
                    }
                    File.Copy(file, target, true);
                }
                n++;
            }
            catch (Exception e)
            {
                Console.WriteLine("  skipped " + rel + " (" + e.Message + ")");
            }
        }
        foreach (string sub in Directory.GetDirectories(dir)) n += CopyTree(sub, root, baseDir, self);
        return n;
    }

    // keep every mod the player already has enabled; add any new ones from the update; Keybinds stays last
    static void MergeModsTxt(string fromUpdate, string current)
    {
        List<string> lines = new List<string>();
        foreach (string l in File.ReadAllLines(current))
            if (l.Trim().Length > 0 && !l.StartsWith("Keybinds")) lines.Add(l);
        foreach (string l in File.ReadAllLines(fromUpdate))
        {
            string name = l.Split(':')[0].Trim();
            if (name.Length == 0 || name.StartsWith(";") || name == "Keybinds") continue;
            bool have = false;
            foreach (string e in lines) if (e.Split(':')[0].Trim() == name) have = true;
            if (!have) lines.Add(l);
        }
        lines.Add("Keybinds : 1");
        File.WriteAllLines(current, lines.ToArray());
    }
}
