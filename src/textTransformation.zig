const std = @import("std");

pub fn htmlToText(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var in_tag = false;
    var in_script = false;
    var in_style = false;

    while (i < html.len) {
        if (html[i] == '<') {
            in_tag = true;
            if (i + 7 <= html.len and std.mem.eql(u8, html[i .. i + 7], "<script")) {
                in_script = true;
            } else if (i + 6 <= html.len and std.mem.eql(u8, html[i .. i + 6], "<style")) {
                in_style = true;
            } else if (i + 9 <= html.len and std.mem.eql(u8, html[i .. i + 9], "</script>")) {
                in_script = false;
                i += 8;
            } else if (i + 8 <= html.len and std.mem.eql(u8, html[i .. i + 8], "</style>")) {
                in_style = false;
                i += 7;
            } else if ((i + 3 <= html.len and std.mem.eql(u8, html[i .. i + 3], "<br")) or
                (i + 3 <= html.len and std.mem.eql(u8, html[i .. i + 3], "<p>")) or
                (i + 4 <= html.len and std.mem.eql(u8, html[i .. i + 4], "<div")))
            {
                try result.append(allocator, '\n');
            }
            i += 1;
            continue;
        } else if (html[i] == '>') {
            in_tag = false;
            i += 1;
            continue;
        }

        if (!in_tag and !in_script and !in_style) {
            try result.append(allocator, html[i]);
        }
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

test "htmlToText - simple text" {
    const allocator = std.testing.allocator;
    const html = "<p>Hello World</p>";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\nHello World", text);
}

test "htmlToText - strips script tags" {
    const allocator = std.testing.allocator;
    const html = "<p>Before</p><script>alert('test');</script><p>After</p>";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\nBefore\nAfter", text);
}

test "htmlToText - strips style tags" {
    const allocator = std.testing.allocator;
    const html = "<style>body { color: red; }</style><p>Content</p>";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\nContent", text);
}

test "htmlToText - handles br tags" {
    const allocator = std.testing.allocator;
    const html = "Line 1<br>Line 2<br/>Line 3";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Line 1\nLine 2\nLine 3", text);
}

test "htmlToText - handles div tags" {
    const allocator = std.testing.allocator;
    const html = "<div>First</div><div class='test'>Second</div>";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\nFirst\nSecond", text);
}

test "htmlToText - complex html" {
    const allocator = std.testing.allocator;
    const html =
        \\<html>
        \\<head><style>body { margin: 0; }</style></head>
        \\<body>
        \\<p>Hello</p>
        \\<script>console.log('test');</script>
        \\<div>World</div>
        \\</body>
        \\</html>
    ;
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\n\n\n\nHello\n\nWorld\n\n", text);
}

test "htmlToText - empty string" {
    const allocator = std.testing.allocator;
    const html = "";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("", text);
}

test "htmlToText - plain text" {
    const allocator = std.testing.allocator;
    const html = "Just plain text";
    const text = try htmlToText(allocator, html);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Just plain text", text);
}
