using System.Buffers.Binary;
using System.Text;
using System.Text.Json;

namespace HardwareMonitor.Service.IPC;

public static class MessageProtocol
{
    public const int MaximumRequestSize = 256 * 1024;
    public const int MaximumResponseSize = 4 * 1024 * 1024;

    public static async Task<byte[]?> ReadMessageAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        byte[] header = new byte[4];
        int read = await ReadExactlyAsync(stream, header, cancellationToken).ConfigureAwait(false);
        if (read == 0) return null;
        if (read != 4) throw new InvalidDataException("Incomplete length header.");

        int length = BinaryPrimitives.ReadInt32BigEndian(header);
        if (length <= 0 || length > MaximumRequestSize)
            throw new InvalidDataException($"Invalid request length: {length}.");

        byte[] payload = new byte[length];
        int payloadRead = await ReadExactlyAsync(stream, payload, cancellationToken).ConfigureAwait(false);
        if (payloadRead != payload.Length)
            throw new InvalidDataException("Incomplete request payload.");
        return payload;
    }

    public static async Task WriteMessageAsync(
        Stream stream,
        byte[] payload,
        CancellationToken cancellationToken)
    {
        if (payload.Length > MaximumResponseSize)
            throw new InvalidOperationException("Response exceeds the maximum response size.");

        byte[] header = new byte[4];
        BinaryPrimitives.WriteInt32BigEndian(header, payload.Length);
        await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
        await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
        await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task<int> ReadExactlyAsync(
        Stream stream,
        byte[] buffer,
        CancellationToken cancellationToken)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int count = await stream.ReadAsync(
                buffer.AsMemory(offset, buffer.Length - offset),
                cancellationToken).ConfigureAwait(false);
            if (count == 0)
                return offset == 0 ? 0 : offset;
            offset += count;
        }
        return offset;
    }
}
