allocator: *Allocator,
tokens: []const Token,
exprs: ExprLinkedList,
statements: ArrayList(Statement),
current_idx: usize = 0,

const Parser = @This();
const std = @import("std");
const Expr = @import("expr.zig").Expr;
const Statement = @import("statement.zig").Statement;
const Token = @import("Token.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const reportErr = @import("util.zig").reportErr;

const Error = error{ParseError} || std.mem.Allocator.Error;

// TODO: is this overcomplicating this? should i just use an arena allocator instead?
// > actually, obviously better to just allocate and store the pointers in an ArrayList
// not using an ArrayList due to pointer invalidation on reallocation
pub const ExprLinkedList = struct {
    allocator: *Allocator,
    head: ?*Node = null,

    const Node = struct {
        expr: Expr,
        next: ?*Node = null,
    };

    pub fn init(allocator: *Allocator) ExprLinkedList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ExprLinkedList) void {
        while (self.head) |node| {
            self.remove(node);
        }
    }

    /// prepends the node to the start of the list
    pub fn add(self: *ExprLinkedList, expr: Expr) Error!*Expr {
        var new_head = try self.allocator.create(Node);
        new_head.* = Node{ .expr = expr, .next = self.head };
        self.head = new_head;

        return &self.head.?.expr;
    }

    fn remove(self: *ExprLinkedList, node: *Node) void {
        const next_node = node.next;
        self.allocator.destroy(node);
        self.head = next_node;
    }
};

test "ExprLinkedList" {
    var expr_linked_list = ExprLinkedList.init(std.testing.allocator);
    defer expr_linked_list.deinit();

    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .int = 1 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .int = 2 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .float = 34.567 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .string = "wow!" } } });

    try std.testing.expectEqual(@as(i32, 1), expr_linked_list.head.?.next.?.next.?.next.?.expr.literal.value.int);
    try std.testing.expectEqual(@as(i32, 2), expr_linked_list.head.?.next.?.next.?.expr.literal.value.int);
    try std.testing.expectEqual(@as(f32, 34.567), expr_linked_list.head.?.next.?.expr.literal.value.float);
    try std.testing.expectEqualStrings("wow!", expr_linked_list.head.?.expr.literal.value.string);
}

test "ExprLinkedList nested" {
    const AstPrinter = @import("AstPrinter.zig");
    var expr_linked_list = ExprLinkedList.init(std.testing.allocator);
    defer expr_linked_list.deinit();

    const literal_123 = try expr_linked_list.add(.{ .literal = .{ .value = .{ .int = 123 } } });
    const unary_123 = try expr_linked_list.add(.{
        .unary = .{
            .operator = .{ .token_type = .Minus, .lexeme = "-" },
            .right = literal_123,
        },
    });

    const literal_45_67 = try expr_linked_list.add(.{ .literal = .{ .value = .{ .float = 45.67 } } });
    const grouping_45_67 = try expr_linked_list.add(.{ .grouping = .{ .expr = literal_45_67 } });

    const expr = try expr_linked_list.add(.{
        .binary = .{
            .left = unary_123,
            .operator = .{ .token_type = .Star, .lexeme = "*" },
            .right = grouping_45_67,
        },
    });

    const writer = std.io.getStdErr().writer();
    try AstPrinter.parenthesize(expr, writer);
    try writer.writeByte('\n');
}

pub fn init(allocator: *Allocator, tokens: []const Token) Parser {
    return Parser{
        .allocator = allocator,
        .tokens = tokens,
        .exprs = ExprLinkedList.init(allocator),
        .statements = ArrayList(Statement).init(allocator),
    };
}

pub fn deinit(self: *Parser) void {
    for (self.statements.items) |stmt|
        stmt.deinit(self.allocator);

    self.statements.deinit();
    self.exprs.deinit();
}

pub fn parse(self: *Parser) Error![]const Statement {
    while (!self.atEnd())
        try self.statements.append(try self.declaration());

    return self.statements.items;
}

fn declaration(self: *Parser) Error!Statement {
    if (self.matchOne(.Var))
        return self.declStatement();

    return self.statement();
}

