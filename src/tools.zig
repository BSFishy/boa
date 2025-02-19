const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.process.exit(1);
        }
    }

    const l = lexer.Lexer.init(allocator);

    const writer = std.io.getStdErr().writer();
    try l.to_graph(writer);
}
