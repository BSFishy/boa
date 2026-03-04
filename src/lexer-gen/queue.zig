const std = @import("std");

pub fn Queue(comptime Child: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            data: Child,
            next: ?*Node,
        };

        start: ?*Node,
        end: ?*Node,

        pub const empty: Self = .{ .start = null, .end = null };

        pub fn enqueue(self: *Self, allocator: std.mem.Allocator, value: Child) !void {
            const node = try allocator.create(Node);
            node.* = .{ .data = value, .next = null };
            if (self.end) |end| {
                end.next = node;
            } else {
                self.start = node;
            }

            self.end = node;
        }

        pub fn dequeue(self: *Self, allocator: std.mem.Allocator) ?Child {
            const start = self.start orelse return null;
            defer allocator.destroy(start);

            if (start.next) |next| {
                self.start = next;
            } else {
                self.start = null;
                self.end = null;
            }

            return start.data;
        }
    };
}

test Queue {
    const allocator = std.testing.allocator;
    var int_queue: Queue(i32) = .empty;

    try int_queue.enqueue(allocator, 25);
    try int_queue.enqueue(allocator, 50);
    try int_queue.enqueue(allocator, 75);
    try int_queue.enqueue(allocator, 100);

    try std.testing.expectEqual(int_queue.dequeue(allocator), 25);
    try std.testing.expectEqual(int_queue.dequeue(allocator), 50);
    try std.testing.expectEqual(int_queue.dequeue(allocator), 75);
    try std.testing.expectEqual(int_queue.dequeue(allocator), 100);
    try std.testing.expectEqual(int_queue.dequeue(allocator), null);

    try int_queue.enqueue(allocator, 5);
    try std.testing.expectEqual(int_queue.dequeue(allocator), 5);
    try std.testing.expectEqual(int_queue.dequeue(allocator), null);
}
