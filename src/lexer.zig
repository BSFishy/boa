const lexer = @import("lexer");

pub const Diagnostics = lexer.Diagnostics;
pub const Lexer = lexer.Lexer(.{
    .Comment = .{ .pattern = "//([^\n])*" },

    // operators
    .Division = .{ .pattern = "/" },
    .Plus = .{ .pattern = "\\+" },

    // punctuation
    .Equal = .{ .pattern = "=" },
    .LParen = .{ .pattern = "\\(" },
    .RParen = .{ .pattern = "\\)" },
    .Colon = .{ .pattern = ":" },
    .Comma = .{ .pattern = "," },
    .LBrace = .{ .pattern = "{" },
    .RBrace = .{ .pattern = "}" },
    .Semicolon = .{ .pattern = ";" },

    // keywords
    .Func = .{ .pattern = "fn" },
    .Pub = .{ .pattern = "pub" },
    .Const = .{ .pattern = "const" },
    .Return = .{ .pattern = "return" },
    .Export = .{ .pattern = "export" },

    // literal values
    .String = .{ .pattern = "\"([^\"]|\\\\\")*\"" },

    // misc
    .Newline = .{ .pattern = "(\n|\r\n)", .skip = true },
    .Space = .{ .pattern = " ", .skip = true },

    // special values
    .Ident = .{ .pattern = "\\w\\W*" },
});

pub const Token = Lexer.Token;
pub const TokenType = Lexer.TokenType;
