// Inline MSBuild tasks for doment's build checks, compiled by RoslynCodeTaskFactory.
// The factory compiles against a reduced reference set (System.Text.Json cannot be
// referenced), so this file sticks to netstandard 2.0 APIs.
using System;
using System.Collections.Generic;
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

public class DomentThirdPartyCheck : Task
{
    [Required]
    public string RegisterFile { get; set; }

    public string ProjectAssetsFile { get; set; }

    public string ProjectPath { get; set; }

    public bool BuildOnly { get; set; }

    public override bool Execute()
    {
        DomentRegister register = DomentRegister.Load(RegisterFile);
        foreach (string problem in register.Problems)
        {
            Log.LogError(null, "DOMENT013", null, null, 0, 0, 0, 0, "{0}: {1}", RegisterFile, problem);
        }
        if (string.IsNullOrEmpty(ProjectAssetsFile) || !File.Exists(ProjectAssetsFile))
        {
            return !Log.HasLoggedErrors;
        }

        DomentAssets assets = DomentAssets.Load(ProjectAssetsFile);
        foreach (KeyValuePair<string, string> package in assets.Packages)
        {
            string id = package.Key;
            string version = package.Value;
            if (register.Exceptions.Exists(row => row.Matches(id)) || register.Platform.Exists(row => row.Matches(id)))
            {
                continue;
            }
            DomentRegisterRow tool = register.Tools.Find(row => row.Matches(id));
            if (tool == null)
            {
                Log.LogError(null, "DOMENT010", null, null, 0, 0, 0, 0,
                    "{0}: package {1} {2} is in no table of {3} ({4})", ProjectPath, id, version, RegisterFile, assets.HowArrived(id));
            }
            else if (!BuildOnly)
            {
                Log.LogError(null, "DOMENT011", null, null, 0, 0, 0, 0,
                    "{0} ships but resolves build-and-test-only package {1} {2}, row {3} of {4} ({5})",
                    ProjectPath, id, version, tool.Id, RegisterFile, assets.HowArrived(id));
            }
        }
        Log.LogMessage(MessageImportance.High, "DOMENT-PACKAGES: {0}", assets.Packages.Count);
        return !Log.HasLoggedErrors;
    }
}

public class DomentReferenceCheck : Task
{
    public ITaskItem[] References { get; set; }

    [Required]
    public string FrameworkPath { get; set; }

    [Required]
    public string RepoRoot { get; set; }

    public string TargetFramework { get; set; }

    public bool BuildOnly { get; set; }

    public string ProjectPath { get; set; }

    private static readonly StringComparison PathComparison =
        Path.DirectorySeparatorChar == '\\' ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    public override bool Execute()
    {
        string framework = AsDirectory(FrameworkPath);
        string repo = AsDirectory(RepoRoot);
        bool windows = (TargetFramework ?? "").StartsWith("net10.0-windows", StringComparison.OrdinalIgnoreCase);
        foreach (ITaskItem reference in References ?? new ITaskItem[0])
        {
            string full = Normalize(reference.GetMetadata("FullPath"));
            if (full.StartsWith(framework, PathComparison))
            {
                string relative = full.Substring(framework.Length);
                bool allowed = Same(relative, "src/Darkraise/Darkraise.csproj")
                    || (windows && (Same(relative, "src/Darkraise.Win32UI/Darkraise.Win32UI.csproj")
                        || Same(relative, "src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj")));
                if (!allowed)
                {
                    NotAllowed(full);
                }
            }
            else if (!full.StartsWith(repo, PathComparison))
            {
                NotAllowed(full);
            }
            else
            {
                string relative = full.Substring(repo.Length);
                bool buildOnlyTarget = relative.StartsWith("tests/", PathComparison) || relative.StartsWith("tools/", PathComparison);
                if (buildOnlyTarget && !BuildOnly)
                {
                    Log.LogError(null, "DOMENT011", null, null, 0, 0, 0, 0,
                        "{0} ships but references build-only project {1}", ProjectPath, full);
                }
            }
        }
        return !Log.HasLoggedErrors;
    }

    private void NotAllowed(string full)
    {
        Log.LogError(null, "DOMENT012", null, null, 0, 0, 0, 0,
            "{0}: project reference {1} is not an allowed darkraise-framework project", ProjectPath, full);
    }

