// ChainedTeams launcher - starts Chained Together through Steam and injects UE4SS
// from this launcher's own ue4ss\ folder. Leaves the game folder untouched.
// Build: build.bat (C# 5, .NET Framework 4.x csc, x64).
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;

static class ChainedTeams
{
    const string AppId = "2567870";
    const string ProcName = "ChainedTogether-Win64-Shipping";
    const int TimeoutSec = 120;

    static int Main(string[] args)
    {
        Console.Title = "Chained Teams";
        bool checkOnly = args.Length > 0 && args[0] == "--check";
        bool testInject = args.Length > 1 && args[0] == "--test-inject"; // --test-inject <pid> <dll>
        try
        {
            if (testInject)
            {
                Inject(int.Parse(args[1]), Path.GetFullPath(args[2]));
                Console.WriteLine("Test injection OK.");
                return 0;
            }

            Console.WriteLine("Starting Chained Together with Chained Teams mod...");
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string dll = Path.Combine(baseDir, "ue4ss\\UE4SS.dll");
            if (!File.Exists(dll))
                return Fail("The mod files are missing. Please unzip the WHOLE folder (keep the 'ue4ss' folder next to ChainedTeams.exe) and try again.");

            string game = FindGame();
            if (game == null)
                return Fail("Couldn't find Chained Together. Make sure Steam is installed and the game is installed in Steam.");
            Console.WriteLine("Found game: " + game);

            string win64 = Path.Combine(game, "ChainedTogether\\Binaries\\Win64");
            if (File.Exists(Path.Combine(win64, "dwmapi.dll")))
                Console.WriteLine("Note: a mod loader (dwmapi.dll) is already installed in the game folder; it will load the mod itself, skipping injection.");

            if (checkOnly) { Console.WriteLine("Check OK."); return 0; }

            Process proc = FindRunning();
            if (proc != null)
                return Fail("Chained Together is already running. Close it first, then start Chained Teams again.");

            Process.Start("steam://rungameid/" + AppId);
            Console.WriteLine("Waiting for the game to open (Steam may take a moment)...");

            var sw = Stopwatch.StartNew();
            while (proc == null)
            {
                if (sw.Elapsed.TotalSeconds > TimeoutSec)
                    return Fail("The game didn't start within 2 minutes. Is Steam logged in? Try starting the game once from Steam, close it, then try again.");
                Thread.Sleep(25);
                proc = FindRunning();
            }

            // Inject as early as possible. UE4SS also tolerates being loaded after
            // engine init (it keeps scanning until the engine objects exist).
            Thread.Sleep(100);
            if (HasModule(proc, "UE4SS.dll"))
            {
                Console.WriteLine("Mod loader already active. Have fun!");
            }
            else
            {
                Inject(proc.Id, dll);
                Console.WriteLine("Mod loaded. Have fun!");
            }
            Thread.Sleep(3000);
            return 0;
        }
        catch (Exception ex)
        {
            return Fail("Something went wrong: " + ex.Message +
                "\n\nIf your antivirus blocked ChainedTeams.exe, allow it and try again.");
        }
    }

    static int Fail(string msg)
    {
        Console.WriteLine();
        Console.WriteLine("PROBLEM: " + msg);
        Console.WriteLine();
        Console.WriteLine("Press any key to close...");
        try { Console.ReadKey(true); } catch { }
        return 1;
    }

    static Process FindRunning()
    {
        Process[] p = Process.GetProcessesByName(ProcName);
        return p.Length > 0 ? p[0] : null;
    }

    static bool HasModule(Process p, string name)
    {
        try
        {
            foreach (ProcessModule m in p.Modules)
                if (string.Equals(m.ModuleName, name, StringComparison.OrdinalIgnoreCase)) return true;
        }
        catch { }
        return false;
    }

