const std = @import("std");
const Parser = @This();

pub const Node = union(enum) {
    char: u21,
    sequence: u21,
    quantifier: Quantifier,
};

pub const Quantifier = struct {
    inner: *const Node,
    quant: enum {
        const Quant = @This();

        zeroOrMore,

        pub fn isZero(self: Quant) bool {
            return switch (self) {
                .zeroOrMore => true,
            };
        }

        pub fn isOne(self: Quant) bool {
            return switch (self) {
                .zeroOrMore => true,
            };
        }

        pub fn isMore(self: Quant) bool {
            return switch (self) {
                .zeroOrMore => true,
            };
        }
    },
};

test {
    unreachable;
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ![]Node {
    var nodes: std.ArrayListUnmanaged(Node) = .{};
    var i: usize = 0;
    while (i < input.len) {
        defer i += 1;

        const c = input[i];
        switch (c) {
            '\\' => {
                i += 1;
                const s = input[i];

                try nodes.append(allocator, .{ .sequence = s });
            },
            '*' => {
                const inner = try allocator.create(Node);
                inner.* = nodes.pop() orelse unreachable;
                try nodes.append(allocator, .{
                    .quantifier = .{
                        .inner = inner,
                        .quant = .zeroOrMore,
                    },
                });
            },
            else => {
                try nodes.append(allocator, .{ .char = c });
            },
        }
    }

    return nodes.toOwnedSlice(allocator);
}
