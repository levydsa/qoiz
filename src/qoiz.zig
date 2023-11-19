const std = @import("std");
const mem = std.mem;
const io = std.io;
const Allocator = mem.Allocator;
const StreamSource = io.StreamSource;

pub const Header = packed struct {
    magic: u32,
    width: u32,
    height: u32,
    channels: Channels,
    colorspace: Colorspace,

    const Channels = enum(u8) { rgb = 3, rgba = 4 };
    const Colorspace = enum(u8) { srgb = 0, linear = 1 };
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
                .a = p.a
            };
        }
    };
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
                .a = p.a
            };
        }
    };
};


pub const Format = enum {
    rgba,
    abgr,
    rgb,
    bgr,

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

    pub fn from(comptime format: Format, p: anytype) Pixel {
        return switch (format) {
            .rgba => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .abgr => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
            .bgr => .{ .r = p.r, .g = p.g, .b = p.b },
            .rgb => .{ .r = p.r, .g = p.g, .b = p.b },
        };
    }

    inline fn fits(comptime T: type, mid: anytype) bool {
        return std.math.minInt(T) <= mid and mid <= std.math.maxInt(T);
    }

    pub fn luma(self: Pixel, p: Pixel) ?Chunk.Luma {
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
        const dr: i8 = @bitCast(self.r -% p.r);
        const dg: i8 = @bitCast(self.g -% p.g);
        const db: i8 = @bitCast(self.b -% p.b);

        return if (fits(i2, dr) and fits(i2, dr) and fits(i2, db)) Chunk.Diff{
            .dr = @truncate(@as(u8, @bitCast(dr +% 2))),
            .dg = @truncate(@as(u8, @bitCast(dg +% 2))),
            .db = @truncate(@as(u8, @bitCast(db +% 2))),
        } else null;
    }

    pub fn hash(self: Pixel) u6 {
        return @truncate(dot(self.vector(), .{ 3, 5, 7, 11 }));
    }
};

const Span = struct { value: Pixel, len: u6 = 1 };

pub const ChunkIterator = struct {
    buffer: []const u8,
    pos: usize = 0,

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
    width: u32,
    height: u32,

    pub fn init(source: []const u8) !SpanIterator {
        var header: Header = @bitCast(source[0..14].*);

        if (header.magic != mem.bytesToValue(u32, "qoif"))
            return error.InvalidMagic;

        header.width = mem.toNative(u32, header.width, .big);
        header.height = mem.toNative(u32, header.height, .big);

        return .{
            .chunks = ChunkIterator{
                .buffer = source,
                .pos = 14,
            },
            .width = header.width,
            .height = header.height,
            .pixel_count = header.width * header.height,
        };
    }

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

// pub fn Chunks(comptime format: Format) type {
//     return struct {
//         spans: Spans(format),
//         seen: [64]Pixel = mem.zeroes([64]Pixel),
//         previous: Pixel = .{ .r = 0, .g = 0, .b = 0 },
// 
//         const Self = @This();
// 
//         pub fn next(self: *Self) ?Chunk {
//             const span = self.spans.next() orelse return null;
// 
//             if (span.len > 1) return .{ .run = .{ .run = span.len - 1 } };
// 
//             const current = span.value;
//             const index = current.hash();
// 
//             defer self.previous = current;
//             defer self.seen[index] = current;
// 
//             if (false) debug(.{
//                 .i = self.spans.pos,
//                 .current = current,
//                 .previous = self.previous,
//             });
// 
//             if (std.meta.eql(current, self.seen[index]))
//                 return .{ .index = .{ .index = index } };
// 
//             if (current.diff(self.previous)) |diff| return .{ .diff = diff };
//             if (current.luma(self.previous)) |luma| return .{ .luma = luma };
// 
//             if (current.a == self.previous.a) return .{ .rgb = .{
//                 .r = current.r,
//                 .g = current.g,
//                 .b = current.b,
//             } };
// 
//             return .{ .rgba = .{
//                 .r = current.r,
//                 .g = current.g,
//                 .b = current.b,
//                 .a = current.a,
//             } };
//         }
//     };
// }
// 
// pub fn Spans(comptime format: Format) type {
//     return struct {
//         pixels: []const format.Type(),
//         pos: usize = 0,
// 
//         const Self = @This();
// 
//         pub fn next(self: *Self) ?Span {
//             if (self.pos == self.pixels.len) return null;
//             const current = Pixel.from(format, self.pixels[self.pos]);
// 
//             for (self.pixels[self.pos + 1 ..], 1..) |pixel, len| {
//                 if (std.meta.eql(current, Pixel.from(format, pixel)) or
//                     len == 62 or
//                     self.pos + 1 + len == self.pixels.len)
//                 {
//                     self.pos += len;
//                     return .{ .value = current, .len = @intCast(len) };
//                 }
//             }
// 
//             self.pos += 1;
//             return .{ .value = current };
//         }
//     };
// }
//
// fn debug(args: anytype) void {
//     inline for (@typeInfo(@TypeOf(args)).Struct.fields) |field| {
//         std.debug.print("{s}: {s} = {any}\n", .{
//             field.name,
//             @typeName(field.type),
//             @field(args, field.name),
//         });
//     }
// }

pub fn Image(comptime format: Format) type {
    return struct {
        width: u32,
        height: u32,
        allocator: Allocator,
        pixels: []format.Type(),

        const Self = @This();

        pub fn convert(p: Pixel) format.Type() {
            return switch (format) {
                .rgba => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
                .abgr => .{ .r = p.r, .g = p.g, .b = p.b, .a = p.a },
                .rgb => .{ .r = p.r, .g = p.g, .b = p.b },
                .bgr => .{ .r = p.r, .g = p.g, .b = p.b },
            };
        }

        pub fn init(allocator: Allocator, source: []const u8) !Self {
            var spans = try SpanIterator.init(source);

            var pixels = try allocator.alloc(format.Type(), spans.width * spans.height);
            var pos: usize = 0;

            while (try spans.next()) |span| : (pos += span.len) {
                for (0..span.len) |i| pixels[pos..][i] = convert(span.value);
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

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.pixels);
        }
    };
}
