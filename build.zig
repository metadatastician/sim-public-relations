// SPDX-License-Identifier: MPL-2.0
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addModule("pr_practice", .{
        .root_source_file = b.path("src/practice.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "pr-practice-lab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pr_practice", .module = kernel }},
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the local practice shell").dependOn(&run.step);

    const unit_tests = b.addTest(.{ .root_module = kernel });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run event, route and assessment tests").dependOn(&run_unit_tests.step);
}
