const std = @import("std");
const lexer = @import("lexer.zig");

pub const Root = union(enum) {
    const Self = @This();

    declaration: Declaration,

    pub fn deinit(self: Self) void {
        switch (self) {
            .declaration => |declaration| declaration.deinit(),
        }
    }
};

pub const Declaration = struct {
    const Self = @This();

    exported: bool,
    type: VariableType,
    name: []const u21,
    expression: Expression,

    pub fn deinit(self: *const Self) void {
        self.expression.deinit();
    }
};

pub const VariableType = enum {
    constant,
    immutable,
    variable,
};

pub const Expression = union(enum) {
    const Self = @This();

    function: Function,
    identifier: []const u21,
    addition: Addition,

    pub fn fromBinaryOperator(allocator: std.mem.Allocator, lhs_data: Expression, op: lexer.TokenType, rhs_data: Expression) !Self {
        const lhs = try allocator.create(Expression);
        errdefer allocator.destroy(lhs);
        lhs.* = lhs_data;

        const rhs = try allocator.create(Expression);
        errdefer allocator.destroy(rhs);
        rhs.* = rhs_data;

        return switch (op) {
            .Plus => .{ .addition = .{ .allocator = allocator, .lhs = lhs, .rhs = rhs } },
            else => unreachable,
        };
    }

    pub fn deinit(self: Self) void {
        switch (self) {
            .function => |function| function.deinit(),
            .identifier => {},
            .addition => |addition| addition.deinit(),
        }
    }
};

pub const Addition = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    lhs: *Expression,
    rhs: *Expression,

    pub fn deinit(self: *const Self) void {
        self.lhs.deinit();
        self.rhs.deinit();

        self.allocator.destroy(self.lhs);
        self.allocator.destroy(self.rhs);
    }
};

pub const Function = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parameters: []Parameter,
    return_type: *const Expression,
    block: Block,

    pub fn deinit(self: *const Self) void {
        for (self.parameters) |param| {
            param.deinit();
        }

        self.allocator.free(self.parameters);
        self.allocator.destroy(self.return_type);
        self.block.deinit();
    }
};

pub const Parameter = struct {
    const Self = @This();

    name: []const u21,
    type: Expression,

    pub fn deinit(self: *const Self) void {
        self.type.deinit();
    }
};

pub const Statement = union(enum) {
    const Self = @This();

    declaration: Declaration,
    expression: Expression,
    @"return": Expression,

    pub fn deinit(self: Self) void {
        switch (self) {
            .declaration => |declaration| declaration.deinit(),
            .expression => |expression| expression.deinit(),
            .@"return" => |ret| ret.deinit(),
        }
    }

    pub fn hasSemicolon(self: Self) bool {
        return switch (self) {
            .declaration, .expression, .@"return" => true,
        };
    }
};

pub const Block = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    statements: []Statement,

    pub fn deinit(self: *const Self) void {
        for (self.statements) |statement| {
            statement.deinit();
        }

        self.allocator.free(self.statements);
    }
};

pub const PrecedenceLevel = enum {
    const Self = @This();

    addition,
    multiplication,
    functionCall,

    pub fn fromToken(token: lexer.TokenType) ?Self {
        return switch (token) {
            .Plus => .addition,
            .Division => .multiplication,
            .Period => .functionCall,
            else => null,
        };
    }
};

fn isRightAssociative(token: lexer.TokenType) bool {
    return switch (token) {
        else => false,
    };
}

pub fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) ![]Root {
    return Parser.parse(allocator, tokens);
}

fn optional(T: type, val: anyerror!T) !?T {
    if (val) |v| {
        return v;
    } else |err| {
        if (err != error.invalidInput) {
            return err;
        }
    }

    return null;
}

