const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("qoiz", .{ .source_file = .{ .path = "src/qoiz.zig" }});

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "src/bench.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(bench);
    bench.addCSourceFile(.{ .file = .{ .path = "src/bench/qoi_impl.c" }, .flags = &.{ "-O3" } });
    bench.addIncludePath(.{ .path = "src/" });
    bench.linkLibC();

    {
        const run = b.addRunArtifact(bench);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);

        const step = b.step("bench", "Run benchmarks");
        step.dependOn(&run.step);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    {
        const run = b.addRunArtifact(unit_tests);
        const step = b.step("test", "Run unit tests");
        step.dependOn(&run.step);
    }

}
