const std = @import("std");

pub fn reportErr(line: usize, comptime msg: []const u8, args: anytype) void {
    // TODO: something else, i guess
    var buf: [512]u8 = undefined;

    report(line, "", std.fmt.bufPrint(&buf, msg, args) catch "error writing error, how ironic :^(");
}

fn report(line: usize, where: []const u8, msg: []const u8) void {
    std.debug.print("[line {}] Error{s}: {s}\n", .{ line + 1, where, msg });
}

pub fn returnType(func: anytype) type {
    const fn_type_info = @typeInfo(@TypeOf(func));
    switch (fn_type_info) {
        .BoundFn => return fn_type_info.BoundFn.return_type.?,
        .Fn => return fn_type_info.Fn.return_type.?,
        else => @compileError("returnType() must be passed a function or method"),
    }
}
