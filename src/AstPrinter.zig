expressions_evaluated: usize = 0,

const AstPrinter = @This();
const std = @import("std");
const Writer = std.fs.File.Writer;
const Error = error{EndOfStream} || std.fs.File.Writer.Error;
const Expr = @import("expr.zig").Expr;

pub fn parenthesize(self: *AstPrinter, expr: *const Expr, writer: Writer) Error!void {
    try expr.visit(self, writer);
}

pub fn visitBinary(self: *AstPrinter, expr: Expr.Binary, writer: Writer) Error!void {
    try writer.print("({s} ", .{expr.operator.lexeme});
    try self.parenthesize(expr.left, writer);
    try writer.writeByte(' ');
    try self.parenthesize(expr.right, writer);
    try writer.writeByte(')');
    self.expressions_evaluated += 1;
}

pub fn visitGrouping(self: *AstPrinter, expr: Expr.Grouping, writer: Writer) Error!void {
    _ = try writer.write("(group ");
    try self.parenthesize(expr.expr, writer);
    try writer.writeByte(')');
    self.expressions_evaluated += 1;
}

pub fn visitLiteral(_: *AstPrinter, expr: Expr.Literal, writer: Writer) Error!void {
    try writer.print("{}", .{expr.value});
}

pub fn visitUnary(self: *AstPrinter, expr: Expr.Unary, writer: Writer) Error!void {
    try writer.print("({s} ", .{expr.operator.lexeme});
    try self.parenthesize(expr.right, writer);
    writer.writeByte(')') catch unreachable;
    self.expressions_evaluated += 1;
}

test "AST" {
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

    const writer = std.io.getStdErr().writer();
    var printer = AstPrinter{};
    try printer.parenthesize(&root, writer);
    try writer.writeByte('\n');
    try std.testing.expectEqual(@as(usize, 3), printer.expressions_evaluated);
}
