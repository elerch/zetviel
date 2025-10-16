const std = @import("std");
const gmime = @import("c.zig").c;
const textTransformation = @import("textTransformation.zig");

const Self = @This();

initialized: bool = false,

pub fn init() Self {
    // We'll initialize on first use...
    //gmime.g_mime_init();
    return .{};
}

pub fn deinit(self: Self) void {
    if (self.initialized) gmime.g_mime_shutdown();
}

/// Initializes gmime if not already initialized
fn gmimeInit(self: *Self) void {
    if (!self.initialized) {
        gmime.g_mime_init();
        self.initialized = true;
    }
}

pub fn openMessage(self: *Self, filename: [:0]const u8) !Message {
    // TODO: remove the :0
    self.gmimeInit();
    // Open the file as a GMime stream
    const stream = gmime.g_mime_stream_fs_open(filename.ptr, gmime.O_RDONLY, 0o0644, null) orelse {
        std.log.err("Failed to open message file: {s}", .{filename});
        return error.FileOpenFailed;
    };
    defer gmime.g_object_unref(stream);

    // Create a parser for the stream
    const parser = gmime.g_mime_parser_new_with_stream(stream) orelse
        return error.ParserCreationFailed;
    defer gmime.g_object_unref(parser);

    // Parse the message
    const message = gmime.g_mime_parser_construct_message(parser, null) orelse
        return error.MessageParsingFailed;

    return .{
        .filename = filename,
        .message = message,
    };
}

