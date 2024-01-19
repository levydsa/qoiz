const std = @import("std");
const mem = std.mem;
const io = std.io;
const Allocator = mem.Allocator;
const StreamSource = io.StreamSource;

pub const decoder = @import("decoder.zig");
pub const encoder = @import("encoder.zig");

pub const Header = packed struct {
    magic: u32 = mem.bytesToValue(u32, "qoif"),
    width: u32,
    height: u32,
    channels: Channels,
    colorspace: Colorspace,

    const Channels = enum(u8) { rgb = 3, rgba = 4 };
    const Colorspace = enum(u8) { srgb = 0, linear = 1 };
};

pub const Span = struct {
    value: Pixel,
    len: u6 = 1,
};

pub const Chunk = union(enum) {
    rgb: Rgb,
    rgba: Rgba,
    index: Index,
    diff: Diff,
    luma: Luma,
    run: Run,

    pub const Rgb = packed struct { tag: u8 = 0b1111_1110, r: u8, g: u8, b: u8 };
    pub const Rgba = packed struct { tag: u8 = 0b1111_1111, r: u8, g: u8, b: u8, a: u8 };
    pub const Index = packed struct { index: u6, tag: u2 = 0b00 };
    pub const Run = packed struct { run: u6, tag: u2 = 0b11 };

    pub const Luma = packed struct {
        dg: u6,
        tag: u2 = 0b10,
        db_dg: u4,
        dr_dg: u4,

        pub fn apply(self: Luma, p: Pixel) Pixel {
            return .{
                .r = p.r +% self.dg -% 32 +% self.dr_dg -% 8,
                .g = p.g +% self.dg -% 32,
                .b = p.b +% self.dg -% 32 +% self.db_dg -% 8,
                .a = p.a,
            };
        }
    };

    pub const Diff = packed struct {
        db: u2,
        dg: u2,
        dr: u2,
        tag: u2 = 0b01,

        pub fn apply(self: Diff, p: Pixel) Pixel {
            return .{
                .r = p.r +% self.dr -% 2,
                .g = p.g +% self.dg -% 2,
                .b = p.b +% self.db -% 2,
                .a = p.a,
            };
        }
    };
};

pub const Format = enum {
    rgba,
    abgr,
    rgb,
    bgr,

    pub fn pixel(comptime self: Format, p: anytype) Pixel {
        return switch (self) {
            .rgba => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .abgr => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .bgr => .{ .r = p.r, .g = p.g, .b = p.b },
            .rgb => .{ .r = p.r, .g = p.g, .b = p.b },
        };
    }

    pub fn format(comptime self: Format, p: Pixel) self.Type() {
        return switch (self) {
            .rgba => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .abgr => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .bgr => .{ .r = p.r, .g = p.g, .b = p.b },
            .rgb => .{ .r = p.r, .g = p.g, .b = p.b },
        };
    }

    pub fn Type(comptime self: Format) type {
        return switch (self) {
            .rgba => packed struct { r: u8, g: u8, b: u8, a: u8 },
            .abgr => packed struct { a: u8, b: u8, g: u8, r: u8 },
            .rgb => packed struct { r: u8, b: u8, g: u8 },
            .bgr => packed struct { b: u8, g: u8, r: u8 },
        };
    }
};

pub const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0xff,

    pub fn dot(a: @Vector(4, u8), b: @Vector(4, u8)) u8 {
        return @reduce(.Add, a *% b);
    }

    pub fn vector(self: Pixel) @Vector(4, u8) {
        return @bitCast(self);
    }

    inline fn fits(comptime T: type, mid: anytype) bool {
        return std.math.minInt(T) <= mid and mid <= std.math.maxInt(T);
    }

    pub fn luma(self: Pixel, p: Pixel) ?Chunk.Luma {
        if (self.a != p.a) return null;

        const dr: i8 = @bitCast(self.r -% p.r);
        const dg: i8 = @bitCast(self.g -% p.g);
        const db: i8 = @bitCast(self.b -% p.b);

        const dr_dg: i8 = dr -% dg;
        const db_dg: i8 = db -% dg;

        return if (fits(i6, dg) and fits(i4, dr_dg) and fits(i4, db_dg)) Chunk.Luma{
            .dg = @truncate(@as(u8, @bitCast(dg +% 32))),
            .db_dg = @truncate(@as(u8, @bitCast(db_dg +% 8))),
            .dr_dg = @truncate(@as(u8, @bitCast(dr_dg +% 8))),
        } else null;
    }

    pub fn diff(self: Pixel, p: Pixel) ?Chunk.Diff {
        if (self.a != p.a) return null;

        const dr: i8 = @bitCast(self.r -% p.r);
        const dg: i8 = @bitCast(self.g -% p.g);
        const db: i8 = @bitCast(self.b -% p.b);

        return if (fits(i2, dr) and fits(i2, dg) and fits(i2, db)) Chunk.Diff{
            .dr = @truncate(@as(u8, @bitCast(dr +% 2))),
            .dg = @truncate(@as(u8, @bitCast(dg +% 2))),
            .db = @truncate(@as(u8, @bitCast(db +% 2))),
        } else null;
    }

    pub fn hash(self: Pixel) u6 {
        return @truncate(dot(self.vector(), .{ 3, 5, 7, 11 }));
    }
};

pub fn Image(comptime format: Format) type {
    return struct {
        width: u32,
        height: u32,
        allocator: Allocator,
        pixels: []format.Type(),

        const Self = @This();

        pub fn init(allocator: Allocator, source: []const u8) !Self {
            var spans = try decoder.SpanIterator.init(source);

            var pixels = try allocator.alloc(format.Type(), spans.width * spans.height);
            var pos: usize = 0;

            while (try spans.next()) |span| : (pos += span.len) {
                for (0..span.len) |i| {
                    pixels[pos..][i] = format.format(span.value);
                }
            }

            return .{
                .pixels = pixels,
                .width = spans.width,
                .height = spans.height,
                .allocator = allocator,
            };
        }

        pub fn flipY(self: *Self) void {
            for (self.pixels[0 .. (self.width * self.height) / 2], 0..) |*a, i| {
                mem.swap(format.Type(), a, &self.pixels[(self.height - (i / self.width) - 1) * self.width + i % self.width]);
            }
        }

        pub fn encode(self: *const Self, allocator: Allocator) ![]u8 {
            var chunks = std.ArrayList(u8).init(allocator);
            var iter = encoder.ChunkIterator(format){
                .pixels = self.pixels,
            };

            try chunks.writer().writeStruct(Header{
                .width = self.width,
                .height = self.height,
                .colorspace = .linear,
                .channels = .rgba,
            });

            while (iter.next()) |chunk| {
                switch (chunk) {
                    inline else => |v| try chunks.writer().writeStruct(v),
                }
            }

            try chunks.writer().writeAll(&.{ 0, 0, 0, 0, 0, 0, 0, 1 });

            return chunks.toOwnedSlice();
        }

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.pixels);
        }
    };
}
