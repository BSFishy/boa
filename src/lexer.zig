const lexer = @import("lexer");

pub const Diagnostics = lexer.Diagnostics;
pub const Lexer = lexer.Lexer(&token_patterns);

pub const Token = Lexer.Token;
pub const TokenType = Lexer.TokenType;

const token_patterns = [_]lexer.TokenPattern{
    .{ .name = "Comment", .pattern = "//([^\n])*" },

    // operators
    .{ .name = "Division", .pattern = "/" },
    .{ .name = "Plus", .pattern = "\\+" },

    // punctuation
    .{ .name = "Equal", .pattern = "=" },
    .{ .name = "LParen", .pattern = "\\(" },
    .{ .name = "RParen", .pattern = "\\)" },
    .{ .name = "Colon", .pattern = ":" },
    .{ .name = "Comma", .pattern = "," },
    .{ .name = "LBrace", .pattern = "{" },
    .{ .name = "RBrace", .pattern = "}" },
    .{ .name = "Semicolon", .pattern = ";" },

    // keywords
    .{ .name = "Func", .pattern = "fn" },
    .{ .name = "Pub", .pattern = "pub" },
    .{ .name = "Const", .pattern = "const" },
    .{ .name = "Return", .pattern = "return" },

    // literal values
    .{ .name = "String", .pattern = "\"([^\"]|\\\\\")*\"" },

    // misc
    .{ .name = "Newline", .pattern = "(\n|\r\n)" },
    .{ .name = "Space", .pattern = " " },

    // special values
    .{ .name = "Ident", .pattern = "\\w\\W*" },
};
