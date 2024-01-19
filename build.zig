const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("qoiz", .{
        .source_file = LazyPath.relative("src/qoiz.zig"),
    });

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = LazyPath.relative("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(bench);
    bench.addCSourceFile(.{
        .file = LazyPath.relative("src/bench/qoi_impl.c"),
        .flags = &.{"-O3"},
    });
    bench.addIncludePath(LazyPath.relative("src/"));
    bench.linkLibC();

    {
        const run = b.addRunArtifact(bench);
        if (b.args) |args| run.addArgs(args);

        const step = b.step("bench", "Run benchmarks");
        step.dependOn(&run.step);
    }

    const _test = b.addTest(.{
        .root_source_file = LazyPath.relative("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    {
        const run = b.addRunArtifact(_test);
        const step = b.step("test", "Run unit tests");
        step.dependOn(&run.step);
    }
}
