const std = @import("std");

const mem = std.mem;
const io = std.io;
const fs = std.fs;
const testing = std.testing;

const assert = std.debug.assert;

const Allocator = mem.Allocator;
const StreamSource = io.StreamSource;

pub const decoder = @import("decoder.zig");
pub const encoder = @import("encoder.zig");

pub const Header = extern struct {
    magic: [4]u8 align(1) = "qoif".*,
    width: u32 align(1),
    height: u32 align(1),
    channels: Channels = .rgba,
    colorspace: Colorspace = .linear,

    pub const Channels = enum(u8) { rgb = 3, rgba = 4 };
    pub const Colorspace = enum(u8) { srgb = 0, linear = 1 };

    pub const Error = error{
        InvalidMagic,
        InvalidChannel,
        InvalidColorspace,
    } || error{EndOfStream};

    comptime {
        assert(@sizeOf(Header) == 14);
    }

    pub fn encode(self: Header) [@sizeOf(Header)]u8 {
        var out = self;

        out.width = mem.nativeTo(u32, self.width, .big);
        out.height = mem.nativeTo(u32, self.height, .big);

        return mem.toBytes(out);
    }

    pub fn fromBytes(bytes: [@sizeOf(Header)]u8) Error!Header {
        var stream = io.fixedBufferStream(&bytes);
        var reader = stream.reader();

        if (!try reader.isBytes("qoif")) return error.InvalidMagic;

        const width = try reader.readInt(u32, .big);
        const height = try reader.readInt(u32, .big);

        const channels = std.meta.intToEnum(Channels, try reader.readByte()) catch {
            return error.InvalidChannel;
        };

        const colorspace = std.meta.intToEnum(Colorspace, try reader.readByte()) catch {
            return error.InvalidColorspace;
        };

        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .colorspace = colorspace,
        };
    }
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

    comptime {
        assert(@bitSizeOf(Rgb) == 8 * 4);
        assert(@bitSizeOf(Rgba) == 8 * 5);
        assert(@bitSizeOf(Index) == 8 * 1);
        assert(@bitSizeOf(Run) == 8 * 1);
        assert(@bitSizeOf(Luma) == 8 * 2);
        assert(@bitSizeOf(Diff) == 8 * 1);
    }

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
        return @truncate(
            self.r *% 3 +%
            self.g *% 5 +%
            self.b *% 7 +%
            self.a *% 11
        );
    }
};

pub fn Image(comptime format: Format) type {
    return struct {
        allocator: Allocator,
        pixels: []format.Type(),
        width: u32,
        height: u32,

        header: Header,

        const Self = @This();

        pub fn initReader(allocator: Allocator, reader: anytype) !Self {
            const source = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
            defer allocator.free(source);

            return Self.init(allocator, source);
        }

        pub fn init(allocator: Allocator, source: []const u8) !Self {
            var spans = try decoder.SpanIterator.init(source);

            const width = spans.header.width;
            const height = spans.header.height;

            var pixels = try allocator.alloc(format.Type(), width * height);
            var pos: usize = 0;

            while (try spans.next()) |span| : (pos += span.len) {
                for (0..span.len) |i| {
                    pixels[pos..][i] = format.format(span.value);
                }
            }

            return .{
                .allocator = allocator,
                .pixels = pixels,
                .width = width,
                .height = height,
                .header = spans.header,
            };
        }

        pub fn flipY(self: *Self) void {
            for (self.pixels[0 .. (self.width * self.height) / 2], 0..) |*a, i| {
                mem.swap(format.Type(), a, &self.pixels[(self.height - (i / self.width) - 1) * self.width + i % self.width]);
            }
        }

        pub fn encode(self: *const Self, allocator: Allocator) ![]u8 {
            var out = std.ArrayList(u8).init(allocator);
            var writer = out.writer();

            try writer.writeAll(&self.header.encode());

            var chunks = encoder.ChunkIterator(format){
                .pixels = self.pixels,
            };

            while (chunks.next()) |chunk| {
                switch (chunk) {
                    inline else => |v| {
                        const size = @divExact(@bitSizeOf(@TypeOf(v)), 8);
                        const bytes = mem.toBytes(v)[0..size];
                        try writer.writeAll(bytes);
                    },
                }
            }

            try writer.writeAll(&.{ 0, 0, 0, 0, 0, 0, 0, 1 });

            return out.toOwnedSlice();
        }

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.pixels);
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}

