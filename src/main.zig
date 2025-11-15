const std = @import("std");
const httpz = @import("httpz");
const root = @import("root.zig");
const auth = @import("auth.zig");

const version = @import("build_options").git_revision;

fn exitAfterDelay() void {
    std.Thread.sleep(500 * std.time.ns_per_ms);
    std.log.err("Notmuch search is in unrecoverable state: exiting", .{});
    std.process.exit(1);
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // SAFETY: buffer to be used by writer
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_f = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_f.interface;
    // SAFETY: buffer to be used by writer
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_f = std.fs.File.stdout().writer(&stderr_buffer);
    const stderr = &stderr_f.interface;

    errdefer stdout.flush() catch @panic("could not flush stdout");
    errdefer stderr.flush() catch @panic("could not flush stdout");
    defer stdout.flush() catch @panic("could not flush stdout");
    defer stderr.flush() catch @panic("could not flush stdout");
    // Parse CLI arguments
    var port: u16 = 5000;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.writeAll(
                \\Zetviel - Email client for notmuch
                \\
                \\Usage: zetviel [OPTIONS]
                \\
                \\Options:
                \\  --port <PORT>    Port to listen on (default: 5000)
                \\  --help, -h       Show this help message
                \\  --version, -v    Show version information
                \\
                \\Environment:
                \\  NOTMUCH_PATH     Path to notmuch database (default: mail)
                \\
            );
            return 0;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try stdout.print("Zetviel {s}\n", .{version});
            return 0;
        } else if (std.mem.eql(u8, arg, "--port")) {
            const port_str = args.next() orelse {
                try stderr.writeAll("Error: --port requires a value\n");
                return 1;
            };
            port = std.fmt.parseInt(u16, port_str, 10) catch {
                try stderr.writeAll("Error: invalid port number\n");
                return 1;
            };
        } else {
            try stderr.print("Error: unknown argument '{s}'\n", .{arg});
            try stderr.writeAll("Use --help for usage information\n");
            return 1;
        }
    }

    // Get notmuch database path from environment or use default
    const db_path = std.posix.getenv("NOTMUCH_PATH") orelse "mail";
    try stdout.print("Notmuch database: {s}\n", .{db_path});

    // Load credentials
    const creds_path = std.posix.getenv("ZETVIEL_CREDS") orelse ".zetviel_creds";
    const creds = auth.loadCredentials(allocator, creds_path) catch |err| {
        if (err == error.FileNotFound) {
            try stderr.print("Warning: No credentials file found at {s}\n", .{creds_path});
            try stderr.writeAll("API routes will be unprotected. Create a credentials file with:\n");
            try stderr.writeAll("  echo 'username' > .zetviel_creds\n");
            try stderr.writeAll("  echo 'password' >> .zetviel_creds\n");
        } else {
            try stderr.print("Error loading credentials: {s}\n", .{@errorName(err)});
            return 1;
        }
        return 1;
    };
    defer {
        allocator.free(creds.username);
        allocator.free(creds.password);
    }

    // Open notmuch database
    var db = try root.openNotmuchDb(
        allocator,
        db_path,
        null,
    );
    defer db.close();

    try stdout.print("Zetviel starting on http://0.0.0.0:{d}\n", .{port});
    try stdout.flush(); // flush before we listen

    // Create HTTP server
    var server = try httpz.Server(*root.NotmuchDb).init(allocator, .{
        .port = port,
        .address = "0.0.0.0",
    }, &db);
    defer server.deinit();

    // Security headers middleware
    var security_headers = SecurityHeaders{};
    const security_middleware = httpz.Middleware(*root.NotmuchDb).init(&security_headers);

    // Auth middleware for API routes
    var basic_auth = auth.BasicAuth{ .creds = creds };
    const auth_middleware = httpz.Middleware(*root.NotmuchDb).init(&basic_auth);

    // API routes with auth
    var api_router = try server.router(.{ .middlewares = &.{ security_middleware, auth_middleware } });
    api_router.get("/api/query/*", queryHandler, .{});
    api_router.get("/api/thread/:thread_id", threadHandler, .{});
    api_router.get("/api/message/:message_id", messageHandler, .{});
    api_router.get("/api/attachment/:message_id/:num", attachmentHandler, .{});
    api_router.get("/api/auth/status", authStatusHandler, .{});

    // Static file serving (no auth)
    var static_router = try server.router(.{ .middlewares = &.{security_middleware} });
    static_router.get("/", indexHandler, .{});
    static_router.get("/*", staticHandler, .{});

    try server.listen();
    return 0;
}

