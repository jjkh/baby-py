source: []const u8,
tokens: std.ArrayList(Token),
start_idx: usize = 0,
current_idx: usize = 0,
line: usize = 0,

const Scanner = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;

const reportErr = @import("root").reportErr;
const Token = @import("Token.zig");
const Expr = @import("expr.zig").Expr;

pub fn init(allocator: *Allocator, source: []const u8) Scanner {
    return Scanner{
        .source = source,
        .tokens = std.ArrayList(Token).init(allocator),
    };
}

pub fn deinit(self: Scanner) void {
    self.tokens.deinit();
}

fn atEnd(self: Scanner) bool {
    return self.current_idx >= self.source.len;
}

pub fn scanTokens(self: *Scanner) !void {
    while (!self.atEnd()) {
        self.start_idx = self.current_idx;
        try self.scanToken();
    }

    try self.tokens.append(.{
        .token_type = .EndOfFile,
        .line = self.line,
    });
}

fn scanToken(self: *Scanner) !void {
    const char = self.advance();
    switch (char) {
        '(' => try self.addToken(.{ .token_type = .LeftParen }),
        ')' => try self.addToken(.{ .token_type = .RightParen }),
        '{' => try self.addToken(.{ .token_type = .LeftBrace }),
        '}' => try self.addToken(.{ .token_type = .RightBrace }),
        ',' => try self.addToken(.{ .token_type = .Comma }),
        '.' => try self.addToken(.{ .token_type = .Dot }),
        '-' => try self.addToken(.{ .token_type = .Minus }),
        '+' => try self.addToken(.{ .token_type = .Plus }),
        ';' => try self.addToken(.{ .token_type = .Semicolon }),
        ':' => try self.addToken(.{ .token_type = .Colon }),
        '*' => try self.addToken(.{ .token_type = .Star }),
        '!' => try self.addToken(.{ .token_type = if (self.match('=')) .BangEqual else .Bang }),
        '=' => try self.addToken(.{ .token_type = if (self.match('=')) .EqualEqual else .Equal }),
        '<' => try self.addToken(.{ .token_type = if (self.match('=')) .LessEqual else .Less }),
        '>' => try self.addToken(.{ .token_type = if (self.match('=')) .GreaterEqual else .Greater }),
        '/' => {
            if (self.match('/')) {
                // comment goes until the end of the line
                while (!self.atEnd() and self.peek() != '\n') _ = self.advance();
            } else {
                try self.addToken(.{ .token_type = .Slash });
            }
        },
        '"' => try self.readString(),
        '0' => switch (self.peek()) {
            'x' => if (isHexDigit(self.peekNext())) try self.readHexInt(),
            'b' => if (isBinDigit(self.peekNext())) try self.readBinInt(),
            else => try self.readNumber(),
        },
        '1'...'9' => try self.readNumber(),
        'a'...'z', 'A'...'Z', '_' => try self.readIdentifier(),
        ' ', '\r', '\t' => {},
        '\n' => self.line += 1,
        else => reportErr(self.line, "Unexpected character '{c}'.", .{char}),
    }
}

fn peek(self: Scanner) u8 {
    if (self.atEnd())
        return 0;

    return self.source[self.current_idx];
}

fn peekNext(self: Scanner) u8 {
    if (self.current_idx > self.source.len)
        return 0;

    return self.source[self.current_idx + 1];
}

fn advance(self: *Scanner) u8 {
    const current_char = self.source[self.current_idx];

    self.current_idx += 1;
    return current_char;
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.atEnd())
        return false;

    if (self.source[self.current_idx] != expected)
        return false;

    self.current_idx += 1;
    return true;
}

fn readString(self: *Scanner) !void {
    while (!self.atEnd() and self.peek() != '"' and self.peek() != '\n')
        _ = self.advance();

    if (self.atEnd() or self.peek() == '\n') {
        reportErr(self.line, "Unterminated string.", .{});
        return;
    }

    _ = self.advance(); // closing '"'

    try self.addToken(.{
        .token_type = .String,
        .literal = .{ .string = self.source[self.start_idx + 1 .. self.current_idx - 1] },
    });
}

fn isHexDigit(char: u8) bool {
    return (char >= '0' and char <= 'F') or (char >= 'a' and char <= 'f');
}

fn isBinDigit(char: u8) bool {
    return char == '0' or char == '1';
}

fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}

fn isValidIdentifierChar(char: u8) bool {
    return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or char == '_';
}

fn readNumber(self: *Scanner) !void {
    while (isDigit(self.peek()))
        _ = self.advance();

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();

        while (isDigit(self.peek()))
            _ = self.advance();

        try self.addToken(.{
            .token_type = .Float,
            .literal = .{ .float = try std.fmt.parseFloat(f32, self.source[self.start_idx..self.current_idx]) },
        });
    } else {
        try self.addToken(.{
            .token_type = .Integer,
            .literal = .{ .int = try std.fmt.parseInt(i32, self.source[self.start_idx..self.current_idx], 10) },
        });
    }
}

fn readHexInt(self: *Scanner) !void {
    // leading 'x'
    _ = self.advance();

    while (isHexDigit(self.peek()))
        _ = self.advance();

    if (self.peek() == '.') {
        _ = self.advance();
        while (isHexDigit(self.peek()))
            _ = self.advance();

        reportErr(self.line, "Invalid period in hex literal.", .{});
        return;
    }

    try self.addToken(.{
        .token_type = .Integer,
        .literal = .{ .int = try std.fmt.parseInt(i32, self.source[self.start_idx + 2 .. self.current_idx], 16) },
    });
}

fn readBinInt(self: *Scanner) !void {
    // leading 'b'
    _ = self.advance();

    while (isBinDigit(self.peek()))
        _ = self.advance();

    if (self.peek() == '.') {
        _ = self.advance();
        while (isBinDigit(self.peek()))
            _ = self.advance();

        reportErr(self.line, "Invalid period in bin literal.", .{});
        return;
    }

    try self.addToken(.{
        .token_type = .Integer,
        .literal = .{ .int = try std.fmt.parseInt(i32, self.source[self.start_idx + 2 .. self.current_idx], 2) },
    });
}

fn readIdentifier(self: *Scanner) !void {
    while (isValidIdentifierChar(self.peek()))
        _ = self.advance();

    const identifier = self.source[self.start_idx..self.current_idx];
    const token_type = Token.KeywordMap.get(identifier) orelse .Identifier;
    const literal: Token.Literal = switch (token_type) {
        .True => .{ .bool = true },
        .False => .{ .bool = false },
        else => .none,
    };

    try self.addToken(.{ .literal = literal, .token_type = token_type });
}

fn addToken(self: *Scanner, token: Token) !void {
    try self.tokens.append(.{
        .token_type = token.token_type,
        .literal = token.literal,
        .lexeme = self.source[self.start_idx..self.current_idx],
        .line = self.line,
    });
}
