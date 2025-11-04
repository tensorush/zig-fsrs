const std = @import("std");

const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const install_step = b.getInstallStep();
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_source_file = b.path("src/root.zig");
    const version: std.SemanticVersion = try .parse(manifest.version);

    // Dependencies
    const zdt_dep = b.dependency("zdt", .{
        .target = target,
        .optimize = optimize,
    });
    const zdt_mod = zdt_dep.module("zdt");

    // Public root module
    const root_mod = b.addModule("fsrs", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = root_source_file,
        .strip = b.option(bool, "strip", "Strip binary"),
        .imports = &.{
            .{ .name = "zdt", .module = zdt_mod },
        },
    });

    // Library
    const lib = b.addLibrary(.{
        .name = "fsrs",
        .version = version,
        .root_module = root_mod,
    });
    if (b.option(bool, "no-bin", "Skip emitting binary") orelse false) {
        install_step.dependOn(&lib.step);
    } else {
        b.installArtifact(lib);
    }

    // Test suite
    const tests_step = b.step("test", "Run test suite");

    const tests = b.addTest(.{
        .root_module = root_mod,
    });

    const tests_run = b.addRunArtifact(tests);
    if (b.option(bool, "debug", "Debug test suite with LLDB") orelse false) {
        // LLDB Zig config: https://github.com/ziglang/zig/blob/master/tools/lldb_pretty_printers.py#L2-L6
        const lldb_run = b.addSystemCommand(&.{
            "lldb",
            "--",
        });
        lldb_run.addArtifactArg(tests);
        tests_step.dependOn(&lldb_run.step);
    } else {
        tests_step.dependOn(&tests_run.step);
    }
    install_step.dependOn(tests_step);

    // Formatting check
    const fmt_step = b.step("fmt", "Check formatting");

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
            "build.zig.zon",
        },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
    install_step.dependOn(fmt_step);

    // Build compilation check for ZLS Build-On-Save
    // See: https://zigtools.org/zls/guides/build-on-save/
    const check_step = b.step("check", "Check compilation");
    const check_lib = b.addLibrary(.{
        .name = "fsrs",
        .version = version,
        .root_module = root_mod,
    });
    check_step.dependOn(&check_lib.step);
}