const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tokens: []lexer.Token,
    i: usize = 0,
    stack: std.ArrayList(usize),

    fn deinit(self: *const Self) void {
        self.stack.deinit();
    }

    fn peek(self: *Self) ?lexer.Token {
        if (self.i >= self.tokens.len) {
            return null;
        }

        return self.tokens[self.i];
    }

    fn consume(self: *Self, token_type: lexer.TokenType) !lexer.Token {
        return self.optionalConsume(token_type) orelse error.invalidInput;
    }

    fn optionalConsume(self: *Self, token_type: lexer.TokenType) ?lexer.Token {
        if (self.i >= self.tokens.len) {
            return null;
        }

        const token = self.tokens[self.i];
        if (token.token_type == token_type) {
            self.i += 1;
            return token;
        }

        return null;
    }

    fn oneOf(self: *Self, comptime tokens: []const lexer.TokenType) !lexer.Token.MatchedType(tokens) {
        return self.optionalOneOf(tokens) orelse error.invalidInput;
    }

    fn optionalOneOf(self: *Self, comptime tokens: []const lexer.TokenType) ?lexer.Token.MatchedType(tokens) {
        if (self.i >= self.tokens.len) {
            return null;
        }

        const token = self.tokens[self.i];
        if (token.match(tokens)) |matched| {
            self.i += 1;
            return matched;
        }

        return null;
    }

    fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) ![]Root {
        var self = Self{
            .allocator = allocator,
            .tokens = tokens,
            .stack = std.ArrayList(usize).init(allocator),
        };
        defer self.deinit();
        errdefer std.debug.print("ended at {}: {any}", .{ self.i, self.tokens[self.i] });

        var roots = std.ArrayList(Root).init(self.allocator);
        errdefer {
            for (roots.items) |root| {
                root.deinit();
            }

            roots.deinit();
        }

        while (try self.parseRoot()) |root| {
            try roots.append(root);
        }

        return roots.toOwnedSlice();
    }

    fn enter(self: *Self) !void {
        try self.stack.append(self.i);
    }

    fn rollback(self: *Self) void {
        self.i = self.stack.pop();
    }

    fn parseRoot(self: *Self) !?Root {
        if (self.i >= self.tokens.len) {
            return null;
        }

        try self.enter();
        errdefer self.rollback();

        if (try optional(Declaration, self.parseDeclaration())) |decl| {
            return .{ .declaration = decl };
        }

        return error.invalidInput;
    }

    fn parseDeclaration(self: *Self) !Declaration {
        try self.enter();
        errdefer self.rollback();

        const exported = if (self.optionalConsume(.Export)) |_| true else false;

        const variable_type: VariableType = switch ((try self.oneOf(&.{.Const})).token_type) {
            .Const => .constant,
        };

        const name = (try self.consume(.Ident)).source;
        _ = try self.consume(.Equal);
        const expression = try self.parseExpression();
        _ = try self.consume(.Semicolon);

        return .{
            .exported = exported,
            .type = variable_type,
            .name = name,
            .expression = expression,
        };
    }

    fn parseExpression(self: *Self) !Expression {
        return try self.parseExpressionRecursive(try self.parseExpressionPrime(), null);
    }

    fn parseExpressionRecursive(self: *Self, input: Expression, precedence_level: ?PrecedenceLevel) !Expression {
        try self.enter();
        errdefer self.rollback();

        const precedende_level_value = if (precedence_level) |pl| @intFromEnum(pl) else 0;

        var lookahead_val = self.peek();
        var lhs = input;
        errdefer lhs.deinit();

        while (lookahead_val) |lookahead| {
            const next_precedence_level = @intFromEnum(PrecedenceLevel.fromToken(lookahead.token_type) orelse break);
            if (next_precedence_level < precedende_level_value) {
                break;
            }

            const operator = lookahead;
            self.i += 1;
            var rhs = try self.parseExpressionPrime();
            errdefer rhs.deinit();

            lookahead_val = self.peek();
            while (lookahead_val) |rhs_lookahead| {
                const rhs_precedence_level = @intFromEnum(PrecedenceLevel.fromToken(rhs_lookahead.token_type) orelse break);
                if (!(rhs_precedence_level > next_precedence_level or (isRightAssociative(rhs_lookahead.token_type) and rhs_precedence_level == next_precedence_level))) {
                    break;
                }

                const change: u8 = if (rhs_precedence_level > next_precedence_level) 1 else 0;
                const next_precedence: PrecedenceLevel = @enumFromInt(next_precedence_level + change);
                rhs = try self.parseExpressionRecursive(rhs, next_precedence);
                lookahead_val = self.peek();
            }

            lhs = try Expression.fromBinaryOperator(self.allocator, lhs, operator.token_type, rhs);
        }

        return lhs;
    }

    fn parseExpressionPrime(self: *Self) !Expression {
        try self.enter();
        errdefer self.rollback();

        if (try optional(Function, self.parseFunction())) |function| {
            return .{ .function = function };
        }

        if (self.optionalConsume(.Ident)) |identifier| {
            return .{ .identifier = identifier.source };
        }

        return error.invalidInput;
    }

    fn parseFunction(self: *Self) !Function {
        try self.enter();
        errdefer self.rollback();

        _ = try self.consume(.Func);
        _ = try self.consume(.LParen);
        const parameters = try self.parseParameters();
        errdefer {
            for (parameters) |parameter| {
                parameter.deinit();
            }

            self.allocator.free(parameters);
        }

        _ = try self.consume(.RParen);
        const return_type = try self.parseExpression();

        const return_type_ptr = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(return_type_ptr);
        return_type_ptr.* = return_type;

        const block = try self.parseBlock();

        return .{
            .allocator = self.allocator,
            .parameters = parameters,
            .return_type = return_type_ptr,
            .block = block,
        };
    }

    fn parseParameters(self: *Self) ![]Parameter {
        try self.enter();
        errdefer self.rollback();

        var parameters = std.ArrayList(Parameter).init(self.allocator);
        errdefer {
            for (parameters.items) |parameter| {
                parameter.deinit();
            }

            parameters.deinit();
        }

        while (try optional(Parameter, self.parseParameter())) |parameter| {
            try parameters.append(parameter);

            if (self.optionalConsume(.Comma) == null) {
                break;
            }
        }

        return parameters.toOwnedSlice();
    }

    fn parseParameter(self: *Self) !Parameter {
        try self.enter();
        errdefer self.rollback();

        const name = try self.consume(.Ident);
        _ = try self.consume(.Colon);
        const parameter_type = try self.parseExpression();

        return .{
            .name = name.source,
            .type = parameter_type,
        };
    }

    fn parseBlock(self: *Self) !Block {
        try self.enter();
        errdefer self.rollback();

        var statements = std.ArrayList(Statement).init(self.allocator);
        errdefer {
            for (statements.items) |statement| {
                statement.deinit();
            }

            statements.deinit();
        }

        _ = try self.consume(.LBrace);

        while (try optional(Statement, self.parseStatement())) |statement| {
            try statements.append(statement);
        }

        _ = try self.consume(.RBrace);

        return .{
            .allocator = self.allocator,
            .statements = try statements.toOwnedSlice(),
        };
    }

    fn parseStatement(self: *Self) !Statement {
        try self.enter();
        errdefer self.rollback();

        const statement: Statement = blk: {
            if (try optional(Declaration, self.parseDeclaration())) |declaration| {
                break :blk .{ .declaration = declaration };
            }

            if (try optional(Expression, self.parseExpression())) |expression| {
                break :blk .{ .expression = expression };
            }

            if (try optional(Statement, self.parseReturnStatement())) |statement| {
                break :blk statement;
            }

            return error.invalidInput;
        };

        if (statement.hasSemicolon()) {
            _ = try self.consume(.Semicolon);
        }

        return statement;
    }

    fn parseReturnStatement(self: *Self) !Statement {
        try self.enter();
        errdefer self.rollback();

        _ = try self.consume(.Return);
        return .{ .@"return" = try self.parseExpression() };
    }
};
