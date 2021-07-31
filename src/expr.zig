const std = @import("std");
const Writer = std.fs.File.Writer;

const Token = @import("Token.zig");

pub const Expr = union(enum) {
    binary: Binary,
    grouping: Grouping,
    literal: Literal,
    unary: Unary,

    pub const Binary = struct {
        left: *const Expr,
        operator: Token,
        right: *const Expr,
    };

    pub const Grouping = struct { expr: *const Expr };

    pub const Literal = struct { value: Token.Literal };

    pub const Unary = struct {
        operator: Token,
        right: *const Expr,
    };

    fn returnType(func: anytype) type {
        const fn_type_info = @typeInfo(@TypeOf(func));
        switch (fn_type_info) {
            .BoundFn => return fn_type_info.BoundFn.return_type.?,
            .Fn => return fn_type_info.Fn.return_type.?,
            else => @compileError("returnType() must be passed a function or method"),
        }
    }

    pub fn visit(self: Expr, visitor: anytype, args: anytype) returnType(visitor.visitBinary) {
        return switch (self) {
            .binary => |expr| visitor.visitBinary(expr, args),
            .grouping => |expr| visitor.visitGrouping(expr, args),
            .literal => |expr| visitor.visitLiteral(expr, args),
            .unary => |expr| visitor.visitUnary(expr, args),
        };
    }
};
