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
    bench.addIncludePath(LazyPath.relative("src/bench/"));
    bench.linkLibC();

    {
        const run = b.addRunArtifact(bench);
        if (b.args) |args| run.addArgs(args);

        const step = b.step("bench", "Run benchmarks");
        step.dependOn(&run.step);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = LazyPath.relative("src/qoiz.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addCSourceFile(.{
        .file = LazyPath.relative("src/bench/qoi_impl.c"),
        .flags = &.{"-O3"},
    });
    unit_tests.addIncludePath(LazyPath.relative("src/bench/"));
    unit_tests.linkLibC();

    {
        const run = b.addRunArtifact(unit_tests);
        const step = b.step("test", "Run unit tests");
        step.dependOn(&run.step);
    }
}
