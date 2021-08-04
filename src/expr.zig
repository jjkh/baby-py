const std = @import("std");
const Writer = std.fs.File.Writer;

const Token = @import("Token.zig");
const returnType = @import("util.zig").returnType;

pub const Expr = union(enum) {
    binary: Binary,
    grouping: Grouping,
    literal: Literal,
    logical: Logical,
    unary: Unary,
    variable: Variable,
    assign: Assign,

    pub const Binary = struct {
        left: *const Expr,
        operator: Token,
        right: *const Expr,
    };

    pub const Grouping = struct { expr: *const Expr };

    pub const Literal = struct { value: Token.Literal };

    pub const Logical = struct {
        left: *const Expr,
        operator: Token,
        right: *const Expr,
    };

    pub const Unary = struct {
        operator: Token,
        right: *const Expr,
    };

    pub const Variable = struct { identifier: Token };
    pub const Assign = struct { identifier: Token, value: *const Expr };

    pub fn visit(self: Expr, visitor: anytype, args: anytype) returnType(visitor.visitBinary) {
        return switch (self) {
            .binary => |expr| visitor.visitBinary(expr, args),
            .grouping => |expr| visitor.visitGrouping(expr, args),
            .literal => |expr| visitor.visitLiteral(expr, args),
            .logical => |expr| visitor.visitLogical(expr, args),
            .unary => |expr| visitor.visitUnary(expr, args),
            .variable => |expr| visitor.visitVariable(expr, args),
            .assign => |expr| visitor.visitAssign(expr, args),
        };
    }
};
