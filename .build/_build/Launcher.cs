using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

// MAS_AIO standalone launcher.
// The MAS_AIO.cmd payload is GZip compressed and Base64 encoded in Payload.
// At runtime it is extracted (byte-for-byte) to %LOCALAPPDATA%\MAS_AIO\MAS_AIO.cmd
// and executed by the native cmd.exe in the same console window.
// Note: %LOCALAPPDATA% is used (not %TEMP%) because MAS refuses to run when its
// own path contains the Temp folder path.
internal static class MasLauncher
{
    private const string Payload = "__PAYLOAD_BASE64__";
    private const string ScriptName = "MAS_AIO.cmd";
    private const string CacheFolderName = "MAS_AIO";

    private static int Main(string[] args)
    {
        try
        {
            string cacheDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                CacheFolderName);
            Directory.CreateDirectory(cacheDir);
            string scriptPath = Path.Combine(cacheDir, ScriptName);

            byte[] data = ExtractPayload();

            // Hidden self-test hook used at build/verify time only.
            if (args.Length == 1 && args[0] == "--mas-extract-test")
            {
                File.WriteAllBytes(scriptPath, data);
                Console.WriteLine("Extracted: " + scriptPath);
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] hash = sha.ComputeHash(data);
                    StringBuilder sb = new StringBuilder(hash.Length * 2);
                    foreach (byte b in hash) sb.Append(b.ToString("x2"));
                    Console.WriteLine("SHA256: " + sb);
                }
                return 0;
            }

            // Drop the script (overwrite any cached copy). If the file is locked
            // because another instance is running it, reuse the existing copy.
            try
            {
                File.WriteAllBytes(scriptPath, data);
                try { File.SetAttributes(scriptPath, FileAttributes.Normal); }
                catch { /* non-fatal */ }
            }
            catch (IOException)
            {
                if (!File.Exists(scriptPath)) throw;
            }

            string cmdPath = Path.Combine(Environment.SystemDirectory, "cmd.exe");

            // Build: cmd /c ""<scriptPath>" <forwarded args>"
            // The outer pair of quotes is stripped by cmd.exe (first/last quote rule),
            // leaving a properly quoted script path plus the original arguments.
            string arguments = "/c \"\"" + scriptPath + "\"" + BuildForwardedArgs(args) + "\"";

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = cmdPath,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = false,
                WorkingDirectory = cacheDir
            };

            Process p = Process.Start(psi);
            p.WaitForExit();
            return p.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Launcher error: " + ex.Message);
            return 1;
        }
    }

    private static byte[] ExtractPayload()
    {
        byte[] gz = Convert.FromBase64String(Payload);
        using (MemoryStream ms = new MemoryStream(gz))
        using (GZipStream zs = new GZipStream(ms, CompressionMode.Decompress))
        using (MemoryStream outMs = new MemoryStream())
        {
            zs.CopyTo(outMs);
            return outMs.ToArray();
        }
    }

    private static string BuildForwardedArgs(string[] args)
    {
        StringBuilder sb = new StringBuilder();
        foreach (string a in args)
        {
            sb.Append(' ');
            if (a.Length == 0)
            {
                sb.Append("\"\"");
            }
            else if (a.IndexOf(' ') >= 0 || a.IndexOf('\t') >= 0 || a.IndexOf('"') >= 0)
            {
                sb.Append('"');
                sb.Append(a.Replace("\"", "\\\""));
                sb.Append('"');
            }
            else
            {
                sb.Append(a);
            }
        }
        return sb.ToString();
    }
}
