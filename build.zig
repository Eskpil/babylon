const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const babylon = b.addModule("babylon", .{
        .root_source_file = b.path("src/babylon.zig"),
        .target = target,
        .link_libc = true,
    });

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const sphdbus_dependency = b.dependency("sphdbus", .{
        .target = target,
        .optimize = optimize,
    });

    babylon.addImport("zigimg", zigimg_dependency.module("zigimg"));
    babylon.addImport("sphdbus", sphdbus_dependency.module("sphdbus"));

    const generate_dependency = sphdbus_dependency.artifact("generate");
    const run = b.addRunArtifact(generate_dependency);

    run.addFileArg(b.path("res/dbus/mpris/org.mpris.MediaPlayer2.Player.xml"));
    const mpris_mod = b.createModule(.{
        .root_source_file = run.addOutputFileArg("mod.zig"),
    });
    mpris_mod.addImport("sphdbus", sphdbus_dependency.module("sphdbus"));

    run.addFileArg(b.path("res/dbus/freedesktop/properties.xml"));
    const properties_mod = b.createModule(.{
        .root_source_file = run.addOutputFileArg("mod.zig"),
    });
    properties_mod.addImport("sphdbus", sphdbus_dependency.module("sphdbus"));

    const babylon_lib = b.addLibrary(.{
        .name = "babylon",
        .root_module = babylon,
    });

    babylon_lib.linkSystemLibrary("cairo");
    babylon_lib.linkSystemLibrary("freetype");
    babylon_lib.linkSystemLibrary("harfbuzz");
    babylon_lib.linkSystemLibrary("fontconfig");
    babylon_lib.linkSystemLibrary("aylin");
    babylon_lib.linkSystemLibrary("librsvg-2.0");

    b.installArtifact(babylon_lib);

    const exe = b.addExecutable(.{
        .name = "babylon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/babylon.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "babylon", .module = babylon_lib.root_module },
                .{ .name = "mpris", .module = mpris_mod },
                .{ .name = "properties", .module = properties_mod },
                .{ .name = "sphdbus", .module = sphdbus_dependency.module("sphdbus") },
            },
        }),
    });

    //    exe.root_module.linkLibrary(babylon_lib);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const svg = b.addExecutable(.{
        .name = "svg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/svg.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "babylon", .module = babylon_lib.root_module },
            },
        }),
    });

    //    exe.root_module.linkLibrary(babylon_lib);
    b.installArtifact(svg);

    const run_svg_step = b.step("svg", "Run the app");
    const run_svg_cmd = b.addRunArtifact(svg);
    run_svg_step.dependOn(&run_svg_cmd.step);

    run_svg_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_svg_cmd.addArgs(args);
    }
}
