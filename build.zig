const std = @import("std");

const Build = *std.Build;
const Target = std.Build.ResolvedTarget;
const Optimize = std.builtin.OptimizeMode;
const allocator = std.heap.page_allocator;

const Context = struct {
    target: Target,
    optimize: Optimize,

    tests: std.ArrayListUnmanaged(*std.Build.Step.Run) = .empty,

    fn addTest(self: *Context, b: Build, module: *std.Build.Module) void {
        const tests = b.addTest(.{
            .root_module = module,
        });

        const run_tests = b.addRunArtifact(tests);
        self.tests.append(allocator, run_tests) catch unreachable;
    }

    fn addTests(self: *const Context, b: Build) void {
        const test_step = b.step("test", "Run tests");

        for (self.tests.items) |test_run| {
            test_step.dependOn(&test_run.step);
        }
    }
};

pub fn build(b: Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var ctx: Context = .{ .target = target, .optimize = optimize };

    // MODULES
    const lexer = lexer_generator(b, &ctx);
    boac_exe(b, &ctx, .{ .lexer = lexer });

    // TESTS
    ctx.addTests(b);
}

fn lexer_generator(b: Build, ctx: *Context) *std.Build.Module {
    const lexer_gen = b.addExecutable(.{
        .name = "lexer-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lexer-gen/main.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
        }),
    });

    b.installArtifact(lexer_gen);
    ctx.addTest(b, lexer_gen.root_module);

    const run_lexer_gen = b.addRunArtifact(lexer_gen);
    run_lexer_gen.addFileArg(b.path("src/boac/lexer.json"));
    const lexer_path = run_lexer_gen.addOutputFileArg("lexer.zig");
    run_lexer_gen.addArgs(&.{ "generate" });
    const lexer = b.addModule("lexer", .{
        .root_source_file = lexer_path,
        .target = ctx.target,
    });

    const run_step = b.step("lexer-graph", "Generate a graphviz representing the lexer");
    const run_cmd = b.addRunArtifact(lexer_gen);
    run_cmd.addFileArg(b.path("src/boac/lexer.json"));
    run_cmd.addArgs(&.{ "/dev/null", "graph" });
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    return lexer;
}

fn boac_exe(b: Build, ctx: *Context, deps: struct { lexer: *std.Build.Module }) void {
    const boac = b.addExecutable(.{
        .name = "boac",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/boac/main.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{
                .{ .name = "lexer", .module = deps.lexer },
            },
        }),
    });

    b.installArtifact(boac);
    ctx.addTest(b, boac.root_module);

    const run_step = b.step("run", "Run boac");
    const run_cmd = b.addRunArtifact(boac);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
