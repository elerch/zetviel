const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    var target_query = b.standardTargetOptionsQueryOnly(.{});

    const paths = try checkNix(b, &target_query);
    const reload_discovered_native_paths = target_query.dynamic_linker.len != 0;
    const target = b.resolveTargetQuery(target_query);

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zetviel",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zetviel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    configure(exe, paths, reload_discovered_native_paths);
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    configure(exe, paths, reload_discovered_native_paths);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    configure(exe_unit_tests, paths, reload_discovered_native_paths);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn configure(compile: *std.Build.Step.Compile, paths: std.zig.system.NativePaths, reload_paths: bool) void {
    compile.linkLibC();
    compile.linkSystemLibrary("notmuch");

    // These are only needed if we are in nix develop shell
    if (!reload_paths) return;
    for (paths.lib_dirs.items) |dir|
        compile.addLibraryPath(.{ .cwd_relative = dir });
    for (paths.include_dirs.items) |dir|
        compile.addIncludePath(.{ .cwd_relative = dir });
    for (paths.rpaths.items) |dir|
        compile.addRPath(.{ .cwd_relative = dir });
}

fn checkNix(b: *std.Build, target_query: *std.Target.Query) !std.zig.system.NativePaths {
    const native_result = b.resolveTargetQuery(target_query.*);
    const paths = try std.zig.system.NativePaths.detect(b.allocator, native_result.result);

    // If we are not using nix, we can build anywhere provided the system dependencies exist
    if (!std.process.hasEnvVarConstant("NIX_BINTOOLS")) return paths;

    // Capture the natively detected paths for potential future use
    const bintools = try std.process.getEnvVarOwned(b.allocator, "NIX_BINTOOLS");

    // We'll capture the interpreter used in $NIX_BINTOOLS/bin/size
    // We expect this to be a symlink to a native elf executable
    // readlink $NIX_BINTOOLS/bin/size
    var pathbuf: [std.posix.PATH_MAX]u8 = undefined;
    // posix.readlink is supported on all OSs
    const elf_path = try std.posix.readlink(
        try std.fs.path.join(b.allocator, &[_][]const u8{
            bintools,
            "bin",
            "size",
        }),
        &pathbuf,
    );

    // Setting the dynamic linker (necessary to avoid dll hell) will put
    // zig into a non-native mode, and will therefore ignore all the native
    // paths. We'll put these back from the values captured above in
    // our configure function
    target_query.dynamic_linker = try getDynamicLinker(elf_path);
    return paths;
}
fn getDynamicLinker(elf_path: []const u8) !std.Target.DynamicLinker {
    // read the dynamic linker from this
    const elf_file = try std.fs.openFileAbsolute(elf_path, .{});
    defer elf_file.close();
    var file_contents: [1024 * 1024]u8 = undefined; // binary is expected to be appox 40k
    const read = try elf_file.readAll(&file_contents);
    if (read == 1024 * 1024) {
        std.log.err("file too big!", .{});
        return error.FileTooBig;
    }
    if (!std.mem.eql(u8, file_contents[0..4], &[_]u8{ 0x7F, 0x45, 0x4C, 0x46 })) {
        std.log.err("file not an ELF!", .{});
        return error.FileNotElf;
    }
    if (!std.mem.eql(u8, file_contents[4..9], &[_]u8{ 0x02, 0x01, 0x01, 0x00, 0x00 })) {
        std.log.err("ELF header not expected (64 bit, LSB, version 1, SYSV ABI, ABI version 0)", .{});
        std.log.err("It's possible the code will work with unexpected header...might loosen this restriction and see what happens", .{});
        std.log.err("(32 bit will require code change)", .{});
        return error.FileNotExpectedElf;
    }
    if (file_contents[0x10] != 0x02) {
        std.log.err("ELF not executable", .{});
        return error.FileNotExpectedElf;
    }
    if (file_contents[0x14] != 0x01) {
        std.log.err("ELF not version 1", .{});
        return error.FileNotExpectedElf;
    }
    // Section header table
    const e_shoff = std.mem.littleToNative(u64, @as(*u64, @ptrFromInt(@intFromPtr(file_contents[0x28 .. 0x29 + 8]))).*); // E8 9D 00 00 00 00 00 00
    // Number of sections
    const e_shnum = std.mem.littleToNative(u16, @as(*u16, @ptrFromInt(@intFromPtr(file_contents[0x3c .. 0x3d + 2]))).*); // 1d

    // Index of section header that contains section header names
    const e_shstrndx = std.mem.littleToNative(u16, @as(*u16, @ptrFromInt(@intFromPtr(file_contents[0x3e .. 0x3f + 2]))).*); // 1c
    // Beginning of section 0x1c (28) that contains header names
    const e_shstroff = e_shoff + (64 * e_shstrndx); // 0xa4e8
    const shstrtab_contents = file_contents[e_shstroff .. e_shstroff + 1 + (e_shnum * 64)];
    // Offset for my set of null terminated strings
    const shstrtab_sh_offset = std.mem.littleToNative(u64, @as(*u64, @ptrFromInt(@intFromPtr(shstrtab_contents[0x18 .. 0x19 + 8]))).*); // 0x9cec
    // Total size of section
    const shstrtab_sh_size = std.mem.littleToNative(u64, @as(*u64, @ptrFromInt(@intFromPtr(shstrtab_contents[0x20 .. 0x21 + 8]))).*); // 250
    // std.debug.print("e_shoff: {x}, e_shstrndx: {x}, e_shstroff: {x}, e_shnum: {x}, shstrtab_sh_offset: {x}, shstrtab_sh_size: {}\n", .{ e_shoff, e_shstrndx, e_shstroff, e_shnum, shstrtab_sh_offset, shstrtab_sh_size });
    const shstrtab_strings = file_contents[shstrtab_sh_offset .. shstrtab_sh_offset + 1 + shstrtab_sh_size];
    var interp: ?[]const u8 = null;
    for (0..e_shnum) |shndx| {
        // get section offset. Look for type == SHT_PROGBITS, then go fetch name
        const sh_off = e_shoff + (64 * shndx);
        const sh_contents = file_contents[sh_off .. sh_off + 1 + 64];
        const sh_type = std.mem.littleToNative(u16, @as(*u16, @ptrFromInt(@intFromPtr(sh_contents[0x04 .. 0x05 + 2]))).*);
        if (sh_type != 0x01) continue;
        // This is an offset to the null terminated string in our string content
        const sh_name_offset = std.mem.littleToNative(u16, @as(*u16, @ptrFromInt(@intFromPtr(sh_contents[0x00 .. 0x01 + 2]))).*);
        const sentinel = std.mem.indexOfScalar(u8, shstrtab_strings[sh_name_offset..], 0);
        if (sentinel == null) {
            std.log.err("Invalid ELF file", .{});
            return error.InvalidElfFile;
        }
        const sh_name = shstrtab_strings[sh_name_offset .. sh_name_offset + sentinel.?];
        // std.debug.print("section name: {s}\n", .{sh_name});
        if (std.mem.eql(u8, ".interp", sh_name)) {
            // found interpreter
            const interp_offset = std.mem.littleToNative(u64, @as(*u64, @ptrFromInt(@intFromPtr(sh_contents[0x18 .. 0x19 + 8]))).*); // 0x9218
            const interp_size = std.mem.littleToNative(u64, @as(*u64, @ptrFromInt(@intFromPtr(sh_contents[0x20 .. 0x21 + 8]))).*); // 2772
            // std.debug.print("Found interpreter at {x}, size: {}\n", .{ interp_offset, interp_size });
            interp = file_contents[interp_offset .. interp_offset + 1 + interp_size];
            // std.debug.print("Interp: {s}\n", .{interp});
        }
    }
    if (interp == null) {
        std.log.err("Could not locate interpreter", .{});
        return error.CouldNotLocateInterpreter;
    }

    var dl = std.Target.DynamicLinker{ .buffer = undefined, .len = 0 };
    dl.set(interp);
    return dl;
}
