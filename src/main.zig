const std = @import("std");
const httpz = @import("httpz");
const root = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get notmuch database path from environment or use default
    const db_path = std.posix.getenv("NOTMUCH_PATH") orelse "mail";

    // Open notmuch database
    var db = try root.openNotmuchDb(allocator, db_path, null);
    defer db.close();

    std.debug.print("Zetviel starting on http://localhost:5000\n", .{});
    std.debug.print("Notmuch database: {s}\n", .{db.path});

    // Create HTTP server
    var server = try httpz.Server(*root.NotmuchDb).init(allocator, .{
        .port = 5000,
        .address = "127.0.0.1",
    }, &db);
    defer server.deinit();

    // API routes
    var router = try server.router(.{});
    router.get("/api/query/*", queryHandler, .{});
    router.get("/api/thread/:thread_id", threadHandler, .{});
    router.get("/api/message/:message_id", messageHandler, .{});
    router.get("/api/attachment/:message_id/:num", attachmentHandler, .{});

    // TODO: Static file serving for frontend

    try server.listen();
}

fn queryHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const query = req.url.path[11..]; // Skip "/api/query/"
    if (query.len == 0) {
        res.status = 400;
        try res.json(.{ .@"error" = "Query parameter required" }, .{});
        return;
    }

    var threads = db.search(query) catch |err| {
        res.status = 500;
        try res.json(.{ .@"error" = @errorName(err) }, .{});
        return;
    };
    defer threads.deinit();

    try res.json(threads, .{});
}

fn threadHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const thread_id = req.param("thread_id") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Thread ID required" }, .{});
        return;
    };

    var thread = db.getThread(thread_id) catch |err| {
        res.status = 404;
        try res.json(.{ .@"error" = @errorName(err) }, .{});
        return;
    };
    defer thread.deinit();

    try res.json(thread, .{});
}

fn messageHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const message_id = req.param("message_id") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Message ID required" }, .{});
        return;
    };

    const msg = db.getMessage(message_id) catch |err| {
        res.status = 404;
        try res.json(.{ .@"error" = @errorName(err) }, .{});
        return;
    };
    defer msg.deinit(db.allocator);

    try res.json(msg, .{});
}

fn attachmentHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const message_id = req.param("message_id") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Message ID required" }, .{});
        return;
    };

    const num_str = req.param("num") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Attachment number required" }, .{});
        return;
    };

    const num = std.fmt.parseInt(usize, num_str, 10) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid attachment number" }, .{});
        return;
    };

    const msg = db.getMessage(message_id) catch |err| {
        res.status = 404;
        try res.json(.{ .@"error" = @errorName(err) }, .{});
        return;
    };
    defer msg.deinit(db.allocator);

    if (num >= msg.attachments.len) {
        res.status = 404;
        try res.json(.{ .@"error" = "Attachment not found" }, .{});
        return;
    }

    const att = msg.attachments[num];
    res.header("Content-Type", att.content_type);
    res.header("Content-Disposition", try std.fmt.allocPrint(db.allocator, "attachment; filename=\"{s}\"", .{att.filename}));

    // TODO: Actually retrieve and send attachment content
    // For now, just send metadata
    try res.json(.{ .filename = att.filename, .content_type = att.content_type }, .{});
}

test "queryHandler with valid query" {
    const allocator = std.testing.allocator;
    var db = try root.openNotmuchDb(allocator, "mail", null);
    defer db.close();

    var t = httpz.testing.init(.{});
    defer t.deinit();

    t.url("/api/query/tag:inbox");
    try queryHandler(&db, t.req, t.res);
    try std.testing.expect(t.res.status != 400);
}

test "queryHandler with empty query" {
    const allocator = std.testing.allocator;
    var db = try root.openNotmuchDb(allocator, "mail", null);
    defer db.close();

    var t = httpz.testing.init(.{});
    defer t.deinit();

    t.url("/api/query/");
    try queryHandler(&db, t.req, t.res);
    try std.testing.expectEqual(@as(u16, 400), t.res.status);
}

test "messageHandler with valid message" {
    const allocator = std.testing.allocator;
    var db = try root.openNotmuchDb(allocator, "mail", null);
    defer db.close();

    var threads = try db.search("*");
    defer threads.deinit();

    var maybe_thread = (try threads.next()).?;
    defer maybe_thread.deinit();

    var mi = try maybe_thread.thread.getMessages();
    const msg_id = mi.next().?.getMessageId();

    var t = httpz.testing.init(.{});
    defer t.deinit();

    t.param("message_id", msg_id);
    try messageHandler(&db, t.req, t.res);
    try std.testing.expect(t.res.status != 404);
}

test "threadHandler with valid thread" {
    const allocator = std.testing.allocator;
    var db = try root.openNotmuchDb(allocator, "mail", null);
    defer db.close();

    var threads = try db.search("*");
    defer threads.deinit();

    var maybe_thread = (try threads.next()).?;
    defer maybe_thread.deinit();

    const thread_id = maybe_thread.thread.getThreadId();

    var t = httpz.testing.init(.{});
    defer t.deinit();

    t.param("thread_id", thread_id);
    try threadHandler(&db, t.req, t.res);
    try std.testing.expect(t.res.status != 404);
}
