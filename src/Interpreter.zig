const Interpreter = @This();
const Token = @import("Token.zig");
const Expr = @import("expr.zig").Expr;
const reportErr = @import("root").reportErr;

const Literal = Token.Literal;
const Error = error{RuntimeError};

pub fn evaluate(expr: *const Expr) Error!Literal {
    return expr.visit(Interpreter, .{});
}

pub fn visitBinary(expr: Expr.Binary, _: struct {}) Error!Literal {
    const left = try evaluate(expr.left);
    const right = try evaluate(expr.right);

    switch (expr.operator.token_type) {
        // arithmetic
        .Plus => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Literal{ .int = left.int + right.toInt() },
                .float => Literal{ .float = left.float + right.toFloat() },
                else => unreachable,
            };
        },
        .Minus => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Literal{ .int = left.int - right.toInt() },
                .float => Literal{ .float = left.float - right.toFloat() },
                else => unreachable,
            };
        },
        .Slash => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Literal{ .int = @divTrunc(left.int, right.toInt()) },
                .float => Literal{ .float = left.float / right.toFloat() },
                else => unreachable,
            };
        },
        .Star => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Literal{ .int = left.int * right.toInt() },
                .float => Literal{ .float = left.float * right.toFloat() },
                else => unreachable,
            };
        },
        // comparison
        .Greater => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Literal{ .bool = left.toFloat() > right.toFloat() };
        },
        .GreaterEqual => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Literal{ .bool = left.toFloat() >= right.toFloat() };
        },
        .Less => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Literal{ .bool = left.toFloat() < right.toFloat() };
        },
        .LessEqual => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Literal{ .bool = left.toFloat() <= right.toFloat() };
        },
        // equality
        .BangEqual => return Literal{ .bool = !left.isEqual(right) },
        .EqualEqual => return Literal{ .bool = left.isEqual(right) },
        else => unreachable,
    }
}

pub fn visitGrouping(expr: Expr.Grouping, _: struct {}) Error!Literal {
    return try evaluate(expr.expr);
}

pub fn visitLiteral(expr: Expr.Literal, _: struct {}) Error!Literal {
    return expr.value;
}

pub fn visitUnary(expr: Expr.Unary, _: struct {}) Error!Literal {
    const right = try evaluate(expr.right);

    switch (expr.operator.token_type) {
        .Minus => {
            try assertNumeric(expr.operator.line, right);
            return switch (right) {
                .float => Literal{ .float = -right.float },
                .int => Literal{ .int = -right.int },
                else => unreachable,
            };
        },
        .Bang => return Literal{ .bool = !isTruthy(right) },
        else => unreachable,
    }
}

fn isTruthy(literal: Literal) bool {
    if (literal == .none) return false;
    if (literal == .bool) return literal.bool;

    return true;
}

fn assertNumeric(line: usize, literal: Literal) !void {
    if (!literal.isNumeric()) {
        reportErr(line, "Expected number, found '{}'", .{literal});
        return error.RuntimeError;
    }
}

fn assertNumericOperands(line: usize, a: Literal, b: Literal) !void {
    try assertNumeric(line, a);
    try assertNumeric(line, b);
}

test "Interpreter" {
    const std = @import("std");

    const root = Expr{
        .binary = Expr.Binary{
            .left = &Expr{
                .unary = Expr.Unary{
                    .operator = .{ .token_type = .Minus, .lexeme = "-" },
                    .right = &Expr{
                        .literal = Expr.Literal{ .value = .{ .int = 123 } },
                    },
                },
            },
            .operator = .{ .token_type = .Star, .lexeme = "*" },
            .right = &Expr{
                .grouping = Expr.Grouping{
                    .expr = &Expr{ .literal = .{ .value = .{ .float = 45.67 } } },
                },
            },
        },
    };

    std.debug.print("{}\n", .{try Interpreter.evaluate(&root)});
}
