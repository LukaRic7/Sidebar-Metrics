using System.Text.Json;

namespace HardwareMonitor.Core.Configuration;

public sealed class ConfigurationManager
{
    private static readonly JsonSerializerOptions ReadOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly JsonSerializerOptions WriteOptions = new() { WriteIndented = true };
    private readonly object _gate = new();
    private readonly string _directory;
    private readonly string _file;
    private HardwareConfiguration _configuration;

    public ConfigurationManager(string? directory = null)
    {
        _directory = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "HardwareMonitor");
        _file = Path.Combine(_directory, "config.json");
        _configuration = Load();
    }

    public HardwareConfiguration Snapshot()
    {
        lock (_gate)
        {
            return new HardwareConfiguration
            {
                PollingIntervalMilliseconds = _configuration.PollingIntervalMilliseconds,
                ActiveSensorIds = new List<string>(_configuration.ActiveSensorIds)
            };
        }
    }

    public void Update(Action<HardwareConfiguration> update)
    {
        lock (_gate)
        {
            update(_configuration);
            SaveLocked();
        }
    }

    private HardwareConfiguration Load()
    {
        try
        {
            Directory.CreateDirectory(_directory);
            if (!File.Exists(_file))
                return GetDefaults();

            string json = File.ReadAllText(_file);
            HardwareConfiguration? loaded = JsonSerializer.Deserialize<HardwareConfiguration>(json, ReadOptions);
            if (loaded is null)
                return GetDefaults();

            loaded.PollingIntervalMilliseconds = Math.Clamp(
                loaded.PollingIntervalMilliseconds,
                HardwareConfiguration.MinimumPollingIntervalMilliseconds,
                HardwareConfiguration.MaximumPollingIntervalMilliseconds);
            loaded.ActiveSensorIds ??= new List<string>();
            return loaded;
        }
        catch (Exception)
        {
            return GetDefaults();
        }
    }

    private static HardwareConfiguration GetDefaults()
    {
        return new HardwareConfiguration
        {
            PollingIntervalMilliseconds = 1000
        };
    }

    private void SaveLocked()
    {
        Directory.CreateDirectory(_directory);
        string temporary = _file + ".tmp-" + Environment.ProcessId.ToString();
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(_configuration, WriteOptions));
            File.Move(temporary, _file, overwrite: true);
        }
        catch
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            throw;
        }
    }
}
