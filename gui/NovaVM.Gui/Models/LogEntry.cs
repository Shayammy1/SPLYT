namespace NovaVM.Gui.Models;

public enum LogLevel
{
    Info,
    Success,
    Warning,
    Error,
}

public sealed class LogEntry
{
    public DateTime Timestamp { get; init; } = DateTime.Now;
    public LogLevel Level { get; init; }
    public required string Source { get; init; }
    public required string Message { get; init; }
    public string? Details { get; init; }

    public string Icon => Level switch
    {
        LogLevel.Success => "✔",   // check
        LogLevel.Warning => "⚠",   // warning triangle
        LogLevel.Error => "✖",     // cross
        _ => "ℹ",                   // info
    };
}
