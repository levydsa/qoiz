const qoi = @import("qoiz.zig");
const std = @import("std");

const Pixel = qoi.Pixel;
const Chunk = qoi.Chunk;
const Header = qoi.Header;
const Span = qoi.Span;

const mem = std.mem;

pub const ChunkIterator = struct {
    buffer: []const u8,
    pos: usize = 0,

    /// Get next chunk from raw image.
    pub fn next(self: *ChunkIterator) ?Chunk {
        if (self.buffer.len - self.pos == 8) return null;

        const bytes = self.buffer[self.pos..][0..5];
        const info: packed struct { rest: u6, tag: u2 } = @bitCast(bytes[0]);

        const chunk: Chunk, const size: usize = switch (info.tag) {
            0b00 => .{ .{ .index = @bitCast(bytes[0]) }, 1 },
            0b01 => .{ .{ .diff = @bitCast(bytes[0]) }, 1 },
            0b10 => .{ .{ .luma = @bitCast(bytes[0..2].*) }, 2 },
            0b11 => switch (info.rest) {
                0b11_1110 => .{ .{ .rgb = @bitCast(bytes[0..4].*) }, 4 },
                0b11_1111 => .{ .{ .rgba = @bitCast(bytes.*) }, 5 },
                else => .{ .{ .run = @bitCast(bytes[0]) }, 1 },
            },
        };

        self.pos += size;
        return chunk;
    }
};

pub const SpanIterator = struct {
    chunks: ChunkIterator,
    seen: [64]Pixel = mem.zeroes([64]Pixel),
    previous: Pixel = .{ .r = 0, .g = 0, .b = 0 },
    pixel_count: usize,
    header: Header,

    /// Extract QOI header and iterate over the span of pixels
    pub fn init(source: []const u8) Header.Error!SpanIterator {
        const header = try Header.fromBytes(source[0..14].*);

        return .{
            .chunks = ChunkIterator{
                .buffer = source,
                .pos = 14,
            },
            .pixel_count = header.width * header.height,
            .header = header,
        };
    }

    /// Get next span of pixels
    pub fn next(self: *SpanIterator) !?Span {
        const chunk = self.chunks.next() orelse {
            std.debug.assert(mem.eql(
                u8,
                self.chunks.buffer[self.chunks.pos..][0..8],
                &.{ 0, 0, 0, 0, 0, 0, 0, 1 },
            ));
            return if (self.pixel_count > 0) error.MissingChunks else null;
        };

        const span: Span = switch (chunk) {
            .rgb => |p| .{ .value = .{ .r = p.r, .g = p.g, .b = p.b, .a = self.previous.a } },
            .rgba => |p| .{ .value = .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a } },
            .index => |index| .{ .value = self.seen[index.index] },
            .luma => |luma| .{ .value = luma.apply(self.previous) },
            .diff => |diff| .{ .value = diff.apply(self.previous) },
            .run => |run| .{ .value = self.previous, .len = run.run + 1 },
        };

        self.seen[span.value.hash()] = span.value;
        self.previous = span.value;
        self.pixel_count -= span.len;
        return span;
    }
};