fn indexHandler(db: *root.NotmuchDb, _: *httpz.Request, res: *httpz.Response) !void {
    const file = std.fs.cwd().openFile("static/index.html", .{}) catch {
        res.status = 500;
        res.body = "Error loading index.html";
        return;
    };
    defer file.close();

    const content = file.readToEndAlloc(db.allocator, 1024 * 1024) catch {
        res.status = 500;
        res.body = "Error reading index.html";
        return;
    };

    res.header("Content-Type", "text/html");
    res.header("Cache-Control", "no-cache, no-store, must-revalidate");
    res.body = content;
}

fn staticHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const path = req.url.path;

    const file_path = if (std.mem.eql(u8, path, "/style.css"))
        "static/style.css"
    else if (std.mem.eql(u8, path, "/app.js"))
        "static/app.js"
    else {
        res.status = 404;
        res.body = "Not Found";
        return;
    };

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        res.status = 404;
        res.body = "Not Found";
        return;
    };
    defer file.close();

    const content = file.readToEndAlloc(db.allocator, 1024 * 1024) catch {
        res.status = 500;
        res.body = "Error reading file";
        return;
    };

    if (std.mem.endsWith(u8, file_path, ".css")) {
        res.header("Content-Type", "text/css");
    } else if (std.mem.endsWith(u8, file_path, ".js")) {
        res.header("Content-Type", "application/javascript");
    }

    res.body = content;
}

const SecurityHeaders = struct {
    pub fn execute(_: *SecurityHeaders, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
        res.header("X-Frame-Options", "deny");
        res.header("X-Content-Type-Options", "nosniff");
        res.header("X-XSS-Protection", "1; mode=block");
        res.header("Referrer-Policy", "no-referrer");
        _ = req;
        return executor.next();
    }
};

fn queryHandler(db: *root.NotmuchDb, req: *httpz.Request, res: *httpz.Response) !void {
    const encoded_query = req.url.path[11..]; // Skip "/api/query/"
    if (encoded_query.len == 0) {
        res.status = 400;
        try res.json(.{ .@"error" = "Query parameter required" }, .{});
        return;
    }

    // URL decode the query
    const query_buf = try req.arena.dupe(u8, encoded_query);
    const query = std.Uri.percentDecodeInPlace(query_buf);

    var threads = db.search(query) catch |err| {
        if (err == error.CouldNotSearchThreads) {
            res.status = 503;
            try res.json(.{ .@"error" = "CouldNotSearchThreads", .fatal = true }, .{});
            const exit_thread = std.Thread.spawn(.{}, exitAfterDelay, .{}) catch @panic("could not spawn thread to kill process");
            exit_thread.detach();
            return;
        }
        res.status = 500;
        try res.json(.{ .@"error" = @errorName(err) }, .{});
        return;
    };
    defer threads.deinit();

    // Check Accept header
    const accept = req.header("accept") orelse "application/json";
    if (std.mem.startsWith(u8, accept, "text/plain")) {
        // Parse parameters
        const has_format = std.mem.indexOf(u8, accept, "format=message-ids") != null;
        const separator_param = std.mem.indexOf(u8, accept, "separator=");
        const has_mutt_escape = std.mem.indexOf(u8, accept, "escape=mutt") != null;

        if (!has_format) {
            res.status = 400;
            res.body = "Invalid Accept header: text/plain requires format=message-ids";
            return;
        }

        // Collect message IDs
        var msg_ids = std.ArrayList([]const u8){};

        while (try threads.next()) |*thread| {
            defer thread.deinit();
            var msg_iter = try thread.thread.getMessages();
            while (msg_iter.next()) |msg| {
                const msg_id = msg.getMessageId();
                if (has_mutt_escape) {
                    const escaped = try std.mem.replaceOwned(u8, res.arena, msg_id, "+", "\\+");
                    try msg_ids.append(res.arena, escaped);
                } else {
                    try msg_ids.append(res.arena, msg_id);
                }
            }
        }

        // Format output
        const separator: []const u8 = if (separator_param) |s| accept[s + "separator=".len .. s + "separator=".len + 1] else "\n";
        const output = try std.mem.join(res.arena, separator, msg_ids.items);
        res.header("Content-Type", "text/plain");
        res.body = output;
    } else if (std.mem.startsWith(u8, accept, "application/json") or std.mem.eql(u8, accept, "*/*")) {
        try res.json(threads, .{});
    } else {
        res.status = 400;
        res.body = "Invalid Accept header: must be application/json or text/plain; format=message-ids";
    }
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

fn authStatusHandler(_: *root.NotmuchDb, _: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .authenticated = true }, .{});
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