// Message representation for MIME parsing
pub const Message = struct {
    //     allocator: std.mem.Allocator,
    filename: [:0]const u8, // do we need this?
    message: *gmime.GMimeMessage,

    pub fn deinit(self: Message) void {
        gmime.g_object_unref(self.message);
    }

    // From gmime README: https://github.com/jstedfast/gmime
    // MIME does define a set of general rules for how mail clients should
    // interpret this tree structure of MIME parts. The Content-Disposition
    // header is meant to provide hints to the receiving client as to which
    // parts are meant to be displayed as part of the message body and which
    // are meant to be interpreted as attachments.
    //
    // The Content-Disposition header will generally have one of two values:
    // inline or attachment.

    // The meaning of these value should be fairly obvious. If the value
    // is attachment, then the content of said MIME part is meant to be
    // presented as a file attachment separate from the core message.
    // However, if the value is inline, then the content of that MIME part
    // is meant to be displayed inline within the mail client's rendering
    // of the core message body.
    //
    // If the Content-Disposition header does not exist, then it should be
    // treated as if the value were inline.
    //
    // Technically, every part that lacks a Content-Disposition header or
    // that is marked as inline, then, is part of the core message body.
    //
    // There's a bit more to it than that, though.
    //
    // Modern MIME messages will often contain a multipart/alternative MIME
    // container which will generally contain a text/plain and text/html
    // version of the text that the sender wrote. The text/html version
    // is typically formatted much closer to what the sender saw in his or
    // her WYSIWYG editor than the text/plain version.
    //
    // Example without multipart/related:
    // multipart/alternative
    //  text/plain
    //  text/html
    //
    // Example with:
    // multipart/alternative
    //   text/plain
    //   multipart/related
    //     text/html
    //     image/jpeg
    //     video/mp4
    //     image/png
    //
    // multipart/mixed (html/text only, with attachments)
    // text/html - html only
    // text/plain - text only
    //
    // It might be worth constructing a mime tree in zig that is constructed by traversing all
    // this stuff in GMime once, getting all the things we need in Zig land, and
    // the rest could be much easier from there

    const Attachment = struct {};

    // Helper function to find HTML content in a multipart container
    fn findHtmlInMultipart(multipart: *gmime.GMimeMultipart, allocator: std.mem.Allocator) !?[]const u8 {
        const mpgc = gmime.g_mime_multipart_get_count(multipart);
        if (mpgc == -1) return error.NoMultipartCount;
        const count: usize = @intCast(mpgc);

        // std.debug.print("\n\nCount: {}\n", .{count});
        // Look for HTML part first (preferred in multipart/alternative)
        for (0..count) |i| {
            const part = gmime.g_mime_multipart_get_part(multipart, @intCast(i));
            if (part == null) continue;

            const part_content_type = gmime.g_mime_object_get_content_type(part);
            if (part_content_type == null) continue;

            const part_mime_type = gmime.g_mime_content_type_get_mime_type(part_content_type);
            if (part_mime_type == null) continue;
            defer gmime.g_free(part_mime_type);
            // std.debug.print("Mime type: {s}\n", .{std.mem.span(part_mime_type)});

            // subtype is "html", but mime type is "text/html", so we don't need this
            // const part_mime_subtype = gmime.g_mime_content_type_get_media_subtype(part_content_type);
            // if (part_mime_subtype == null) continue;
            // std.debug.print("Media subtype type: {s}\n", .{std.mem.span(part_mime_subtype)});

            // Check if this is text/html
            if (std.mem.eql(u8, std.mem.span(part_mime_type), "text/html")) {
                // Try to get the text content
                if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(part)), gmime.g_mime_text_part_get_type()) != 0) {
                    const text_part: *gmime.GMimeTextPart = @ptrCast(part);
                    const text = gmime.g_mime_text_part_get_text(text_part);
                    if (text != null) {
                        defer gmime.g_free(text);
                        return try allocator.dupe(u8, std.mem.span(text));
                    }
                }
            }
        }

        // If no HTML found, check for nested multiparts (like multipart/related inside multipart/alternative)
        // TODO: Test this code path
        for (0..count) |i| {
            const part = gmime.g_mime_multipart_get_part(multipart, @intCast(i));
            if (part == null) continue;

            if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(part)), gmime.g_mime_multipart_get_type()) != 0) {
                const nested_multipart: *gmime.GMimeMultipart = @ptrCast(part);
                if (try findHtmlInMultipart(nested_multipart, allocator)) |content|
                    return content;
            }
        }

        std.log.debug("No HTML Multipart found", .{});
        return null;
    }

    fn findTextInMultipart(multipart: *gmime.GMimeMultipart, allocator: std.mem.Allocator) !?[]const u8 {
        const mpgc = gmime.g_mime_multipart_get_count(multipart);
        if (mpgc == -1) return error.NoMultipartCount;
        const count: usize = @intCast(mpgc);

        for (0..count) |i| {
            const part = gmime.g_mime_multipart_get_part(multipart, @intCast(i));
            if (part == null) continue;

            const part_content_type = gmime.g_mime_object_get_content_type(part);
            if (part_content_type == null) continue;

            const part_mime_type = gmime.g_mime_content_type_get_mime_type(part_content_type);
            if (part_mime_type == null) continue;
            defer gmime.g_free(part_mime_type);

            if (std.mem.eql(u8, std.mem.span(part_mime_type), "text/plain")) {
                if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(part)), gmime.g_mime_text_part_get_type()) != 0) {
                    const text_part: *gmime.GMimeTextPart = @ptrCast(part);
                    const text = gmime.g_mime_text_part_get_text(text_part);
                    if (text != null) {
                        defer gmime.g_free(text);
                        return try allocator.dupe(u8, std.mem.span(text));
                    }
                }
            }
        }

        for (0..count) |i| {
            const part = gmime.g_mime_multipart_get_part(multipart, @intCast(i));
            if (part == null) continue;

            if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(part)), gmime.g_mime_multipart_get_type()) != 0) {
                const nested_multipart: *gmime.GMimeMultipart = @ptrCast(part);
                if (try findTextInMultipart(nested_multipart, allocator)) |content|
                    return content;
            }
        }

        return null;
    }

    pub fn rawBody(self: Message, allocator: std.mem.Allocator) ![]const u8 {
        // Get the message body using GMime
        const body = gmime.g_mime_message_get_body(self.message);
        if (body == null) return error.NoMessageBody;

        // Check if it's a multipart message
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_multipart_get_type()) != 0) {
            const multipart: *gmime.GMimeMultipart = @ptrCast(body);

            // Try to find HTML content in the multipart
            if (try findHtmlInMultipart(multipart, allocator)) |html_content| {
                // Trim trailing whitespace and newlines to match expected format
                return html_content;
            }
        }

        // If it's not multipart or we didn't find HTML, check if it's a single text part
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_text_part_get_type()) != 0) {
            const text_part: *gmime.GMimeTextPart = @ptrCast(body);
            const text = gmime.g_mime_text_part_get_text(text_part);
            if (text != null) {
                defer gmime.g_free(text);
                const content = try allocator.dupe(u8, std.mem.span(text));
                return content;
            }
        }

        // Fallback: convert the entire body to string
        const body_string = gmime.g_mime_object_to_string(body, null);
        if (body_string == null) return error.BodyConversionFailed;

        defer gmime.g_free(body_string);
        return try allocator.dupe(u8, std.mem.span(body_string));
    }

    pub fn getContent(self: Message, allocator: std.mem.Allocator) !struct { content: []const u8, content_type: []const u8 } {
        const body = gmime.g_mime_message_get_body(self.message);
        if (body == null) return error.NoMessageBody;

        // Check if it's a multipart message
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_multipart_get_type()) != 0) {
            const multipart: *gmime.GMimeMultipart = @ptrCast(body);
            if (try findHtmlInMultipart(multipart, allocator)) |html_content| {
                return .{ .content = html_content, .content_type = "text/html" };
            }
        }

        // Check if it's a single text part
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_text_part_get_type()) != 0) {
            const text_part: *gmime.GMimeTextPart = @ptrCast(body);
            const text = gmime.g_mime_text_part_get_text(text_part);
            if (text != null) {
                defer gmime.g_free(text);
                const content = try allocator.dupe(u8, std.mem.span(text));
                const content_type_obj = gmime.g_mime_object_get_content_type(body);
                const mime_type = if (content_type_obj != null)
                    gmime.g_mime_content_type_get_mime_type(content_type_obj)
                else
                    null;
                const ct = if (mime_type != null) std.mem.span(mime_type) else "text/plain";
                return .{ .content = content, .content_type = ct };
            }
        }

        return error.NoTextContent;
    }

    pub fn getTextAndHtmlBodyVersions(self: Message, allocator: std.mem.Allocator) !struct { text: []const u8, html: []const u8 } {
        const body = gmime.g_mime_message_get_body(self.message);
        if (body == null) return error.NoMessageBody;

        var text_content: ?[]const u8 = null;
        var html_content: ?[]const u8 = null;

        // Check if it's a multipart message
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_multipart_get_type()) != 0) {
            const multipart: *gmime.GMimeMultipart = @ptrCast(body);
            text_content = try findTextInMultipart(multipart, allocator);
            html_content = try findHtmlInMultipart(multipart, allocator);
        } else if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(body)), gmime.g_mime_text_part_get_type()) != 0) {
            const text_part: *gmime.GMimeTextPart = @ptrCast(body);
            const text = gmime.g_mime_text_part_get_text(text_part);
            if (text != null) {
                defer gmime.g_free(text);
                const content_type_obj = gmime.g_mime_object_get_content_type(body);
                const mime_type = if (content_type_obj != null)
                    gmime.g_mime_content_type_get_mime_type(content_type_obj)
                else
                    null;
                const ct = if (mime_type != null) std.mem.span(mime_type) else "text/plain";
                const content = try allocator.dupe(u8, std.mem.span(text));
                if (std.mem.eql(u8, ct, "text/html")) {
                    html_content = content;
                } else {
                    text_content = content;
                }
            }
        }

        // Ensure we have both text and html versions
        if (text_content == null and html_content != null) {
            text_content = try textTransformation.htmlToText(allocator, html_content.?);
        }
        if (html_content == null and text_content != null) {
            html_content = try std.fmt.allocPrint(allocator,
                \\<html>
                \\<head><title>No HTML version available</title></head>
                \\<body>No HTML version available. Text is:<br><pre>{s}</pre></body>
                \\</html>
            , .{text_content.?});
        }

        var final_text = text_content orelse try allocator.dupe(u8, "no text or html versions available");

        // If text is empty (e.g., HTML with only images without alt tags), provide fallback
        if (final_text.len == 0) {
            allocator.free(final_text);
            final_text = try allocator.dupe(u8, "Message contains only image data without alt tags");
        }

        return .{
            .text = final_text,
            .html = html_content orelse try allocator.dupe(u8,
                \\<html>
                \\<head><title>No text or HTML version available</title></head>
                \\<body>No text or HTML versions available</body>
                \\</html>
            ),
        };
    }

    pub fn getHeader(self: Message, name: []const u8) ?[]const u8 {
        const name_z = std.mem.sliceTo(name, 0);
        const header = gmime.g_mime_message_get_header(self.message, name_z.ptr);
        if (header == null) return null;
        return std.mem.span(header);
    }

    pub const AttachmentInfo = struct {
        filename: []const u8,
        content_type: []const u8,
    };

    pub fn getAttachments(self: Message, allocator: std.mem.Allocator) ![]AttachmentInfo {
        var list = std.ArrayList(AttachmentInfo){};
        defer list.deinit(allocator);

        // Get the MIME part from the message (not just the body)
        const mime_part = gmime.g_mime_message_get_mime_part(self.message);
        if (mime_part == null) return try allocator.dupe(AttachmentInfo, &.{});

        try collectAttachments(mime_part, &list, allocator);
        return list.toOwnedSlice(allocator);
    }

    fn collectAttachments(part: *gmime.GMimeObject, list: *std.ArrayList(AttachmentInfo), allocator: std.mem.Allocator) !void {
        // Check if this is a multipart
        if (gmime.g_type_check_instance_is_a(@as(*gmime.GTypeInstance, @ptrCast(part)), gmime.g_mime_multipart_get_type()) != 0) {
            const multipart: *gmime.GMimeMultipart = @ptrCast(part);
            const count_i = gmime.g_mime_multipart_get_count(multipart);
            if (count_i == -1) return;
            const count: usize = @intCast(count_i);

            for (0..count) |i| {
                const subpart = gmime.g_mime_multipart_get_part(multipart, @intCast(i));
                if (subpart != null) {
                    try collectAttachments(subpart, list, allocator);
                }
            }
            return;
        }

        // Check if this part is an attachment
        const disposition = gmime.g_mime_object_get_content_disposition(part);
        if (disposition != null) {
            const disp_str = gmime.g_mime_content_disposition_get_disposition(disposition);
            if (disp_str != null and (std.mem.eql(u8, std.mem.span(disp_str), "attachment") or
                std.mem.eql(u8, std.mem.span(disp_str), "inline")))
            {
                const filename_c = gmime.g_mime_part_get_filename(@as(*gmime.GMimePart, @ptrCast(part)));
                if (filename_c != null) {
                    const content_type_obj = gmime.g_mime_object_get_content_type(part);
                    const mime_type = if (content_type_obj != null)
                        gmime.g_mime_content_type_get_mime_type(content_type_obj)
                    else
                        null;

                    try list.append(allocator, .{
                        .filename = try allocator.dupe(u8, std.mem.span(filename_c)),
                        .content_type = if (mime_type != null)
                            try allocator.dupe(u8, std.mem.span(mime_type))
                        else
                            try allocator.dupe(u8, "application/octet-stream"),
                    });
                }
            }
        }
    }
};