test "image init reader" {
    const file = try fs.cwd().openFile("src/bench/data/dice.qoi", .{});
    defer file.close();

    const image = try Image(.rgb).initReader(testing.allocator, file.reader());
    defer image.deinit();
}

test "chunk iterator encoder and decoder" {
    const source = @embedFile("bench/data/dice.qoi");

    const image = try Image(.rgba).init(testing.allocator, source);
    defer image.deinit();

    const encoded: []u8 = try image.encode(testing.allocator);
    defer testing.allocator.free(encoded);

    var source_chunks = decoder.ChunkIterator{
        .buffer = source,
        .pos = 14,
    };

    var encoded_chunks = encoder.ChunkIterator(.rgba){
        .pixels = image.pixels,
    };

    while (source_chunks.next()) |source_chunk| {
        const encoded_chunk = encoded_chunks.next().?;

        try testing.expectEqual(source_chunk, encoded_chunk);
    }
}

test "image decode by reference" {
    const bench = @import("bench.zig");

    var dir = try std.fs.cwd().openDir("src/bench/data/", .{ .iterate = true });
    defer dir.close();
    var entries = dir.iterate();

    while (try entries.next()) |entry| if (entry.kind == .file) {
        const file = try entries.dir.readFileAlloc(testing.allocator, entry.name, std.math.maxInt(usize));
        defer testing.allocator.free(file);

        var reference = try bench.decode(.reference, file, testing.allocator);
        defer reference.deinit();

        var image = try Image(.rgba).init(testing.allocator, file);
        defer image.deinit();

        for (reference.pixels, image.pixels, 0..) |ref, img, i| {
            std.testing.expectEqual(ref, img) catch |e| {
                std.debug.print("{d}: {} {}", .{ i, ref, img });
                return e;
            };
        }
    };
}

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

    const expected = [_]Chunk{
        .{ .index = .{ .index = 1 } },
        .{ .diff = .{ .dr = 1, .dg = 2, .db = 3 } },
        .{ .luma = .{ .dg = 1, .dr_dg = 2, .db_dg = 3 } },
        .{ .run = .{ .run = 32 } },
        .{ .run = .{ .run = 1 } },
        .{ .rgb = .{ .r = 1, .g = 2, .b = 3 } },
        .{ .rgba = .{ .r = 1, .g = 2, .b = 3, .a = 4 } },
    };

    var chunks = decoder.ChunkIterator{ .buffer = &bytes };

    for (expected) |e| try testing.expectEqual(e, chunks.next().?);
}

test "encoder" {
    const source: []const u8 = @embedFile("bench/data/dice.qoi");

    const image = try Image(.rgba).init(testing.allocator, source);
    defer image.deinit();

    const encoded = try image.encode(testing.allocator);
    defer testing.allocator.free(encoded);

    try testing.expect(mem.eql(u8, source, encoded));
}

test "operations" {
    assert(std.meta.eql(
        (Chunk.Diff{ .dr = 3, .dg = 2, .db = 1 }).apply(
            Pixel{ .r = 10, .g = 10, .b = 10 },
        ),
        Pixel{ .r = 11, .g = 10, .b = 9 },
    ));

    const p1 = Pixel{ .r = 206, .g = 236, .b = 206, .a = 27 };
    const p2 = Pixel{ .r = 206, .g = 241, .b = 206, .a = 27 };

    try testing.expectEqual(
        Chunk.Luma{ .dg = 37, .db_dg = 3, .dr_dg = 3 },
        p2.luma(p1).?,
    );
}
