const Allocator = @import("std").mem.Allocator;
const Expr = @import("expr.zig").Expr;
const returnType = @import("util.zig").returnType;

pub const Statement = union(enum) {
    expr: ExprStatement,
    print: PrintStatement,
    exit: void,
    decl: DeclStatement,
    block: BlockStatement,
    if_: IfStatement,
    while_: WhileStatement,

    pub const ExprStatement = struct { expr: *const Expr };
    pub const PrintStatement = struct { expr: *const Expr };
    pub const DeclStatement = struct { identifier: []const u8, initialiser: ?*const Expr };
    pub const BlockStatement = struct {
        statements: []const Statement,

        pub fn deinit(self: BlockStatement, allocator: *Allocator) void {
            for (self.statements) |stmt|
                stmt.deinit(allocator);

            allocator.free(self.statements);
        }
    };
    pub const IfStatement = struct {
        condition: *const Expr,
        thenBranch: *const Statement,
        elseBranch: ?*const Statement,

        pub fn deinit(self: IfStatement, allocator: *Allocator) void {
            self.thenBranch.deinit(allocator);
            allocator.destroy(self.thenBranch);

            if (self.elseBranch) |elseBranch| {
                elseBranch.deinit(allocator);
                allocator.destroy(elseBranch);
            }
        }
    };
    pub const WhileStatement = struct {
        condition: *const Expr,
        body: *const Statement,

        pub fn deinit(self: WhileStatement, allocator: *Allocator) void {
            self.body.deinit(allocator);
            allocator.destroy(self.body);
        }
    };

    pub fn visit(self: Statement, visitor: anytype, args: anytype) returnType(visitor.visitExprStatement) {
        return switch (self) {
            .expr => |stmt| visitor.visitExprStatement(stmt, args),
            .print => |stmt| visitor.visitPrintStatement(stmt, args),
            .exit => |stmt| visitor.visitExitStatement(stmt, args),
            .decl => |stmt| visitor.visitDeclStatement(stmt, args),
            .block => |stmt| visitor.visitBlockStatement(stmt, args),
            .if_ => |stmt| visitor.visitIfStatement(stmt, args),
            .while_ => |stmt| visitor.visitWhileStatement(stmt, args),
        };
    }

    pub fn deinit(self: Statement, allocator: *Allocator) void {
        switch (self) {
            .block => |stmt| stmt.deinit(allocator),
            .if_ => |stmt| stmt.deinit(allocator),
            .while_ => |stmt| stmt.deinit(allocator),
            else => {},
        }
    }
};