fn testPath(allocator: std.mem.Allocator) ![:0]const u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    return std.fs.path.joinZ(allocator, &[_][]const u8{ cwd, "mail", "Inbox", "cur", "1721591945.R4187135327503631514.nucman:2,S" });
}
test "read raw body of message" {
    var engine = Self.init();
    defer engine.deinit();
    const allocator = std.testing.allocator;
    const message_path = try testPath(allocator);
    defer allocator.free(message_path);
    const msg = try engine.openMessage(message_path);
    defer msg.deinit();
    const body = try msg.rawBody(allocator);
    defer allocator.free(body);
    try std.testing.expectEqualStrings(
        \\<html>
        \\<head>
        \\<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        \\</head>
        \\<body><a href="https://unmaskfauci.com/assets/images/chw.php"><img src="https://imgpx.com/dfE6oYsvHoYw.png"></a> <div><img width=1 height=1 alt="" src="https://vnevent.net/wp-content/plugins/wp-automatic/awe.php?QFYiTaVCm0ogM30sC5RNRb%2FKLO0%2FqO3iN9A89RgPbrGjPGsdVierqrtB7w8mnIqJugBVA5TZVG%2F6MFLMOrK9z4D6vgFBDRgH88%2FpEmohBbpaSFf4wx1l9S4LGJd87EK6"></div></body></html>
    , std.mem.trimRight(u8, body, "\r\n"));
}

