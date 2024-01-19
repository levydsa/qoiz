const std = @import("std");
const qoi = @import("qoiz.zig");

const Pixel = qoi.Pixel;
const Chunk = qoi.Chunk;
const Header = qoi.Chunk;
const Span = qoi.Span;
const Format = qoi.Format;

const mem = std.mem;

pub fn ChunkIterator(comptime format: Format) type {
    return struct {
        pixels: []const format.Type(),
        pos: usize = 0,

        seen: [64]Pixel = mem.zeroes([64]Pixel),
        previous: Pixel = .{ .r = 0, .g = 0, .b = 0 },

        const Self = @This();

        pub fn next(self: *Self) ?Chunk {
            if (self.pos >= self.pixels.len) return null;

            var run: usize = 0;
            while (run + self.pos < self.pixels.len and run < 62) : (run += 1) {
                const pixel = format.pixel(self.pixels[self.pos + run]);

                if (!std.meta.eql(pixel, self.previous)) break;
            }

            if (run > 0) {
                self.pos += run;
                // NOTE: -1 bias
                return .{ .run = .{ .run = @intCast(run - 1) } };
            }

            const current = format.pixel(self.pixels[self.pos]);
            self.pos += 1;

            const index = current.hash();

            defer self.previous = current;
            defer self.seen[index] = current;

            if (std.meta.eql(current, self.seen[index])) return .{
                .index = .{ .index = index },
            };

            if (current.diff(self.previous)) |diff| return .{ .diff = diff };
            if (current.luma(self.previous)) |luma| return .{ .luma = luma };

            if (current.a == self.previous.a) return .{
                .rgb = .{
                    .r = current.r,
                    .g = current.g,
                    .b = current.b,
                },
            };

            return .{
                .rgba = .{
                    .r = current.r,
                    .g = current.g,
                    .b = current.b,
                    .a = current.a,
                },
            };
        }
    };
}