fn declStatement(self: *Parser) Error!Statement {
    const identifier = try self.consume(.Identifier, "Expected identifier after var, got {}", .{self.peek()});
    const initialiser = if (self.matchOne(.Equal)) try self.expression() else null;

    _ = try self.consume(.Semicolon, "Expected ';' after variable declaration, got {}", .{self.peek()});
    return Statement{ .decl = .{ .identifier = identifier.lexeme, .initialiser = initialiser } };
}

fn statement(self: *Parser) Error!Statement {
    if (self.matchOne(.Exit)) return self.exitStatement();
    if (self.matchOne(.If)) return self.ifStatement();
    if (self.matchOne(.Print)) return self.printStatement();
    if (self.matchOne(.While)) return self.whileStatement();
    if (self.matchOne(.LeftBrace)) return self.blockStatement();

    return self.exprStatement();
}

fn exitStatement(self: *Parser) Error!Statement {
    _ = try self.consume(.Semicolon, "Expected ';' after exit, got {}", .{self.peek()});
    return Statement.exit;
}

fn ifStatement(self: *Parser) Error!Statement {
    _ = try self.consume(.LeftParen, "Expected '(' after 'if', got {}", .{self.peek()});
    const condition = try self.expression();
    _ = try self.consume(.RightParen, "Expected ')' after if condition, got {}", .{self.peek()});

    const thenBranch = try self.allocator.create(Statement);
    errdefer self.allocator.destroy(thenBranch);
    thenBranch.* = try self.statement();

    var elseBranch: ?*Statement = null;
    if (self.matchOne(.Else)) {
        elseBranch = try self.allocator.create(Statement);
        errdefer self.allocator.destroy(elseBranch.?);
        elseBranch.?.* = try self.statement();
    }

    return Statement{ .if_ = .{
        .condition = condition,
        .thenBranch = thenBranch,
        .elseBranch = elseBranch,
    } };
}

fn printStatement(self: *Parser) Error!Statement {
    const expr = try self.expression();
    _ = try self.consume(.Semicolon, "Expected ';' after value, got {}", .{self.peek()});
    return Statement{ .print = .{ .expr = expr } };
}

fn whileStatement(self: *Parser) Error!Statement {
    _ = try self.consume(.LeftParen, "Expected '(' after 'while', got {}", .{self.peek()});
    const condition = try self.expression();
    _ = try self.consume(.RightParen, "Expected ')' after while condition, got {}", .{self.peek()});

    const body = try self.allocator.create(Statement);
    errdefer self.allocator.destroy(body);
    body.* = try self.statement();

    return Statement{ .while_ = .{ .condition = condition, .body = body } };
}

fn exprStatement(self: *Parser) Error!Statement {
    const expr = try self.expression();
    _ = try self.consume(.Semicolon, "Expected ';' after expression, got {}", .{self.peek()});
    return Statement{ .expr = .{ .expr = expr } };
}

fn blockStatement(self: *Parser) Error!Statement {
    var statements = ArrayList(Statement).init(self.allocator);
    defer statements.deinit();

    while (!self.check(.RightBrace) and !self.atEnd())
        try statements.append(try self.declaration());

    _ = try self.consume(.RightBrace, "Expected '}}' after block, got {}", .{self.peek()});

    return Statement{ .block = .{ .statements = statements.toOwnedSlice() } };
}

fn expression(self: *Parser) Error!*Expr {
    return try self.assignment();
}

fn assignment(self: *Parser) Error!*Expr {
    const expr = try self.or_();

    if (self.matchOne(.Equal)) {
        const equals = self.previous();
        const value = try self.assignment();
        if (expr.* == .variable) {
            const identifier = expr.variable.identifier;
            const right = Expr{ .assign = .{ .identifier = identifier, .value = value } };
            return try self.exprs.add(right);
        }

        reportErr(equals.line, "Invalid assignment target \"{s}\"", .{expr});
    }

    return expr;
}

fn or_(self: *Parser) Error!*Expr {
    var expr = try self.and_();

    while (self.matchOne(.Or)) {
        const logical_expr = Expr{ .logical = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.and_(),
        } };
        expr = try self.exprs.add(logical_expr);
    }

    return expr;
}

fn and_(self: *Parser) Error!*Expr {
    var expr = try self.equality();

    while (self.matchOne(.And)) {
        const logical_expr = Expr{ .logical = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.equality(),
        } };
        expr = try self.exprs.add(logical_expr);
    }

    return expr;
}

