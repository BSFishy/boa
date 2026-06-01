const std = @import("std");
const Parser = @import("parser.zig");
const Tree = @import("tree.zig");

const Token = struct {
    name: []u8,
    pattern: []u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    const input_path = args[1];
    const output_path = args[2];
    const action = args[3];

    const cwd = std.Io.Dir.cwd();
    const output_file = try cwd.createFile(io, output_path, .{});
    _ = output_file;

    const input = try cwd.readFileAlloc(io, input_path, allocator, .unlimited);
    const tokens: []Token = (try std.json.parseFromSlice(struct { tokens: []Token }, allocator, input, .{})).value.tokens;

    var tree: Tree = .{};
    for (tokens) |token| {
        const nodes = try Parser.parse(allocator, token.pattern);
        tree.insert(allocator, .{ .token = token.name }, nodes, false);
    }

    if (std.mem.eql(u8, action, "graph-ir")) {
        tree.dump(allocator);
        return;
    }

    tree.expand(allocator);
    if (tree.tail) |tail| {
        std.debug.panic("zero length token detected: {s}\n", .{tail});
    }

    if (std.mem.eql(u8, action, "graph")) {
        tree.dump(allocator);
    } else if (std.mem.eql(u8, action, "generate")) {
        std.debug.print("i would generate some code here\n", .{});
    } else {
        std.debug.panic("invalid action: {s}", .{action});
    }
}

test {
    // ensure that the queue tests run
    _ = @import("queue.zig");
}
