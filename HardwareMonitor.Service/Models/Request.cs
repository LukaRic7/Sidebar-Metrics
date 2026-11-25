using System.Text.Json;
using System.Text.Json.Serialization;

namespace HardwareMonitor.Service.Models;

public sealed class Request
{
    [JsonPropertyName("requestId")]
    public string? RequestId { get; set; }

    [JsonPropertyName("command")]
    public string? Command { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? Arguments { get; set; }
}
