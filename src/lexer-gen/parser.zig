const std = @import("std");
const Queue = @import("queue.zig").Queue;
const Parser = @This();

pub const Node = union(enum) {
    char: u21,
    sequence: u21,
    group: [][]Node,
    charlist: struct { list: []Node },
    quantifier: Quantifier,

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(".{{ ", .{});
        switch (this) {
            .char => |c| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &buf) catch unreachable;
                try writer.print(".char = {s}", .{buf[0..len]});
            },
            .sequence => |c| {
                var buf: [5]u8 = .{ '\\', undefined, undefined, undefined, undefined };
                const len = (std.unicode.utf8Encode(c, buf[1..]) catch unreachable) + 1;
                try writer.print(".sequence = {s}", .{buf[0..len]});
            },
            .group => |group| {
                try writer.print(".group = .{{ ", .{});

                for (group) |subgroup| {
                    try writer.print(".{{ ", .{});

                    for (subgroup) |node| {
                        try writer.print("{f}", .{node});
                    }

                    try writer.print(" }}", .{});
                }

                try writer.print(" }}", .{});
            },
            .charlist => |charlist| {
                try writer.print(".charlist = {any}", .{charlist});
            },
            .quantifier => |quant| {
                try writer.print(".quantifier = {any}", .{quant});
            },
        }
        try writer.print(" }}", .{});
    }
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

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ![]Node {
    var nodes: std.ArrayListUnmanaged(Node) = .empty;
    var groupPos: std.ArrayListUnmanaged(usize) = .empty;
    var splitPos: Queue(usize) = .empty;
    var charlistStart: ?usize = null;

    var i: usize = 0;
    while (i < input.len) {
        defer i += 1;

        const c = input[i];
        switch (c) {
            '\\' => {
                i += 1;
                const s = input[i];
                switch (s) {
                    '\\', '[', ']', '(', '|', ')', '*' => {
                        try nodes.append(allocator, .{ .char = s });
                    },
                    else => try nodes.append(allocator, .{ .sequence = s }),
                }
            },
            '[' => {
                if (charlistStart) |_| return error.invalidCharlist;
                charlistStart = nodes.items.len;
            },
            ']' => {
                const start = charlistStart orelse return error.invalidCharlist;
                const charlist_nodes = try allocator.alloc(Node, nodes.items.len - start);
                @memcpy(charlist_nodes, nodes.items[start..]);
                try nodes.resize(allocator, start);
                try nodes.append(allocator, .{ .charlist = .{ .list = charlist_nodes } });
                charlistStart = null;
            },
            '(' => {
                try groupPos.append(allocator, nodes.items.len);
            },
            '|' => {
                try splitPos.enqueue(allocator, nodes.items.len);
            },
            ')' => {
                if (charlistStart) |_| return error.invalidCharlist;
                const startPos = groupPos.pop() orelse return error.invalidGroup;
                var group_nodes: std.ArrayListUnmanaged([]Node) = .empty;
                var currentPos = startPos;

                while (currentPos < nodes.items.len) {
                    const nextPos = splitPos.dequeue(allocator) orelse nodes.items.len;
                    defer currentPos = nextPos;

                    const current_nodes = nodes.items[currentPos..nextPos];
                    const new_nodes = try allocator.alloc(Node, current_nodes.len);
                    @memcpy(new_nodes, current_nodes);

                    try group_nodes.append(allocator, new_nodes);
                }

                try nodes.resize(allocator, startPos);
                try nodes.append(allocator, .{ .group = try group_nodes.toOwnedSlice(allocator), });
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