fn equality(self: *Parser) Error!*Expr {
    var expr = try self.comparison();

    while (self.match(&[_]Token.Type{ .BangEqual, .EqualEqual })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.comparison(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn comparison(self: *Parser) Error!*Expr {
    var expr = try self.term();

    while (self.match(&[_]Token.Type{ .Greater, .GreaterEqual, .Less, .LessEqual })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.term(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn term(self: *Parser) Error!*Expr {
    var expr = try self.factor();

    while (self.match(&[_]Token.Type{ .Minus, .Plus })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.factor(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn factor(self: *Parser) Error!*Expr {
    var expr = try self.unary();

    while (self.match(&[_]Token.Type{ .Slash, .Star })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.unary(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn unary(self: *Parser) Error!*Expr {
    if (self.match(&[_]Token.Type{ .Bang, .Minus })) {
        const unary_expr = Expr{ .unary = .{
            .operator = self.previous(),
            .right = try self.unary(),
        } };
        return try self.exprs.add(unary_expr);
    }

    return try self.primary();
}

fn primary(self: *Parser) Error!*Expr {
    if (self.match(&[_]Token.Type{ .True, .False, .None, .String, .Integer, .Float }))
        return try self.exprs.add(.{ .literal = .{ .value = self.previous().literal } });

    if (self.matchOne(.Identifier))
        return try self.exprs.add(.{ .variable = .{ .identifier = self.previous() } });

    if (self.matchOne(.LeftParen)) {
        const expr = try self.expression();
        _ = try self.consume(.RightParen, "Expected ')' after expression, got {}", .{self.peek().token_type});
        return try self.exprs.add(.{ .grouping = .{ .expr = expr } });
    }

    try parseError(self.peek(), "Expected expression, got {}.", .{self.peek().token_type});
    unreachable;
}

fn matchOne(self: *Parser, comptime token_type: Token.Type) bool {
    return self.match(&[_]Token.Type{token_type});
}

fn match(self: *Parser, comptime token_types: []const Token.Type) bool {
    for (token_types) |token_type| {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
    }

    return false;
}

fn consume(self: *Parser, token_type: Token.Type, comptime error_msg: []const u8, error_args: anytype) Error!Token {
    if (self.check(token_type)) return self.advance();

    // report error on the next token's line
    try parseError(self.peek(), error_msg, error_args);
    unreachable;
}

fn parseError(token: Token, comptime error_msg: []const u8, error_args: anytype) !void {
    reportErr(token.line, error_msg, error_args);
    return error.ParseError;
}

// not currently used - we don't have statements yet!
fn synchronize(self: *Parser) void {
    self.advance();

    while (!self.atEnd()) {
        if (self.previous() == .Semicolon) return;

        switch (self.peek()) {
            // on statement, hope we're in 'sync'
            .If, .Else, .For, .While, .Print, .Def, .Return => return,
            else => self.advance(),
        }
    }
}

fn check(self: Parser, token_type: Token.Type) bool {
    return !self.atEnd() and self.peek().token_type == token_type;
}

fn advance(self: *Parser) Token {
    if (!self.atEnd())
        self.current_idx += 1;

    return self.previous();
}

fn atEnd(self: Parser) bool {
    return self.peek().token_type == .EndOfFile;
}

fn peek(self: Parser) Token {
    return self.tokens[self.current_idx];
}

fn previous(self: Parser) Token {
    return self.tokens[self.current_idx - 1];
}

test "Parser" {
    const AstPrinter = @import("AstPrinter.zig");
    const tokens = [_]Token{
        Token{ .token_type = .Minus, .lexeme = "-" },
        Token{ .token_type = .Integer, .literal = .{ .int = 123 } },
        Token{ .token_type = .Star, .lexeme = "*" },
        Token{ .token_type = .LeftParen },
        Token{ .token_type = .Float, .literal = .{ .float = 45.67 } },
        Token{ .token_type = .RightParen },
        Token{ .token_type = .EndOfFile },
    };

    var parser = Parser.init(std.testing.allocator, &tokens);
    defer parser.deinit();

    const expr = try parser.parse();

    std.debug.print("{}\n", .{expr});

    const writer = std.io.getStdErr().writer();
    try AstPrinter.parenthesize(expr, writer);
    try writer.writeByte('\n');
}
