const std = @import("std");
const Parser = @import("parser.zig");
const Queue = @import("queue.zig").Queue;
const Tree = @This();

const Map = std.AutoArrayHashMapUnmanaged;

const Quantifier = struct {
    quant: Parser.Quantifier,
    tail: Tail,
    left: []const Parser.Node,
    expanded: bool,

    pub fn copy(self: Quantifier) Quantifier {
        var self_copy = self;
        self_copy.expanded = false;
        return self_copy;
    }
};

const Tail = union(enum) {
    token: []const u8,
    subtree: struct {
        tails: *Map(*Tree, void),
        tree: *Tree,
    },

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(".{{ ", .{});

        switch (this) {
            .token => |token| try writer.print(".token = \"{s}\"", .{token}),
            .subtree => |_| try writer.print(".subtree", .{}),
        }

        try writer.print(" }}", .{});
    }

    fn defaultTree(self: Tail) ?*Tree {
        return switch (self) {
            .token => null,
            .tree => |tree| tree,
        };
    }
};

const Sequence = struct {
    tree: *Tree,
    expanded: bool = false,
};

chars: Map(u21, *Tree) = .empty,
sequences: Map(u21, Sequence) = .empty,
quantifiers: std.ArrayListUnmanaged(Quantifier) = .empty,
tail: ?[]const u8 = null,

const Iterator = struct {
    visited: Map(*Tree, void) = .empty,
    queue: Queue(*Tree),

    pub fn init(allocator: std.mem.Allocator, root: *Tree) Iterator {
        var queue: Queue(*Tree) = .empty;
        queue.enqueue(allocator, root) catch unreachable;
        return .{ .queue = queue };
    }

    pub fn next(self: *Iterator, allocator: std.mem.Allocator) ?*Tree {
        const tree = self.queue.dequeue(allocator) orelse return null;

        {
            var iterator = tree.chars.iterator();
            while (iterator.next()) |entry| {
                const subtree = entry.value_ptr.*;
                if (self.visited.contains(subtree)) {
                    continue;
                }

                self.visited.put(allocator, subtree, {}) catch unreachable;
                self.queue.enqueue(allocator, subtree) catch unreachable;
            }
        }

        {
            var iterator = tree.sequences.iterator();
            while (iterator.next()) |entry| {
                const subtree = entry.value_ptr.tree;
                if (self.visited.contains(subtree)) {
                    continue;
                }

                self.visited.put(allocator, subtree, {}) catch unreachable;
                self.queue.enqueue(allocator, subtree) catch unreachable;
            }
        }

        return tree;
    }
};

pub fn iter(self: *Tree, allocator: std.mem.Allocator) Iterator {
    return .init(allocator, self);
}

fn getOrCreateChar(self: *Tree, allocator: std.mem.Allocator, c: u21, tail: ?*Tree) *Tree {
    if (self.chars.get(c)) |tree| {
        return tree;
    }

    const s = blk: {
        if (tail) |t| {
            break :blk t;
        }

        const s = allocator.create(Tree) catch unreachable;
        s.* = .{};
        break :blk s;
    };

    self.chars.put(allocator, c, s) catch unreachable;
    return s;
}

fn getOrCreateSequence(self: *Tree, allocator: std.mem.Allocator, c: u21, tail: ?*Tree) *Tree {
    if (self.sequences.get(c)) |tree| {
        return tree.tree;
    }

    const s = blk: {
        if (tail) |t| {
            break :blk t;
        }

        const s = allocator.create(Tree) catch unreachable;
        s.* = .{};
        break :blk s;
    };

    self.sequences.put(allocator, c, .{ .tree = s }) catch unreachable;
    return s;
}

fn concat(self: *Tree, allocator: std.mem.Allocator, base: []const []const Parser.Node, tail_nodes: []const Parser.Node, full_tail: Tail) void {
    const subtree = allocator.create(Tree) catch unreachable;
    subtree.* = .{};

    var tails: Map(*Tree, void) = .empty;
    tails.put(allocator, subtree, {}) catch unreachable;

    const tail: Tail = .{ .subtree = .{ .tree = subtree, .tails = &tails } };

    for (base) |nodes| {
        self.insert(allocator, tail, nodes);
    }

    for (tails.keys()) |tail_tree| {
        tail_tree.insert(allocator, full_tail, tail_nodes);
    }
}