    private static bool Same(string a, string b)
    {
        return string.Equals(a, b, PathComparison);
    }

    private static string Normalize(string path)
    {
        return Path.GetFullPath(path).Replace('\\', '/');
    }

    private static string AsDirectory(string path)
    {
        string full = Normalize(path);
        return full.EndsWith("/", StringComparison.Ordinal) ? full : full + "/";
    }
}

// The parts of obj/project.assets.json the third-party check reads.
// Run by build/gate.sh through build/Gate.proj: the tool manifest and the tracked binaries.
public class DomentGateFiles : Task
{
    [Required]
    public string Tree { get; set; }

    [Required]
    public string RegisterFile { get; set; }

    // Relative to Tree; empty when the tree tracks no tool manifest.
    public string ToolManifest { get; set; }

    // A file of NUL-separated paths relative to Tree.
    public string BinaryList { get; set; }

    public override bool Execute()
    {
        DomentRegister register = DomentRegister.Load(RegisterFile);
        foreach (string problem in register.Problems)
        {
            Log.LogError(null, "DOMENT013", null, null, 0, 0, 0, 0, "{0}: {1}", RegisterFile, problem);
        }

        if (!string.IsNullOrEmpty(ToolManifest))
        {
            var manifest = DomentJson.Parse(File.ReadAllText(Path.Combine(Tree, ToolManifest))) as DomentJson.Obj;
            var tools = manifest == null ? null : manifest.Get("tools") as DomentJson.Obj;
            if (tools != null)
            {
                foreach (KeyValuePair<string, object> tool in tools.Members)
                {
                    if (!register.Tools.Exists(row => row.Matches(tool.Key)))
                    {
                        Log.LogError(null, "DOMENT021", null, null, 0, 0, 0, 0,
                            "{0}: tool {1} is not a build-and-test-only row of {2}", ToolManifest, tool.Key, RegisterFile);
                    }
                }
            }
        }

        if (!string.IsNullOrEmpty(BinaryList) && File.Exists(BinaryList))
        {
            foreach (string file in File.ReadAllText(BinaryList).Split(new[] { '\0' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (!register.Exceptions.Exists(row => row.Matches(file)) && !register.Tools.Exists(row => row.Matches(file)))
                {
                    Log.LogError(null, "DOMENT022", null, null, 0, 0, 0, 0,
                        "{0} is a tracked binary that no row of {1} lists", file, RegisterFile);
                }
            }
        }
        return !Log.HasLoggedErrors;
    }
}

public sealed class DomentAssets
{
    // Package ID to version, in the order of the assets file's libraries.
    public readonly List<KeyValuePair<string, string>> Packages = new List<KeyValuePair<string, string>>();

    private readonly List<string> directPackages = new List<string>();
    private readonly List<string> directProjects = new List<string>();
    private readonly Dictionary<string, List<string>> dependencies =
        new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

    public static DomentAssets Load(string path)
    {
        var assets = new DomentAssets();
        var root = DomentJson.Parse(File.ReadAllText(path)) as DomentJson.Obj;
        if (root == null)
        {
            return assets;
        }
        var packageIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var libraries = root.Get("libraries") as DomentJson.Obj;
        if (libraries != null)
        {
            foreach (KeyValuePair<string, object> library in libraries.Members)
            {
                var body = library.Value as DomentJson.Obj;
                string type = body == null ? null : body.Get("type") as string;
                string id = IdOf(library.Key);
                if (type == "package" && packageIds.Add(id))
                {
                    assets.Packages.Add(new KeyValuePair<string, string>(id, VersionOf(library.Key)));
                }
                else if (type == "project")
                {
                    assets.directProjects.Add(id);
                }
            }
        }
        var project = root.Get("project") as DomentJson.Obj;
        var frameworks = project == null ? null : project.Get("frameworks") as DomentJson.Obj;
        if (frameworks != null)
        {
            foreach (KeyValuePair<string, object> framework in frameworks.Members)
            {
                var body = framework.Value as DomentJson.Obj;
                var direct = body == null ? null : body.Get("dependencies") as DomentJson.Obj;
                if (direct == null)
                {
                    continue;
                }
                foreach (KeyValuePair<string, object> dependency in direct.Members)
                {
                    if (!assets.directPackages.Exists(id => string.Equals(id, dependency.Key, StringComparison.OrdinalIgnoreCase)))
                    {
                        assets.directPackages.Add(dependency.Key);
                    }
                }
            }
        }
        var targets = root.Get("targets") as DomentJson.Obj;
        if (targets != null)
        {
            foreach (KeyValuePair<string, object> target in targets.Members)
            {
                var entries = target.Value as DomentJson.Obj;
                if (entries == null)
                {
                    continue;
                }
                foreach (KeyValuePair<string, object> entry in entries.Members)
                {
                    var body = entry.Value as DomentJson.Obj;
                    var deps = body == null ? null : body.Get("dependencies") as DomentJson.Obj;
                    List<string> list;
                    string id = IdOf(entry.Key);
                    if (!assets.dependencies.TryGetValue(id, out list))
                    {
                        list = new List<string>();
                        assets.dependencies[id] = list;
                    }
                    if (deps != null)
                    {
                        foreach (KeyValuePair<string, object> dep in deps.Members)
                        {
                            list.Add(dep.Key);
                        }
                    }
                }
            }
        }
        return assets;
    }

    // "direct reference", "through <direct package id>" or "through project <project name>":
    // the first direct reference, in the order of the assets file, whose closure holds the package.
    public string HowArrived(string id)
    {
        if (directPackages.Exists(direct => string.Equals(direct, id, StringComparison.OrdinalIgnoreCase)))
        {
            return "direct reference";
        }
        foreach (string direct in directPackages)
        {
            if (Reaches(direct, id))
            {
                return "through " + direct;
            }
        }
        foreach (string directProject in directProjects)
        {
            if (Reaches(directProject, id))
            {
                return "through project " + directProject;
            }
        }
        return "direct reference";
    }

    private bool Reaches(string from, string id)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { from };
        var queue = new Queue<string>();
        queue.Enqueue(from);
        while (queue.Count > 0)
        {
            List<string> next;
            if (!dependencies.TryGetValue(queue.Dequeue(), out next))
            {
                continue;
            }
            foreach (string dependency in next)
            {
                if (string.Equals(dependency, id, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                if (seen.Add(dependency))
                {
                    queue.Enqueue(dependency);
                }
            }
        }
        return false;
    }

    private static string IdOf(string key)
    {
        int slash = key.IndexOf('/');
        return slash < 0 ? key : key.Substring(0, slash);
    }

    private static string VersionOf(string key)
    {
        int slash = key.IndexOf('/');
        return slash < 0 ? "" : key.Substring(slash + 1);
    }
}

// A minimal JSON reader: objects (members kept in file order), arrays, strings, numbers, true, false, null.
public static class DomentJson
{
    public sealed class Obj
    {
        public readonly List<KeyValuePair<string, object>> Members = new List<KeyValuePair<string, object>>();

        public object Get(string name)
        {
            foreach (KeyValuePair<string, object> member in Members)
            {
                if (member.Key == name)
                {
                    return member.Value;
                }
            }
            return null;
        }
    }

    public static object Parse(string text)
    {
        int position = 0;
        object value = ReadValue(text, ref position);
        SkipWhitespace(text, ref position);
        if (position != text.Length)
        {
            throw new FormatException("unexpected text after the JSON value at offset " + position);
        }
        return value;
    }

    private static object ReadValue(string text, ref int position)
    {
        SkipWhitespace(text, ref position);
        if (position >= text.Length)
        {
            throw new FormatException("unexpected end of JSON");
        }
        char c = text[position];
        if (c == '{')
        {
            var obj = new Obj();
            position++;
            SkipWhitespace(text, ref position);
            if (Peek(text, position) == '}')
            {
                position++;
                return obj;
            }
            while (true)
            {
                SkipWhitespace(text, ref position);
                string name = ReadString(text, ref position);
                SkipWhitespace(text, ref position);
                Expect(text, ref position, ':');
                obj.Members.Add(new KeyValuePair<string, object>(name, ReadValue(text, ref position)));
                SkipWhitespace(text, ref position);
                if (Peek(text, position) == ',')
                {
                    position++;
                    continue;
                }
                Expect(text, ref position, '}');
                return obj;
            }
        }
        if (c == '[')
        {
            var list = new List<object>();
            position++;
            SkipWhitespace(text, ref position);
            if (Peek(text, position) == ']')
            {
                position++;
                return list;
            }
            while (true)
            {
                list.Add(ReadValue(text, ref position));
                SkipWhitespace(text, ref position);
                if (Peek(text, position) == ',')
                {
                    position++;
                    continue;
                }
                Expect(text, ref position, ']');
                return list;
            }
        }
        if (c == '"')
        {
            return ReadString(text, ref position);
        }
        if (ReadLiteral(text, ref position, "true"))
        {
            return true;
        }
        if (ReadLiteral(text, ref position, "false"))
        {
            return false;
        }
        if (ReadLiteral(text, ref position, "null"))
        {
            return null;
        }
        int start = position;
        while (position < text.Length && "+-0123456789.eE".IndexOf(text[position]) >= 0)
        {
            position++;
        }
        if (position == start)
        {
            throw new FormatException("unexpected character '" + c + "' at offset " + position);
        }
        return double.Parse(text.Substring(start, position - start), System.Globalization.CultureInfo.InvariantCulture);
    }

    private static string ReadString(string text, ref int position)
    {
        Expect(text, ref position, '"');
        var result = new StringBuilder();
        while (true)
        {
            if (position >= text.Length)
            {
                throw new FormatException("unterminated JSON string");
            }
            char c = text[position++];
            if (c == '"')
            {
                return result.ToString();
            }
            if (c != '\\')
            {
                result.Append(c);
                continue;
            }
            if (position >= text.Length)
            {
                throw new FormatException("unterminated JSON escape");
            }
            char escape = text[position++];
            switch (escape)
            {
                case 'b': result.Append('\b'); break;
                case 'f': result.Append('\f'); break;
                case 'n': result.Append('\n'); break;
                case 'r': result.Append('\r'); break;
                case 't': result.Append('\t'); break;
                case 'u':
                    result.Append((char)Convert.ToInt32(text.Substring(position, 4), 16));
                    position += 4;
                    break;
                default: result.Append(escape); break;
            }
        }
    }

    private static bool ReadLiteral(string text, ref int position, string literal)
    {
        if (string.CompareOrdinal(text, position, literal, 0, literal.Length) == 0)
        {
            position += literal.Length;
            return true;
        }
        return false;
    }

    private static void SkipWhitespace(string text, ref int position)
    {
        while (position < text.Length && char.IsWhiteSpace(text[position]))
        {
            position++;
        }
    }

    private static char Peek(string text, int position)
    {
        return position < text.Length ? text[position] : '\0';
    }

    private static void Expect(string text, ref int position, char expected)
    {
        if (Peek(text, position) != expected)
        {
            throw new FormatException("expected '" + expected + "' at offset " + position);
        }
        position++;
    }
}

public sealed class DomentRegisterRow
{
    public string Id = "";
    public readonly Dictionary<string, string> Cells = new Dictionary<string, string>(StringComparer.Ordinal);

    // Exact package IDs, file paths, or prefixes written as `<prefix>.*`; empty for a `-` cell.
    public readonly List<string> Entries = new List<string>();

    public bool Matches(string candidate)
    {
        foreach (string entry in Entries)
        {
            if (entry.EndsWith(".*", StringComparison.Ordinal))
            {
                string prefix = entry.Substring(0, entry.Length - 1);
                if (candidate.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            else if (string.Equals(entry, candidate, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}

// docs/third-party-exceptions.md: three level-2 headings, each followed by one Markdown table.
public sealed class DomentRegister
{
    public const string ExceptionsTable = "Exceptions";
    public const string ToolsTable = "Build-and-test-only tools";
    public const string PlatformTable = "Platform packages";

    private static readonly string[] ExceptionColumns =
        { "ID", "Component", "Packages or files", "Used for", "Reason", "Licence", "Behind", "Replacement", "Approved" };
    private static readonly string[] ToolColumns =
        { "ID", "Component", "Packages or tool", "Used for", "Licence", "Approved" };
    private static readonly string[] PlatformColumns = { "Package", "Added by", "First seen" };

    public readonly List<string> Problems = new List<string>();
    public readonly List<DomentRegisterRow> Exceptions = new List<DomentRegisterRow>();
    public readonly List<DomentRegisterRow> Tools = new List<DomentRegisterRow>();
    public readonly List<DomentRegisterRow> Platform = new List<DomentRegisterRow>();

    // Every problem is collected in Problems; loading never stops at the first.
    public static DomentRegister Load(string path)
    {
        var register = new DomentRegister();
        string[] lines = File.Exists(path) ? File.ReadAllLines(path) : new string[0];
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        register.ReadTable(lines, ExceptionsTable, ExceptionColumns, "Packages or files", true, ids, register.Exceptions);
        register.ReadTable(lines, ToolsTable, ToolColumns, "Packages or tool", true, ids, register.Tools);
        register.ReadTable(lines, PlatformTable, PlatformColumns, "Package", false, ids, register.Platform);
        return register;
    }

    private void ReadTable(string[] lines, string heading, string[] columns, string packagesColumn,
        bool hasIds, HashSet<string> ids, List<DomentRegisterRow> rows)
    {
        int index = Array.FindIndex(lines, line => line.Trim() == "## " + heading);
        if (index >= 0)
        {
            index++;
            while (index < lines.Length && !lines[index].TrimStart().StartsWith("|", StringComparison.Ordinal)
                && !lines[index].StartsWith("## ", StringComparison.Ordinal))
            {
                index++;
            }
        }
        if (index < 0 || index >= lines.Length || !lines[index].TrimStart().StartsWith("|", StringComparison.Ordinal))
        {
            Problems.Add(string.Format("table '{0}' is missing", heading));
            return;
        }

        List<string> header = SplitRow(lines[index]);
        foreach (string column in columns)
        {
            if (!header.Contains(column))
            {
                Problems.Add(string.Format("table '{0}' has no column '{1}'", heading, column));
            }
        }
        index++;
        if (index < lines.Length && IsSeparator(lines[index]))
        {
            index++;
        }

        for (; index < lines.Length && lines[index].TrimStart().StartsWith("|", StringComparison.Ordinal); index++)
        {
            List<string> cells = SplitRow(lines[index]);
            var row = new DomentRegisterRow();
            for (int i = 0; i < header.Count; i++)
            {
                row.Cells[header[i]] = i < cells.Count ? cells[i] : "";
            }
            string packages;
            if (row.Cells.TryGetValue(packagesColumn, out packages) && packages != "-")
            {
                foreach (string entry in packages.Split(','))
                {
                    string trimmed = entry.Trim().Trim('`').Trim();
                    if (trimmed.Length > 0)
                    {
                        row.Entries.Add(trimmed);
                    }
                }
            }
            if (hasIds)
            {
                string id;
                row.Id = row.Cells.TryGetValue("ID", out id) ? id : "";
                if (row.Id.Length > 0 && !ids.Add(row.Id))
                {
                    Problems.Add(string.Format("duplicate ID {0}", row.Id));
                }
                foreach (string column in columns)
                {
                    string value;
                    if (row.Cells.TryGetValue(column, out value) && value.Length == 0)
                    {
                        Problems.Add(string.Format("row {0}, column '{1}' is empty", row.Id, column));
                    }
                }
            }
            rows.Add(row);
        }
    }

    private static List<string> SplitRow(string line)
    {
        string trimmed = line.Trim();
        if (trimmed.StartsWith("|", StringComparison.Ordinal))
        {
            trimmed = trimmed.Substring(1);
        }
        if (trimmed.EndsWith("|", StringComparison.Ordinal))
        {
            trimmed = trimmed.Substring(0, trimmed.Length - 1);
        }
        var cells = new List<string>();
        foreach (string cell in trimmed.Split('|'))
        {
            cells.Add(cell.Trim());
        }
        return cells;
    }

    private static bool IsSeparator(string line)
    {
        string trimmed = line.Trim();
        return trimmed.Length > 0 && trimmed.Trim('|', '-', ':', ' ').Length == 0 && trimmed.Contains("-");
    }
}
