namespace HardwareMonitor.Service.Logging;

public sealed class BoundedLogger : IDisposable
{
    private readonly object _gate = new();
    private readonly string _directory;
    private readonly string _file;
    private readonly long _maximumBytes;
    private readonly int _maximumFiles;

    public BoundedLogger(string? directory = null)
    {
        _directory = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "HardwareMonitor",
            "logs");
        _file = Path.Combine(_directory, "hardware-monitor.log");
        _maximumBytes = 5 * 1024 * 1024;
        _maximumFiles = 3;
        Directory.CreateDirectory(_directory);
    }

    public void Info(string message) => Write("INFO", message);
    public void Error(string message) => Write("ERROR", message);

    private void Write(string level, string message)
    {
        lock (_gate)
        {
            try
            {
                RotateIfNeeded();
                string line = $"{DateTimeOffset.UtcNow:O} [{level}] {message.Replace("\r", " ").Replace("\n", " ")}";
                File.AppendAllText(_file, line + Environment.NewLine);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Logging failure: {ex.Message}");
            }
        }
    }

    private void RotateIfNeeded()
    {
        if (!File.Exists(_file)) return;
        FileInfo file = new(_file);
        if (file.Length < _maximumBytes) return;

        for (int i = _maximumFiles - 1; i >= 1; i--)
        {
            string source = _file + "." + i;
            string destination = _file + "." + (i + 1);
            if (File.Exists(source))
            {
                if (File.Exists(destination)) File.Delete(destination);
                File.Move(source, destination);
            }
        }

        string first = _file + ".1";
        if (File.Exists(first)) File.Delete(first);
        File.Move(_file, first);
    }

    public void Dispose()
    {
    }
}
