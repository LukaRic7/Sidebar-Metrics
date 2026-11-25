namespace HardwareMonitor.Core.Hardware;

public sealed record HardwareInfo(
    string Name,
    string HardwareType,
    string Identifier,
    string? ParentIdentifier);
