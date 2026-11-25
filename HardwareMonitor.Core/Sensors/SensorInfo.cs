namespace HardwareMonitor.Core.Sensors;

public sealed record SensorInfo(
    string Id,
    string Name,
    string SensorType,
    string HardwareName,
    string HardwareType,
    string ParentIdentifier,
    string Identifier,
    bool IsActive,
    bool IsAvailable,
    double? Value,
    double? Min,
    double? Max);
