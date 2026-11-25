namespace HardwareMonitor.Core.Sensors;

public sealed record SensorReading(
    string Id,
    string Name,
    string Type,
    double? Value,
    double? Min,
    double? Max,
    DateTimeOffset Timestamp,
    bool IsAvailable,
    bool IsActive);
