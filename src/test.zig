const std = @import("std");
const testing = std.testing;
const io = std.io;
const assert = std.debug.assert;
const qoi = @import("qoiz.zig");

test "chunks" {
    // zig fmt: off
    const bytes = [_]u8{
        0b00_000001,
        0b01_01_10_11,
        0b10_000001, 0b0010_0011,
        0b11_100000,
        0b11_000001,
        0b1111_1110, 1, 2, 3,
        0b1111_1111, 1, 2, 3, 4,
        0xfe, 0x1d, 0x34, 0x63,
        0, 0, 0, 0, 0, 0, 0, 1,
    };
    // zig fmt: on

    const expected = [_]qoi.Chunk{
        .{ .index = .{ .index = 1 } },
        .{ .diff = .{ .dr = 1, .dg = 2, .db = 3 } },
        .{ .luma = .{ .dg = 1, .dr_dg = 2, .db_dg = 3 } },
        .{ .run = .{ .run = 32 } },
        .{ .run = .{ .run = 1 } },
        .{ .rgb = .{ .r = 1, .g = 2, .b = 3 } },
        .{ .rgba = .{ .r = 1, .g = 2, .b = 3, .a = 4 } },
    };

    var chunks = qoi.decoder.ChunkIterator{
        .buffer = &bytes,
        .pos = 0,
    };

    for (expected) |e| try std.testing.expectEqual(e, chunks.next().?);
}

test "encoder" {
    if (false) return error.SkipZigTest;

    const source: []const u8 = @embedFile("bench/data/dice.qoi");

    const image = try qoi.Image(.rgba).init(testing.allocator, source);
    defer image.deinit();

    var dec_chunk_iter = qoi.decoder.ChunkIterator{
        .buffer = source[14..],
    };

    var chunk_iter = qoi.encoder.ChunkIterator(.rgba){
        .pixels = image.pixels,
    };

    const encoded = try image.encode(testing.allocator);
    defer testing.allocator.free(encoded);

    std.debug.print("{any}", .{ encoded });

    while (chunk_iter.next()) |chunk| {
        const dec_chunk = dec_chunk_iter.next().?;
        std.testing.expectEqual(dec_chunk, chunk) catch |err| {
            std.debug.print(
                \\ {x}: {}
                \\ {x}: {}
                \\
                , .{ chunk_iter.pos, chunk, dec_chunk_iter.pos, dec_chunk });
            return err;
        };
        std.debug.print(
            \\ {x}: {}
            \\ {x}: {}
            \\
            , .{ chunk_iter.pos, chunk, dec_chunk_iter.pos, dec_chunk });
    }
}

test "operations" {
    assert(std.meta.eql(
        (qoi.Chunk.Diff{ .dr = 3, .dg = 2, .db = 1 }).apply(
            qoi.Pixel{ .r = 10, .g = 10, .b = 10 },
        ),
        qoi.Pixel{ .r = 11, .g = 10, .b = 9 },
    ));

    const p1 = qoi.Pixel{ .r = 206, .g = 236, .b = 206, .a = 27 };
    const p2 = qoi.Pixel{ .r = 206, .g = 241, .b = 206, .a = 27 };

    try testing.expectEqual(qoi.Chunk.Luma{ .dg = 37, .db_dg = 3, .dr_dg = 3 }, p2.luma(p1).?);
    try testing.expectEqual(@as(?qoi.Chunk.Diff, null), p2.diff(p1));
}
