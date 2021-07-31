const Expr = @import("expr.zig").Expr;
const returnType = @import("util.zig").returnType;

pub const Statement = union(enum) {
    expr: ExprStatement,
    print: PrintStatement,
    exit: void,
    decl: DeclStatement,

    pub const ExprStatement = struct { expr: *const Expr };
    pub const PrintStatement = struct { expr: *const Expr };
    pub const DeclStatement = struct { identifier: []const u8, initialiser: ?*const Expr };

    pub fn visit(self: Statement, visitor: anytype, args: anytype) returnType(visitor.visitExprStatement) {
        return switch (self) {
            .expr => |stmt| visitor.visitExprStatement(stmt, args),
            .print => |stmt| visitor.visitPrintStatement(stmt, args),
            .exit => |stmt| visitor.visitExitStatement(stmt, args),
            .decl => |stmt| visitor.visitDeclStatement(stmt, args),
        };
    }
};
