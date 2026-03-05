const std = @import("std");
const Parser = @import("parser.zig");
const Tree = @import("tree.zig");

const Token = struct {
    name: []u8,
    pattern: []u8,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    const input_path = args[1];
    const output_path = args[2];
    const action = args[3];

    const input_file = try std.fs.openFileAbsolute(input_path, .{});
    const output_file = try std.fs.createFileAbsolute(output_path, .{});
    _ = output_file;

    const input = try input_file.readToEndAlloc(allocator, 2 * 1024 * 1024);
    const tokens: []Token = (try std.json.parseFromSlice(struct { tokens: []Token }, allocator, input, .{})).value.tokens;

    var tree = Tree{};
    for (tokens) |token| {
        const nodes = try Parser.parse(allocator, token.pattern);
        tree.insert(allocator, .{ .token = token.name }, nodes);
    }

    if (std.mem.eql(u8, action, "graph-ir")) {
        tree.dump(allocator);
    }

    tree.expand(allocator);
    if (std.mem.eql(u8, action, "graph")) {
        tree.dump(allocator);
    } else if (std.mem.eql(u8, action, "generate")) {
        std.debug.print("i would generate some code here\n", .{});
    } else if (std.mem.eql(u8, action, "graph-ir")) {
    } else {
        std.debug.panic("invalid action: {s}", .{action});
    }
}

test {
    // ensure that the queue tests run
    _ = @import("queue.zig");
}
