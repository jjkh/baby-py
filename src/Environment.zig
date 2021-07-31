allocator: *Allocator,
values: StringHashMap(Value),

const Environment = @This();
const std = @import("std");
const Value = @import("Interpreter.zig").Value;

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

pub fn init(allocator: *Allocator) Environment {
    return .{ .allocator = allocator, .values = StringHashMap(Value).init(allocator) };
}

pub fn deinit(self: *Environment) void {
    var it = self.values.iterator();
    while (it.next()) |*kv| {
        kv.value_ptr.destroy(self.allocator);
        self.allocator.free(kv.key_ptr.*);
    }

    self.values.deinit();
}

pub fn define(self: *Environment, identifier: []const u8, value: Value) !void {
    if (self.clearAndGetValue(identifier)) |old_value|
        old_value.* = try value.copyAlloc(self.allocator)
    else
        try self.values.put(try self.allocator.dupe(u8, identifier), try value.copyAlloc(self.allocator));
}

pub fn assign(self: *Environment, identifier: []const u8, value: Value) !void {
    if (self.clearAndGetValue(identifier)) |old_value|
        old_value.* = try value.copyAlloc(self.allocator)
    else
        return error.UndefinedIdentifier;
}

fn clearAndGetValue(self: *Environment, identifier: []const u8) ?*Value {
    if (self.values.getPtr(identifier)) |current_value| {
        current_value.destroy(self.allocator);
        return current_value;
    }

    return null;
}

pub fn get(self: Environment, identifier: []const u8) !Value {
    return self.values.get(identifier) orelse error.UndefinedIdentifier;
}