pub fn insert(self: *Tree, allocator: std.mem.Allocator, tail: Tail, nodes: []const Parser.Node) void {
    if (nodes.len == 0) {
        switch (tail) {
            .token => |tail_token| {
                if (self.tail) |t| {
                    std.debug.panic("Not overriding tail {s} with {s} in insert\n", .{t, tail_token});
                } else {
                    self.tail = tail_token;
                }
            },
            .subtree => |subtree| {
                subtree.tails.put(allocator, self, {}) catch unreachable;
            },
        }

        return;
    }

    const tail_getter = if (nodes.len == 1) blk: {
        switch (tail) {
            .subtree => |subtree| break :blk subtree.tree,
            else => break :blk null,
        }
    } else null;
    const node = nodes[0];

    switch (node) {
        .char => |c| {
            const s = self.getOrCreateChar(allocator, c, tail_getter);
            s.insert(allocator, tail, nodes[1..]);
        },
        .sequence => |c| {
            const s = self.getOrCreateSequence(allocator, c, tail_getter);
            s.insert(allocator, tail, nodes[1..]);
        },
        .group => |group| {
            self.concat(allocator, group, nodes[1..], tail);
        },
        .quantifier => |quant| {
            self.quantifiers.append(allocator, .{ .quant = quant, .tail = tail, .left = nodes[1..], .expanded = false }) catch unreachable;
        },
    }
}

fn isExpanded(self: *const Tree) bool {
    if (!self.expanded) {
        return false;
    }

    var iterator = self.sequences.iterator();
    while (iterator.next()) |entry| {
        const sequence = entry.value_ptr.*;
        if (!sequence.expanded) {
            return false;
        }
    }

    for (self.quantifiers.items) |quant| {
        if (!quant.expanded) {
            return false;
        }
    }

    return true;
}

const ExpansionIterator = struct {
    const Step = enum { quantifier, sequence, char };

    quantifier_trees: Queue(*Tree),
    sequence_trees: Queue(*Tree),
    char_trees: Queue(*Tree),

    quantifier_visited: Map(*Tree, void),
    sequence_visited: Map(*Tree, void),
    char_visited: Map(*Tree, void),

    pub const empty: ExpansionIterator = .{
        .quantifier_trees = .empty,
        .sequence_trees = .empty,
        .char_trees = .empty,

        .quantifier_visited = .empty,
        .sequence_visited = .empty,
        .char_visited = .empty,
    };

    pub fn enqueue(self: *ExpansionIterator, allocator: std.mem.Allocator, step: Step, tree: *Tree) void {
        const visited = switch (step) {
            .quantifier => &self.quantifier_visited,
            .sequence => &self.sequence_visited,
            .char => &self.char_visited,
        };

        if (visited.contains(tree)) {
            return;
        }

        var trees = switch (step) {
            .quantifier => &self.quantifier_trees,
            .sequence => &self.sequence_trees,
            .char => &self.char_trees,
        };

        visited.put(allocator, tree, {}) catch unreachable;
        trees.enqueue(allocator, tree) catch unreachable;
    }

    pub fn next(self: *ExpansionIterator, allocator: std.mem.Allocator) ?struct{ tree: *Tree, step: Step } {
        if (self.quantifier_trees.dequeue(allocator)) |tree| {
            return .{ .tree = tree, .step = .quantifier };
        }

        if (self.sequence_trees.dequeue(allocator)) |tree| {
            return .{ .tree = tree, .step = .sequence };
        }

        if (self.char_trees.dequeue(allocator)) |tree| {
            return .{ .tree = tree, .step = .char };
        }

        return null;
    }
};

pub fn expand(self: *Tree, allocator: std.mem.Allocator) void {
    var iterator: ExpansionIterator = .empty;
    iterator.enqueue(allocator, .quantifier, self);

    while (iterator.next(allocator)) |index| {
        const tree = index.tree;
        const step = index.step;

        switch (step) {
            .quantifier => {
                while (tree.hasUnexpandedQuantifiers()) {
                    tree.expandQuantifiers(allocator);
                }

                iterator.enqueue(allocator, .sequence, tree);
            },
            .sequence => {
                tree.expandSequences(allocator, &iterator);

                iterator.enqueue(allocator, .char, tree);
            },
            .char => {
                var char_iterator = tree.chars.iterator();
                while (char_iterator.next()) |entry| {
                    const subtree = entry.value_ptr.*;
                    iterator.enqueue(allocator, .quantifier, subtree);
                }
            },
        }
    }
}

fn hasUnexpandedQuantifiers(self: *const Tree) bool {
    for (self.quantifiers.items) |quant| {
        if (!quant.expanded) {
            return true;
        }
    }

    return false;
}

