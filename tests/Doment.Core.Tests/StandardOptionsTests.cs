namespace Doment.Core.Tests;

public sealed class StandardOptionsTests
{
    private const string Usage = "usage: doment [--version | --help]\n";

    [Fact]
    public void Run_Version_PrintsNameAndVersion()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        int code = StandardOptions.Run("doment", ["--version"], stdout, stderr);

        Assert.Equal(0, code);
        Assert.Matches(@"^doment 0\.1\.0([+-].*)?\n$", stdout.ToString());
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public void Run_Help_PrintsUsageToStdout()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        int code = StandardOptions.Run("doment", ["--help"], stdout, stderr);

        Assert.Equal(0, code);
        Assert.Equal(Usage, stdout.ToString());
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Theory]
    [InlineData]
    [InlineData("--bogus")]
    [InlineData("--version", "x")]
    public void Run_OtherArguments_PrintUsageToStderr(params string[] args)
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        int code = StandardOptions.Run("doment", args, stdout, stderr);

        Assert.Equal(2, code);
        Assert.Equal(Usage, stderr.ToString());
        Assert.Equal(string.Empty, stdout.ToString());
    }
}
