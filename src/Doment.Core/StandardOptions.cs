using System.Reflection;

namespace Doment.Core;

public static class StandardOptions
{
    public static string ProductVersion { get; } =
        typeof(StandardOptions).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
        ?? string.Empty;

    // Lines end in "\n" on every platform, so the output does not depend on Environment.NewLine.
    public static int Run(string name, IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(stdout);
        ArgumentNullException.ThrowIfNull(stderr);

        string usage = "usage: " + name + " [--version | --help]\n";
        if (args.Count == 1 && args[0] == "--version")
        {
            stdout.Write(name + " " + ProductVersion + "\n");
            return 0;
        }

        if (args.Count == 1 && args[0] == "--help")
        {
            stdout.Write(usage);
            return 0;
        }

        stderr.Write(usage);
        return 2;
    }
}
