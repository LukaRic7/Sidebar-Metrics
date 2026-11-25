using System.Text.Json.Serialization;

namespace HardwareMonitor.Service.Models;

public sealed class Response
{
    [JsonPropertyName("requestId")]
    public string? RequestId { get; set; }
    [JsonPropertyName("success")]
    public bool Success { get; set; }
    [JsonPropertyName("data")]
    public object? Data { get; set; }
    [JsonPropertyName("error")]
    public object? Error { get; set; }

    public static Response Ok(string? requestId, object? data) =>
        new() { RequestId = requestId, Success = true, Data = data, Error = null };

    public static Response Fail(string? requestId, string code, string message) =>
        new()
        {
            RequestId = requestId,
            Success = false,
            Data = null,
            Error = new { code, message }
        };
}
