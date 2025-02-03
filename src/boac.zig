const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.process.exit(1);
        }
    }

    const code = try readUtf8(allocator, "examples/add.boa");
    defer allocator.free(code);

    const tokens = lex(allocator, code) catch std.process.exit(1);
    defer allocator.free(tokens);

    for (tokens) |token| {
        std.debug.print("{s} - ", .{@tagName(token.token_type)});

        for (token.source) |char| {
            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        std.debug.print("\n", .{});
    }
}

// i feel like this is pretty unoptimized but it works for now.
fn readUtf8(allocator: std.mem.Allocator, filename: []const u8) ![]u21 {
    // 2 GiB max filesize
    const contents = try std.fs.cwd().readFileAlloc(allocator, filename, 2 * 1024 * 1024 * 1024);
    defer allocator.free(contents);

    var out = std.ArrayList(u21).init(allocator);
    const view = try std.unicode.Utf8View.init(contents);
    var iterator = view.iterator();

    while (iterator.nextCodepoint()) |codepoint| {
        try out.append(codepoint);
    }

    return out.toOwnedSlice();
}

fn lex(allocator: std.mem.Allocator, code: []const u21) ![]lexer.Token {
    var l = lexer.Lexer.init(allocator);

    var diagnostics = lexer.Diagnostics{};
    const tokens = l.lex(code, .{ .diagnostics = &diagnostics }) catch |err| {
        const failure = diagnostics.failure orelse unreachable;
        try failure.print();

        return err;
    };

    return tokens;
}
