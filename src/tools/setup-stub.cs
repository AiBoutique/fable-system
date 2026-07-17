// Fable System setup stub - the whole kit rides inside this exe as an embedded
// payload. On run: extract to a private %TEMP% staging dir, hand off to the
// kit's install.ps1 (Windows PowerShell 5.1, what a stock machine has), pass
// every argument through (-Unattended, -TargetHome, -ProjectPath, -ForceMemory),
// propagate the installer's exit code (0 pass / 1 fail / 2 user abort), and
// clean the staging dir. Compiled by tools\build-exe.ps1 with the .NET
// Framework csc.exe every Windows box ships - no dependencies.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

class FableSetup
{
    static int Main(string[] args)
    {
        string stage = Path.Combine(Path.GetTempPath(), "fable-setup-" + Guid.NewGuid().ToString("N"));
        string zip = Path.Combine(stage, "payload.zip");
        string kit = Path.Combine(stage, "kit");
        bool unattended = false;
        for (int i = 0; i < args.Length; i++)
            if (string.Equals(args[i], "-Unattended", StringComparison.OrdinalIgnoreCase)) unattended = true;
        try
        {
            Directory.CreateDirectory(stage);
            using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (res == null) { Console.Error.WriteLine("payload.zip resource missing - rebuild with tools\\build-exe.ps1"); return 1; }
                using (FileStream f = File.Create(zip))
                {
                    byte[] buf = new byte[81920]; int n;
                    while ((n = res.Read(buf, 0, buf.Length)) > 0) f.Write(buf, 0, n);
                }
            }
            // extraction via Windows PowerShell's Expand-Archive (present since 5.0);
            // single quotes doubled so exotic temp paths (e.g. O'Brien) survive
            int ex = RunPs("-NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -LiteralPath '"
                + zip.Replace("'", "''") + "' -DestinationPath '" + kit.Replace("'", "''") + "' -Force\"");
            if (ex != 0) { Console.Error.WriteLine("payload extraction failed (exit " + ex + ")"); return ex; }
            string installer = Path.Combine(kit, "install.ps1");
            if (!File.Exists(installer)) { Console.Error.WriteLine("extracted payload has no install.ps1 - corrupt build"); return 1; }
            string passthru = "";
            for (int i = 0; i < args.Length; i++) passthru += " " + Quote(args[i]);
            int code = RunPs("-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"" + passthru);
            if (!unattended)
            {
                // double-click UX: keep the console window until the user has read the result.
                // Piped/closed stdin returns immediately (ReadLine -> null), so scripts never hang.
                Console.Write("\n  Press Enter to close... ");
                Console.ReadLine();
            }
            return code;
        }
        finally
        {
            try { if (Directory.Exists(stage)) Directory.Delete(stage, true); } catch { /* best effort; %TEMP% */ }
        }
    }

    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOf(' ') < 0 && a.IndexOf('"') < 0) return a;
        // canonical Windows argv quoting: backslash runs double before an embedded
        // quote and before the closing quote - a tab-completed "C:\some path\" stays
        // intact and can no longer swallow the next argument (e.g. -Unattended)
        System.Text.StringBuilder sb = new System.Text.StringBuilder("\"");
        int bs = 0;
        foreach (char c in a)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; continue; }
            sb.Append('\\', bs); sb.Append(c); bs = 0;
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    static int RunPs(string psArgs)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
        psi.Arguments = psArgs;
        psi.UseShellExecute = false;   // inherit this console: prompts, output, and stdin all flow
        // clear any inherited PSModulePath (e.g. from a PowerShell 7 parent) so
        // Windows PowerShell 5.1 rebuilds its own defaults - INSTALL.bat does the same
        psi.EnvironmentVariables["PSModulePath"] = "";
        using (Process p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }
}
