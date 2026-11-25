using System.Text.Json.Serialization;

namespace HardwareMonitor.Core.Configuration;

public sealed class HardwareConfiguration
{
    public int PollingIntervalMilliseconds { get; set; } = 1000;
    public List<string> ActiveSensorIds { get; set; } = new();

    [JsonIgnore]
    public static int MinimumPollingIntervalMilliseconds => 100;

    [JsonIgnore]
    public static int MaximumPollingIntervalMilliseconds => 60_000;
}