test "can get body from multipart/alternative html preferred" {
    var engine = Self.init();
    defer engine.deinit();
    const allocator = std.testing.allocator;
    const message_path = try testPath(allocator);
    defer allocator.free(message_path);
    const msg = try engine.openMessage(message_path);
    defer msg.deinit();
    const body = try msg.rawBody(allocator);
    defer allocator.free(body);
    const b = "hi";
    _ = b;
    try std.testing.expectEqualStrings(
        \\<html>
        \\<head>
        \\<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        \\</head>
        \\<body><a href="https://unmaskfauci.com/assets/images/chw.php"><img src="https://imgpx.com/dfE6oYsvHoYw.png"></a> <div><img width=1 height=1 alt="" src="https://vnevent.net/wp-content/plugins/wp-automatic/awe.php?QFYiTaVCm0ogM30sC5RNRb%2FKLO0%2FqO3iN9A89RgPbrGjPGsdVierqrtB7w8mnIqJugBVA5TZVG%2F6MFLMOrK9z4D6vgFBDRgH88%2FpEmohBbpaSFf4wx1l9S4LGJd87EK6"></div></body></html>
    , std.mem.trimRight(u8, body, "\r\n"));
}

test "can parse attachments" {
    var engine = Self.init();
    defer engine.deinit();
    const allocator = std.testing.allocator;

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    const attachment_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ cwd, "mail", "Inbox", "cur", "attachmentmcattachface.msg" });
    defer allocator.free(attachment_path);

    const msg = try engine.openMessage(attachment_path);
    defer msg.deinit();

    const attachments = try msg.getAttachments(allocator);
    defer {
        for (attachments) |att| {
            allocator.free(att.filename);
            allocator.free(att.content_type);
        }
        allocator.free(attachments);
    }

    // Should have one attachment
    try std.testing.expectEqual(@as(usize, 1), attachments.len);
    try std.testing.expectEqualStrings("a.txt", attachments[0].filename);
    try std.testing.expectEqualStrings("text/plain", attachments[0].content_type);
}
