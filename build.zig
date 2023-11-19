const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var qoi = b.addModule("qoi", .{ .source_file = .{ .path = "src/qoiz.zig" }});

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "src/bench.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(bench);
    bench.addModule("qoi", qoi);
    bench.addCSourceFile(.{ .file = .{ .path = "src/bench/qoi_impl.c" }, .flags = &.{ "-ggdb", "-O3" } });
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

    unit_tests.addModule("qoi", qoi);

    {
        const run = b.addRunArtifact(unit_tests);
        const step = b.step("test", "Run unit tests");
        step.dependOn(&run.step);
    }

}
