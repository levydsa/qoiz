
const std = @import("std");
const io = std.io;
const assert = std.debug.assert;
const qoi = @import("qoi");

// test "chunk iterator" {
//     const expected_chunks = [_]qoi.Chunk{
//         .{ .luma = .{ .dg = 1, .dr_dg = 2, .db_dg = 3 } },
//         .{ .rgb = .{ .r = 1,  .g = 2, .b = 3 } },
//         .{ .rgba = .{ .r = 1,  .g = 2, .b = 3, .a = 4 } },
//         .{ .index = .{ .index = 1 } },
//         .{ .run = .{ .run = 1 } },
//         .{ .diff = .{ .dr = 1,  .dg = 2, .db = 3 } },
//     };
// 
//     const bytes = [_]u8{
//         0b10_000001, 0b0010_0011, // luma
//         0b1111_1110, 1, 2, 3,     // rgb
//         0b1111_1111, 1, 2, 3, 4,  // rgba
//         0b00_000001,              // index
//         0b11_000001,              // run
//         0b01_011011,              // diff
//         0,0,0,0,0,0,0,1,          // padding
//     };
// 
//     var buffer = io.fixedBufferStream(&bytes);
//     var source = io.StreamSource{.const_buffer = buffer};
//     var chunks = qoi.ChunkBufferIterator{ .source = &source };
// 
//     for (expected_chunks) |e| {
//         const chunk = (try chunks.next()).?;
//         assert(std.meta.eql(e, chunk));
//     }
// }
test "chunks" {
    const bytes = [_]u8{
        0b00_000001,
        0b01_01_10_11,
        0b10_000001, 0b0010_0011,
        0b11_100000,
        0b11_000001,
        0b1111_1110, 1, 2, 3,
        0b1111_1111, 1, 2, 3, 4,
        0xfe, 0x1d, 0x34, 0x63,
        0,0,0,0,0,0,0,1,
    };

    const expected = [_]qoi.Chunk{
        .{ .index = .{ .index = 1 } },
        .{ .diff = .{ .dr = 1, .dg = 2, .db = 3 } },
        .{ .luma = .{ .dg = 1, .dr_dg = 2, .db_dg = 3 } },
        .{ .run = .{ .run = 32 } },
        .{ .run = .{ .run = 1 } },
        .{ .rgb = .{ .r = 1, .g = 2, .b = 3 } },
        .{ .rgba = .{ .r = 1, .g = 2, .b = 3, .a = 4 } },
    };

    var chunks = qoi.ChunkBufferIterator{
        .buffer = &bytes,
        .pos = 0,
    };

    for (expected) |e| try std.testing.expectEqual(e, chunks.next().?);
}

test "operations" {
    assert(std.meta.eql(
        qoi.diff(
            qoi.Pixel{.r = 10, .g = 10, .b = 10 },
            qoi.Chunk.Diff{.dr = 3, .dg = 2, .db = 1},
        ),
        qoi.Pixel{.r = 11, .g = 10, .b = 9},
    ));
}
