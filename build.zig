const std = @import("std");
const builtin = @import("builtin");
const zemscripten = @import("zemscripten");

const release_flags = &[_][]const u8{"-DNDEBUG"};
const debug_flags = &[_][]const u8{};
const universal_flags = &[_][]const u8{
    "-D_POSIX_C_SOURCE=199309L", // for clock_gettime()
    "-fblocks",
    "-std=c17",
    "-Werror",
    "-Wmissing-prototypes",
    "-Wall",
    "-Wextra",
    "-pedantic",
    "-Wno-unused-value",
};

const headers = &[_][]const u8{
    "box2d/base.h",
    "box2d/box2d.h",
    "box2d/collision.h",
    "box2d/id.h",
    "box2d/math_functions.h",
    "box2d/types.h",
};

const c_sources = [_][]const u8{
    "aabb.c",
    "arena_allocator.c",
    "array.c",
    "bitset.c",
    "body.c",
    "broad_phase.c",
    "constraint_graph.c",
    "contact.c",
    "contact_solver.c",
    "core.c",
    "distance.c",
    "distance_joint.c",
    "dynamic_tree.c",
    "geometry.c",
    "hull.c",
    "id_pool.c",
    "island.c",
    "joint.c",
    "manifold.c",
    "math_functions.c",
    "motor_joint.c",
    "mouse_joint.c",
    "mover.c",
    "prismatic_joint.c",
    "revolute_joint.c",
    "sensor.c",
    "shape.c",
    "solver.c",
    "solver_set.c",
    "table.c",
    "timer.c",
    "types.c",
    "weld_joint.c",
    "wheel_joint.c",
    "world.c",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "box2d",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
        }),
    });

    var flags = std.ArrayList([]const u8){};

    const emsdk_path = b.option([]const u8, "emsdk_absolute_path", "An absolute path to the emsdk") orelse b.lazyDependency("emsdk", .{}).?.builder.build_root.path.?;

    if (b.option(bool, "validate", "Enable heavy validation") == true) {
        try flags.append(b.allocator, "-DBOX2D_VALIDATE");
    }

    const disable_simd = b.option(bool, "disable_simd", "Disable SIMD") orelse false;
    const use_avx = block: {
        if (disable_simd)
            break :block false;
        if (target.result.cpu.arch != .x86_64)
            break :block false;
        break :block b.option(bool, "avx", "Enable the AVX instruction set for x86_64 targets") orelse false;
    };

    if (disable_simd) {
        try flags.append(b.allocator, "-DBOX2D_DISABLE_SIMD");
    }

    if (b.option(bool, "use_doubles", "Use double precision floating point values")) |use_doubles| {
        try flags.append(b.allocator, b.fmt("-DCP_USE_DOUBLES={s}", .{if (use_doubles) "1" else "0"}));
    }

    try flags.appendSlice(b.allocator, universal_flags);
    if (builtin.mode != .Debug) {
        try flags.append(b.allocator, "-ffast-math");
    } else {
        try flags.append(b.allocator, "-Wall");
    }

    const upstream_dep = b.dependency("box2d_upstream", .{});
    const src_root = upstream_dep.path(".");

    lib.addIncludePath(src_root.path(b, "include"));

    switch (optimize) {
        .Debug => {
            try flags.appendSlice(b.allocator, debug_flags);
        },
        else => {
            try flags.appendSlice(b.allocator, release_flags);
        },
    }

    switch (target.result.os.tag) {
        .emscripten => {
            if (!disable_simd) {
                try flags.appendSlice(b.allocator, &.{
                    "-msimd128",
                    // box2d includes this, but it doesnt seem to be real, at least for wasm-emscripten?
                    // "-msse2"
                });
            }

            lib.step.dependOn(zemscripten.activateEmsdkStepWithPath(b, emsdk_path));
        },
        else => {
            if (use_avx) {
                try flags.appendSlice(b.allocator, &.{ "-DBOX2D_AVX2", "-mavx2" });
            }
            lib.linkLibC();
        },
    }

    lib.addCSourceFiles(.{
        .root = src_root.path(b, "src"),
        .flags = flags.items,
        .files = &c_sources,
        .language = .c,
    });

    // always install headers
    for (headers) |h| {
        lib.installHeader(src_root.path(b, "include").path(b, h), h);
    }

    b.installArtifact(lib);
}
