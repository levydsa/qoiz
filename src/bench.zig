const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const io = std.io;
const zubench = @import("zubench");
const c = @cImport({
    @cInclude("qoi.h");
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

    pub fn deinit(self: Buffer) void {
        self.allocator.free(self.slice);
    }
};

pub fn encode(impl: Impl, image: qoi.Image(.rgba), gpa: mem.Allocator) !Buffer {
    switch (impl) {
        .zigqoi => {
            return .{
                .slice = try zigqoi.encodeBuffer(gpa, .{
                    .height = image.height,
                    .width = image.width,
                    .pixels = @ptrCast(image.pixels),
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

                slice.ptr = @ptrCast(c.qoi_encode(@ptrCast(image.pixels), &desc, &len));
                slice.len = @intCast(len);

                break :slice slice;
            }, .allocator = std.heap.raw_c_allocator };
        },
    }
}

pub fn decode(impl: Impl, source: []const u8, gpa: mem.Allocator) !qoi.Image(.rgba) {
    switch (impl) {
        .zigqoi => {
            const image = try zigqoi.decodeBuffer(gpa, source);
            return qoi.Image(.rgba){
                .allocator = gpa,
                .width = image.width,
                .height = image.height,
                .pixels = @alignCast(@ptrCast(image.pixels)),
                .header = undefined,
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
                .header = undefined,
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

fn variance(xs: []f64, m: f64) f64 {
    var v: f64 = 0;

    for (xs, 1..) |x, n| {
        v += (std.math.pow(f64, x - m, 2) - v) / std.math.lossyCast(f64, n);
    }

    return v;
}

fn mean(xs: []f64) f64 {
    var m: f64 = 0;

    for (xs, 1..) |x, n| {
        m += (x - m) / std.math.lossyCast(f64, n);
    }

    return m;
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const impl = std.meta.stringToEnum(Impl, args.next().?).?;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const files = [_][]const u8{
        "src/bench/data/dice.qoi",
        "src/bench/data/edgecase.qoi",
        "src/bench/data/kodim10.qoi",
        "src/bench/data/kodim23.qoi",
        "src/bench/data/qoi_logo.qoi",
        "src/bench/data/testcard.qoi",
        "src/bench/data/testcard_rgba.qoi",
        "src/bench/data/wikipedia_008.qoi",
        "src/bench/data/zero.qoi",
    };

    const names = [files.len][]const u8{
        "dice",
        "edgecase",
        "kodim10",
        "kodim23",
        "qoi_logo",
        "testcard",
        "testcard_rgba",
        "wikipedia_008",
        "zero",
    };

    const max_filename_len = comptime max: {
        var best = 0;

        for (names) |name| {
            best = @max(name.len, best);
        }

        break :max best;
    };

    const buffers = buffers: {
        var bs = std.ArrayList([]u8).init(arena.allocator());

        inline for (files) |file| {
            try bs.append(try std.fs.cwd().readFileAlloc(arena.allocator(), file, std.math.maxInt(usize)));
        }

        break :buffers bs;
    };

    for (buffers.allocatedSlice()[0..files.len], names) |buffer, name| {

        const sample_count = 10;
        var samples_decode: [sample_count]f64 = undefined;
        var samples_encode: [sample_count]f64 = undefined;

        for (0..sample_count) |n| {
            var timer = try std.time.Timer.start();

            const image = try decode(impl, buffer, arena.allocator());
            defer image.deinit();

            samples_decode[n] = std.math.lossyCast(f64, timer.lap()) / std.time.ns_per_ms;

            const raw = try encode(impl, image, arena.allocator());
            defer raw.deinit();

            samples_encode[n] = std.math.lossyCast(f64, timer.lap()) / std.time.ns_per_ms;
        }

        const decode_mean = mean(&samples_decode);
        const decode_variance = variance(&samples_decode, decode_mean);

        const encode_mean = mean(&samples_encode);
        const encode_variance = variance(&samples_decode, decode_variance);

        std.debug.print(
            "{[name]s: >[len]} : dec. {[dec_mean]d: >6.3}ms ±σ {[dec_std]d: >6.3}ms | enc. {[enc_mean]d:.3}ms ±σ {[enc_std]d:.3}ms\n",
            .{
                .name = name,
                .len = max_filename_len,
                .dec_mean = decode_mean,
                .dec_std = std.math.sqrt(decode_variance),
                .enc_mean = encode_mean,
                .enc_std = std.math.sqrt(encode_variance)
            }
        );
    }

    // const dice = std.fs.cwd().readFileAlloc(
    //     arena.allocator(),
    //     "bench/data/dice.qoi",
    //     std.math.maxInt(usize),
    // );


    // inline for ([_]Impl{ .reference, .qoiz, .zigqoi }) |impl| {
    //     var ellapsed = try std.time.Timer.start();
    //     var time = std.StringHashMap(MinMax).init(arena.allocator());

    //     var dir = try std.fs.cwd().openDir("src/bench/data/", .{ .iterate = true });
    //     defer dir.close();
    //     var entries = dir.iterate();

    //     while (try entries.next()) |entry| if (entry.kind == .file) for (0..32) |_| {
    //         const file = try entries.dir.readFileAlloc(gpa.allocator(), entry.name, std.math.maxInt(usize));
    //         defer gpa.allocator().free(file);

    //         var timer = try std.time.Timer.start();

    //         var image = try decode(impl, file, gpa.allocator());
    //         defer image.deinit();

    //         try time.put(entry.name, (time.get(entry.name) orelse MinMax{}).new(timer.lap() / std.time.ns_per_us));
    //     };

    //     var iter = time.iterator();
    //     std.debug.print("{}: {d}ms\n", .{ impl, ellapsed.read() / std.time.ns_per_ms });
    //     while (iter.next()) |entry| {
    //         const v = entry.value_ptr.*;
    //         const min = v.min;
    //         const max = v.max;
    //         std.debug.print("\t{s}: {d}μs±{d}\n", .{ entry.key_ptr.*, (min + max) / 2, (min + max) / 2 - min });
    //     }
    // }
}
