// Inline MSBuild tasks for doment's build checks, compiled by RoslynCodeTaskFactory.
// The factory compiles against a reduced reference set (System.Text.Json cannot be
// referenced), so this file sticks to netstandard 2.0 APIs.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class DomentFrameworkState : Task
{
    [Required]
    public string FrameworkPath { get; set; }

    [Required]
    public string PinFile { get; set; }

    public bool Strict { get; set; }

    public override bool Execute()
    {
        string pin = DomentGit.ReadPin(PinFile);
        if (pin == null)
        {
            Log.LogError(null, "DOMENT006", null, null, 0, 0, 0, 0,
                "{0} must hold one full 40-character commit hash", PinFile);
            return false;
        }

        string path = FrameworkPath.TrimEnd('/', '\\');
        DomentGit.Result prefix;
        try
        {
            prefix = DomentGit.Run(path, "rev-parse", "--show-prefix");
        }
        catch (Win32Exception)
        {
            Report("DOMENT002", "darkraise-framework at {0} cannot be verified: git not found", path);
            return !Log.HasLoggedErrors;
        }

        // A plain directory inside another repository answers rev-parse with that
        // repository's root, so only an empty prefix means `path` is a checkout's top level.
        DomentGit.Result head = prefix.ExitCode == 0 && prefix.Output.Trim().Length == 0
            ? DomentGit.Run(path, "rev-parse", "HEAD")
            : null;
        if (head == null || head.ExitCode != 0)
        {
            Report("DOMENT002", "darkraise-framework at {0} cannot be verified: not a git checkout", path);
            return !Log.HasLoggedErrors;
        }

        string actual = head.Output.Trim();
        string firstUnclean = DomentGit.FirstUncleanPath(path);
        if (actual != pin)
        {
            string text = string.Format("darkraise-framework at {0} is at {1}, but the pin is {2}", path, actual, pin);
            if (firstUnclean != null)
            {
                text += "; not clean, first: " + firstUnclean;
            }
            Report("DOMENT001", "{0}", text);
        }
        else if (firstUnclean != null)
        {
            Report("DOMENT001", "darkraise-framework at {0} is at the pin {1} but not clean, first: {2}", path, pin, firstUnclean);
        }

        return !Log.HasLoggedErrors;
    }

    private void Report(string code, string format, params object[] args)
    {
        if (Strict)
        {
            Log.LogError(null, code, null, null, 0, 0, 0, 0, format, args);
        }
        else
        {
            Log.LogWarning(null, code, null, null, 0, 0, 0, 0, format, args);
        }
    }
}

public static class DomentGit
{
    public sealed class Result
    {
        public int ExitCode;
        public string Output;
    }

    private static readonly Regex PinPattern = new Regex("^[0-9a-f]{40}$");

    // Returns the pinned commit, or null when the file is missing or does not hold one full hash.
    public static string ReadPin(string pinFile)
    {
        if (!File.Exists(pinFile))
        {
            return null;
        }
        string content = File.ReadAllText(pinFile).TrimEnd('\r', '\n');
        return PinPattern.IsMatch(content) ? content : null;
    }

    // The first path that makes the tree not clean, in git's output order, or null when it is clean:
    // anything but an ignored path with a segment named bin, obj, .vs or .idea.
    public static string FirstUncleanPath(string path)
    {
        Result status = Run(path, "--no-optional-locks", "status", "--porcelain=v1", "-z",
            "--ignored=matching", "--untracked-files=all");
        if (status.ExitCode != 0)
        {
            return "(git status failed)";
        }
        string[] entries = status.Output.Split('\0');
        for (int i = 0; i < entries.Length; i++)
        {
            string entry = entries[i];
            if (entry.Length < 4)
            {
                continue;
            }
            string code = entry.Substring(0, 2);
            string entryPath = entry.Substring(3);
            if (code[0] == 'R' || code[0] == 'C')
            {
                i++;
            }
            if (code == "!!" && HasBuildOutputSegment(entryPath))
            {
                continue;
            }
            return entryPath;
        }
        return null;
    }

    private static bool HasBuildOutputSegment(string path)
    {
        foreach (string segment in path.Split('/'))
        {
            if (segment == "bin" || segment == "obj" || segment == ".vs" || segment == ".idea")
            {
                return true;
            }
        }
        return false;
    }

    // Runs git in `workingDirectory`. Throws Win32Exception when git cannot be started.
    public static Result Run(string workingDirectory, params string[] args)
    {
        var arguments = new StringBuilder();
        arguments.Append("-C ").Append(Quote(workingDirectory));
        foreach (string arg in args)
        {
            arguments.Append(' ').Append(Quote(arg));
        }
        var info = new ProcessStartInfo("git", arguments.ToString())
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
        };
        info.Environment["GIT_OPTIONAL_LOCKS"] = "0";
        using (Process process = Process.Start(info))
        {
            var stderr = new StringBuilder();
            process.ErrorDataReceived += (sender, e) => { if (e.Data != null) stderr.AppendLine(e.Data); };
            process.BeginErrorReadLine();
            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return new Result { ExitCode = process.ExitCode, Output = output };
        }
    }

    // Quotes one argument for ProcessStartInfo.Arguments (the Windows command-line rules, which .NET also applies on Unix).
    private static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new[] { ' ', '\t', '"', '\\' }) < 0)
        {
            return arg;
        }
        var quoted = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
            }
            else
            {
                quoted.Append('\\', backslashes);
            }
            backslashes = 0;
            quoted.Append(c);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