fn expandQuantifiers(self: *Tree, allocator: std.mem.Allocator) void {
    for (self.quantifiers.items) |*quant| {
        if (quant.expanded) {
            continue;
        }

        quant.expanded = true;
        const q = quant.quant.quant;
        if (q.isZero()) {
            self.insert(allocator, quant.tail, quant.left);
        }

        if (q.isOne()) {
            const subtree = allocator.create(Tree) catch unreachable;
            subtree.* = .{};

            var tails: Map(*Tree, void) = .empty;
            tails.put(allocator, subtree, {}) catch unreachable;

            const tail: Tail = .{ .subtree = .{ .tree = subtree, .tails = &tails } };
            self.insert(allocator, tail, &.{quant.quant.inner.*});

            for (tails.keys()) |tail_tree| {
                tail_tree.insert(allocator, quant.tail, quant.left);
            }

            if (q.isMore()) {
                subtree.insert(allocator, tail, &.{quant.quant.inner.*});
            }
        }
    }
}

fn sequenceMatches(s: u21, c: u21) bool {
    switch (s) {
        'a' => {
            if ('a' <= c and c <= 'z') {
                return true;
            }

            if ('0' <= c and c <= '9') {
                return true;
            }
        },

        'A' => {
            if ('a' <= c and c <= 'z') {
                return true;
            }

            if ('A' <= c and c <= 'Z') {
                return true;
            }

            if ('0' <= c and c <= '9') {
                return true;
            }
        },

        else => unreachable,
    }

    return false;
}

fn expandSequences(self: *Tree, allocator: std.mem.Allocator, expansion_iterator: *ExpansionIterator) void {
    var iterator = self.sequences.iterator();
    while (iterator.next()) |entry| {
        const s = entry.key_ptr.*;
        const sequence = entry.value_ptr;
        const subtree = sequence.tree;

        if (sequence.expanded) {
            continue;
        }

        sequence.expanded = true;
        expansion_iterator.enqueue(allocator, .quantifier, subtree);

        var char_iterator = self.chars.iterator();
        while (char_iterator.next()) |char_entry| {
            const c = char_entry.key_ptr.*;
            const char_tree = char_entry.value_ptr.*;

            if (!sequenceMatches(s, c)) {
                continue;
            }

            char_tree.copy(allocator, subtree);
        }
    }
}

fn copy(self: *Tree, allocator: std.mem.Allocator, other: *const Tree) void {
    if (self == other) {
        return;
    }

    {
        var iterator = other.chars.iterator();
        while (iterator.next()) |entry| {
            const c = entry.key_ptr.*;
            const subtree = entry.value_ptr.*;

            if (self.chars.get(c)) |char_tree| {
                char_tree.copy(allocator, subtree);
            } else {
                self.chars.put(allocator, c, subtree) catch unreachable;
            }
        }
    }

    {
        var iterator = other.sequences.iterator();
        while(iterator.next()) |entry| {
            const c = entry.key_ptr.*;
            const sequence = entry.value_ptr;
            const subtree = sequence.tree;

            if (self.sequences.get(c)) |seq_tree| {
                seq_tree.tree.copy(allocator, subtree);
            } else {
                self.sequences.put(allocator, c, .{ .tree = subtree }) catch unreachable;
            }
        }
    }

    for (other.quantifiers.items) |quant| {
        self.quantifiers.append(allocator, quant.copy()) catch unreachable;
    }

    if (self.tail) |_| {
        if (other.tail) |_| {
            // Both have a tail, however we do not override, because unexpanded
            // tails must take precedence over expanded tails
        }
    } else {
        if (other.tail) |tail| {
            self.tail = tail;
        }
    }
}

fn print(indent: usize, comptime str: []const u8, args: anytype) void {
    for (0..indent) |_| {
        std.debug.print(" ", .{});
    }

    std.debug.print(str, args);
}

pub fn dump(self: *Tree, allocator: std.mem.Allocator) void {
    std.debug.print("digraph {{\n", .{});

    var iterator = self.iter(allocator);
    while (iterator.next(allocator)) |tree| {
        {
            var char_iterator = tree.chars.iterator();
            while (char_iterator.next()) |entry| {
                const char = entry.key_ptr.*;
                const subtree = entry.value_ptr.*;

                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(char, &buf) catch unreachable;
                std.debug.print("  \"{*}\" -> \"{*}\" [label=\"{s}\"];\n", .{tree, subtree, buf[0..len]});
            }
        }

        {
            var seq_iterator = tree.sequences.iterator();
            while (seq_iterator.next()) |entry| {
                const char = entry.key_ptr.*;
                const subtree = entry.value_ptr.tree;

                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(char, &buf) catch unreachable;
                std.debug.print("  \"{*}\" -> \"{*}\" [label=\"\\\\{s}\" color=blue];\n", .{tree, subtree, buf[0..len]});
            }
        }

        if (tree.tail) |tail| {
            std.debug.print("  \"{*}\" -> \"{s}\" [color=red];\n", .{tree, tail});
        }
    }

    std.debug.print("}}\n", .{});
}