    // ---------- Steam / game discovery ----------
    static string FindGame()
    {
        string steam = null;
        using (var k = Registry.CurrentUser.OpenSubKey("Software\\Valve\\Steam"))
            if (k != null) steam = k.GetValue("SteamPath") as string;
        if (steam == null)
            using (var k = Registry.LocalMachine.OpenSubKey("SOFTWARE\\WOW6432Node\\Valve\\Steam"))
                if (k != null) steam = k.GetValue("InstallPath") as string;
        if (steam == null) return null;
        steam = steam.Replace('/', '\\');

        var libs = new System.Collections.Generic.List<string>();
        libs.Add(steam);
        string vdf = Path.Combine(steam, "steamapps\\libraryfolders.vdf");
        if (File.Exists(vdf))
            foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s*\"([^\"]+)\""))
                libs.Add(m.Groups[1].Value.Replace("\\\\", "\\"));

        foreach (string lib in libs)
        {
            string dir = Path.Combine(lib, "steamapps\\common\\ChainedTogether");
            if (File.Exists(Path.Combine(dir, "ChainedTogether\\Binaries\\Win64\\" + ProcName + ".exe")))
                return Path.GetFullPath(dir);
        }
        return null;
    }

    // ---------- Classic CreateRemoteThread(LoadLibraryW) injection ----------
    const uint PROCESS_ALL = 0x0002 | 0x0008 | 0x0010 | 0x0020 | 0x0400; // create thread, vm op/read/write, query
    const uint MEM_COMMIT_RESERVE = 0x3000, MEM_RELEASE = 0x8000, PAGE_RW = 0x04;

    [DllImport("kernel32", SetLastError = true)] static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, UIntPtr s, uint t, uint p);
    [DllImport("kernel32", SetLastError = true)] static extern bool VirtualFreeEx(IntPtr h, IntPtr a, UIntPtr s, uint t);
    [DllImport("kernel32", SetLastError = true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, UIntPtr s, out UIntPtr w);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, UIntPtr ss, IntPtr start, IntPtr param, uint f, out uint tid);
    [DllImport("kernel32", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] static extern bool GetExitCodeThread(IntPtr h, out uint code);
    [DllImport("kernel32", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string n);
    [DllImport("kernel32", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);

    static void Inject(int pid, string dllPath)
    {
        if (!Environment.Is64BitProcess) throw new Exception("launcher must be 64-bit");
        IntPtr h = OpenProcess(PROCESS_ALL, false, pid);
        if (h == IntPtr.Zero) throw new Exception("couldn't access the game process (error " + Marshal.GetLastWin32Error() + ")");
        IntPtr mem = IntPtr.Zero;
        try
        {
            byte[] bytes = System.Text.Encoding.Unicode.GetBytes(dllPath + "\0");
            UIntPtr size = (UIntPtr)(uint)bytes.Length;
            mem = VirtualAllocEx(h, IntPtr.Zero, size, MEM_COMMIT_RESERVE, PAGE_RW);
            if (mem == IntPtr.Zero) throw new Exception("VirtualAllocEx failed (" + Marshal.GetLastWin32Error() + ")");
            UIntPtr written;
            if (!WriteProcessMemory(h, mem, bytes, size, out written)) throw new Exception("WriteProcessMemory failed (" + Marshal.GetLastWin32Error() + ")");
            // kernel32 is mapped at the same base in every process of a boot session.
            IntPtr loadLib = GetProcAddress(GetModuleHandleW("kernel32.dll"), "LoadLibraryW");
            uint tid;
            IntPtr th = CreateRemoteThread(h, IntPtr.Zero, UIntPtr.Zero, loadLib, mem, 0, out tid);
            if (th == IntPtr.Zero) throw new Exception("CreateRemoteThread failed (" + Marshal.GetLastWin32Error() + ")");
            WaitForSingleObject(th, 60000);
            uint code; GetExitCodeThread(th, out code); // low 32 bits of HMODULE; 0 = load failed
            CloseHandle(th);
            if (code == 0) throw new Exception("the game refused to load the mod (LoadLibrary returned null)");
        }
        finally
        {
            if (mem != IntPtr.Zero) VirtualFreeEx(h, mem, UIntPtr.Zero, MEM_RELEASE);
            CloseHandle(h);
        }
    }
}
