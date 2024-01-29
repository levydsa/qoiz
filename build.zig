const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("qoiz", .{
        .root_source_file = .{ .path = "src/qoiz.zig" },
    });

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "src/bench.zig" },
        .target = target,
        .optimize = optimize,
    });

    bench.addCSourceFile(.{
        .file = .{ .path = "src/bench/qoi_impl.c" },
        .flags = &.{"-O3"},
    });
    bench.addIncludePath(.{ .path = "src/bench/" });
    bench.linkLibC();

    {
        const run = b.addRunArtifact(bench);
        b.step("bench", "Run benchmarks").dependOn(&run.step);

        if (b.args) |args| run.addArgs(args);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/qoiz.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addCSourceFile(.{
        .file = .{ .path = "src/bench/qoi_impl.c" },
        .flags = &.{"-O3"},
    });
    unit_tests.addIncludePath(.{ .path = "src/bench/" });
    unit_tests.linkLibC();

    {
        const run = b.addRunArtifact(unit_tests);
        b.step("test", "Run unit tests").dependOn(&run.step);
    }
}
