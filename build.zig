const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const facil_dep = b.dependency("facil.io", .{
        .target = target,
        .optimize = optimize,
    });

    // create a module to be used internally.
    var zap_module = b.createModule(.{
        .source_file = .{ .path = "src/zap.zig" },
    });

    // register the module so it can be referenced
    // using the package manager.
    // TODO: How to automatically integrate the
    // facil.io dependency with the module?
    try b.modules.put(b.dupe("zap"), zap_module);

    const facil_lib = b.addStaticLibrary(.{
        .name = "facil.io",
        .target = target,
        .optimize = optimize,
    });

    facil_lib.linkLibrary(facil_dep.artifact("facil.io"));

    // we install the facil dependency, just to see what it's like
    // zig build with the default (install) step will install it
    facil_lib.installLibraryHeaders(facil_dep.artifact("facil.io"));
    const facil_install_step = b.addInstallArtifact(facil_lib);
    b.getInstallStep().dependOn(&facil_install_step.step);

    inline for ([_]struct {
        name: []const u8,
        src: []const u8,
    }{
        .{ .name = "hello", .src = "examples/hello/hello.zig" },
        .{ .name = "hello2", .src = "examples/hello2/hello2.zig" },
        .{ .name = "routes", .src = "examples/routes/routes.zig" },
        .{ .name = "serve", .src = "examples/serve/serve.zig" },
        .{ .name = "hello_json", .src = "examples/hello_json/hello_json.zig" },
        .{ .name = "endpoint", .src = "examples/endpoint/main.zig" },
        .{ .name = "wrk", .src = "wrk/zig/main.zig" },
        .{ .name = "wrk_zigstd", .src = "wrk/zigstd/main.zig" },
        .{ .name = "mustache", .src = "examples/mustache/mustache.zig" },
        .{ .name = "endpoint_auth", .src = "examples/endpoint_auth/endpoint_auth.zig" },
    }) |excfg| {
        const ex_name = excfg.name;
        const ex_src = excfg.src;
        const ex_build_desc = try std.fmt.allocPrint(
            b.allocator,
            "build the {s} example",
            .{ex_name},
        );
        const ex_run_stepname = try std.fmt.allocPrint(
            b.allocator,
            "run-{s}",
            .{ex_name},
        );
        const ex_run_stepdesc = try std.fmt.allocPrint(
            b.allocator,
            "run the {s} example",
            .{ex_name},
        );
        const example_run_step = b.step(ex_run_stepname, ex_run_stepdesc);
        const example_step = b.step(ex_name, ex_build_desc);

        var example = b.addExecutable(.{
            .name = ex_name,
            .root_source_file = .{ .path = ex_src },
            .target = target,
            .optimize = optimize,
        });

        example.linkLibrary(facil_dep.artifact("facil.io"));
        example.addModule("zap", zap_module);

        // const example_run = example.run();
        const example_run = b.addRunArtifact(example);
        example_run_step.dependOn(&example_run.step);

        // install the artifact - depending on the "example"
        const example_build_step = b.addInstallArtifact(example);
        example_step.dependOn(&example_build_step.step);
    }

    //
    // TOOLS & TESTING
    //

    // tests
    //
    const auth_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test_auth.zig" },
        .target = target,
        .optimize = optimize,
    });
    auth_tests.linkLibrary(facil_dep.artifact("facil.io"));
    auth_tests.addModule("zap", zap_module);

    const run_auth_tests = b.addRunArtifact(auth_tests);
    // TODO: for some reason, tests aren't run more than once unless
    //       dependencies have changed.
    //       So, for now, we just force the exe to be built, so in order that
    //       we can call it again when needed.
    const install_auth_tests = b.addInstallArtifact(auth_tests);

    const test_step = b.step("test", "Run unit tests [REMOVE zig-cache!]");
    test_step.dependOn(&run_auth_tests.step);
    test_step.dependOn(&install_auth_tests.step);

    // pkghash
    //
    var pkghash_exe = b.addExecutable(.{
        .name = "pkghash",
        .root_source_file = .{ .path = "./tools/pkghash.zig" },
        .target = target,
        .optimize = optimize,
    });
    var pkghash_step = b.step("pkghash", "Build pkghash");
    const pkghash_build_step = b.addInstallArtifact(pkghash_exe);
    pkghash_step.dependOn(&pkghash_build_step.step);
}
