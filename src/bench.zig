const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const io = std.io;
const c = @cImport({
    @cInclude("bench/qoi.h");
});
const zigqoi = @import("bench/zig-qoi.zig");
const qoi = @import("qoiz.zig");

const Impl = enum {
    reference,
    zigqoi,
    qoiz,
};

const Buffer = struct {
    slice: []u8,
    allocator: mem.Allocator,

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.slice);
    }
};

pub fn encode(comptime impl: Impl, image: qoi.Image(.rgba), gpa: mem.Allocator) !Buffer {
    switch (impl) {
        .zigqoi => {
            return .{
                .slice = try zigqoi.encodeBuffer(gpa, .{
                    .height = image.height,
                    .width = image.width,
                    .pixels = image.pixels,
                    .colorspace = .sRGB,
                }),
                .allocator = gpa,
            };
        },
        .qoiz => {
            return .{
                .slice = try image.encode(gpa),
                .allocator = gpa,
            };
        },
        .reference => {
            return .{ .slice = slice: {
                const desc = c.qoi_desc{
                    .width = image.width,
                    .height = image.height,
                    .channels = 4,
                    .colorspace = c.QOI_LINEAR,
                };
                var len: c_int = undefined;
                var slice: []u8 = undefined;

                slice.ptr = c.qoi_encode(image.pixels, &desc, &len);
                slice.len = len;

                break :slice slice;
            }, .allocator = std.heap.raw_c_allocator };
        },
    }
}

pub fn decode(comptime impl: Impl, source: []const u8, gpa: mem.Allocator) !qoi.Image(.rgba) {
    switch (impl) {
        .zigqoi => {
            const image = try zigqoi.decodeBuffer(gpa, source);
            return qoi.Image(.rgba){
                .allocator = gpa,
                .width = image.width,
                .height = image.height,
                .pixels = @alignCast(@ptrCast(image.pixels)),
            };
        },
        .qoiz => {
            return try qoi.Image(.rgba).init(gpa, source);
        },
        .reference => {
            var desc: c.qoi_desc = undefined;
            const pixels: [*]u8 = @ptrCast(c.qoi_decode(source.ptr, @intCast(source.len), &desc, 4).?);

            const image = qoi.Image(.rgba){
                .allocator = std.heap.raw_c_allocator,
                .width = desc.width,
                .height = desc.height,
                .pixels = pixels: {
                    var slice: []qoi.Format.rgba.Type() = undefined;
                    slice.ptr = @alignCast(@ptrCast(pixels));
                    slice.len = desc.width * desc.height;
                    break :pixels slice;
                },
            };

            return image;
        },
    }
}

const MinMax = struct {
    min: u64 = std.math.maxInt(u64),
    max: u64 = std.math.minInt(u64),

    pub fn new(self: MinMax, v: u64) MinMax {
        return .{
            .min = @min(self.min, v),
            .max = @max(self.max, v),
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    inline for ([_]Impl{ .reference, .qoiz, .zigqoi }) |impl| {
        var ellapsed = try std.time.Timer.start();
        var time = std.StringHashMap(MinMax).init(arena.allocator());

        var dir = try std.fs.cwd().openDir("src/bench/data/", .{ .iterate = true });
        defer dir.close();
        var entries = dir.iterate();

        while (try entries.next()) |entry| if (entry.kind == .file) for (0..32) |_| {
            const file = try entries.dir.readFileAlloc(gpa.allocator(), entry.name, std.math.maxInt(usize));
            defer gpa.allocator().free(file);

            var reference = try decode(.reference, file, gpa.allocator());
            defer reference.deinit();

            var timer = try std.time.Timer.start();
            var image = try decode(impl, file, gpa.allocator());
            defer image.deinit();
            try time.put(entry.name, (time.get(entry.name) orelse MinMax{}).new(timer.lap() / std.time.ns_per_us));

            for (reference.pixels, image.pixels, 0..) |ref, img, i| {
                std.testing.expectEqual(ref, img) catch |e| {
                    std.debug.print("{d}: {} {}", .{ i, ref, img });
                    return e;
                };
            }
        };

        var iter = time.iterator();
        std.debug.print("{}: {d}ms\n", .{ impl, ellapsed.read() / std.time.ns_per_ms });
        while (iter.next()) |entry| {
            const v = entry.value_ptr.*;
            const min = v.min;
            const max = v.max;
            std.debug.print("\t{s}: {d}μs±{d}\n", .{ entry.key_ptr.*, (min + max) / 2, (min + max) / 2 - min });
        }
    }
}
