using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using HardwareMonitor.Service.Models;

namespace HardwareMonitor.Service.IPC;

public sealed class PipeClientHandler
{
    private readonly NamedPipeServerStream _pipe;
    private readonly RequestQueue _queue;
    private readonly Action<string>? _log;
    private readonly int _maxClientTimeoutMs;

    public PipeClientHandler(
        NamedPipeServerStream pipe,
        RequestQueue queue,
        Action<string>? log = null,
        int maxClientTimeoutMs = 5_000)
    {
        _pipe = pipe;
        _queue = queue;
        _log = log;
        _maxClientTimeoutMs = maxClientTimeoutMs;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        try
        {
            await _pipe.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
            while (!cancellationToken.IsCancellationRequested)
            {
                byte[]? payload;
                try
                {
                    payload = await MessageProtocol.ReadMessageAsync(_pipe, cancellationToken).ConfigureAwait(false);
                }
                catch (EndOfStreamException)
                {
                    break;
                }
                catch (InvalidDataException ex)
                {
                    await WriteMalformedAsync(null, ex.Message, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                if (payload is null) break;
                string json = Encoding.UTF8.GetString(payload);
                var queued = new QueuedRequest(json, this);
                if (!_queue.TryEnqueue(queued))
                {
                    await WriteJsonAsync(
                        Response.Fail(null, "QUEUE_FULL", "The request queue is full."),
                        cancellationToken).ConfigureAwait(false);
                    continue;
                }

                try
                {
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    timeout.CancelAfter(_maxClientTimeoutMs);
                    object result = await queued.Completion.WaitAsync(timeout.Token).ConfigureAwait(false);
                    await WriteJsonAsync((Response)result, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    await WriteMalformedAsync(null, ex.Message, cancellationToken).ConfigureAwait(false);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException ex)
        {
            _log?.Invoke("Named pipe client disconnected: " + ex.Message);
        }
        catch (Exception ex)
        {
            _log?.Invoke("Named pipe client error: " + ex.Message);
        }
        finally
        {
            try { await _pipe.DisposeAsync().ConfigureAwait(false); } catch { }
        }
    }

    private async Task WriteMalformedAsync(
        string? requestId,
        string message,
        CancellationToken cancellationToken)
    {
        await WriteJsonAsync(
            Response.Fail(requestId, "MALFORMED_REQUEST", message),
            cancellationToken).ConfigureAwait(false);
    }

    public async Task WriteJsonAsync(
        Response response,
        CancellationToken cancellationToken)
    {
        byte[] payload = JsonSerializer.SerializeToUtf8Bytes(
            response,
            new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        await MessageProtocol.WriteMessageAsync(_pipe, payload, cancellationToken).ConfigureAwait(false);
    }
}
