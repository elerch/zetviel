const std = @import("std");
const notmuch = @import("notmuch.zig");
const Email = @import("Email.zig");

pub const Thread = struct {
    allocator: std.mem.Allocator,
    thread: *notmuch.Db.Thread,

    pub fn init(allocator: std.mem.Allocator, t: *notmuch.Db.Thread) Thread {
        return .{ .allocator = allocator, .thread = t };
    }
    pub fn deinit(self: Thread) void {
        self.allocator.destroy(self.thread);
    }

    pub fn jsonStringify(self: Thread, jws: anytype) !void {
        // Format we're looking for on api/thread/<threadid>
        //[
        //  {
        //    "from": "The Washington Post <email@washingtonpost.com>",
        //    "to": "elerch@lerch.org",
        //    "cc": null,
        //    "bcc": null,
        //    "date": "Sun, 21 Jul 2024 19:23:38 +0000",
        //    "subject": "Biden steps aside",
        //    "content": "...content...",
        //    "content_type": "text/html",
        //    "attachments": [],
        //    "message_id": "01010190d6bfe4e1-185e2720-e415-4086-8865-9604cde886c2-000000@us-west-2.amazonses.com"
        //  }
        //]
        try jws.beginArray();
        var mi = self.thread.getMessages() catch return error.OutOfMemory;
        while (mi.next()) |m| {
            try jws.beginObject();
            try jws.objectField("from");
            try jws.write(m.getHeader("from") catch return error.OutOfMemory);
            try jws.objectField("to");
            try jws.write(m.getHeader("to") catch return error.OutOfMemory);
            try jws.objectField("cc");
            try jws.write(m.getHeader("cc") catch return error.OutOfMemory);
            try jws.objectField("bcc");
            try jws.write(m.getHeader("bcc") catch return error.OutOfMemory);
            try jws.objectField("date");
            try jws.write(m.getHeader("date") catch return error.OutOfMemory);
            try jws.objectField("subject");
            try jws.write(m.getHeader("subject") catch return error.OutOfMemory);
            // content, content-type, and attachments are all based on the file itself
            // TODO: init shouldn't fail
            // var message = try Message.init(self.allocator, m.getFilename());
            // defer message.deinit();
            // try message.load();
            // const content_type = try message.getContentType();
            // try jws.objectField("content-type");
            // try jws.write(content_type);

            try jws.objectField("message_id");
            try jws.write(m.getMessageId());
            try jws.endObject();
        }

        try jws.endArray();
    }
};

pub const Threads = struct {
    allocator: std.mem.Allocator,
    iterator: *notmuch.Db.ThreadIterator,

    pub fn init(allocator: std.mem.Allocator, it: *notmuch.Db.ThreadIterator) Threads {
        return .{
            .allocator = allocator,
            .iterator = it,
        };
    }

    pub fn deinit(self: *Threads) void {
        self.iterator.deinit();
        self.allocator.destroy(self.iterator);
    }

    pub fn next(self: *Threads) !?Thread {
        const nxt = self.iterator.next();
        if (nxt) |_| {
            const tptr = try self.allocator.create(notmuch.Db.Thread);
            tptr.* = nxt.?;
            return Thread.init(self.allocator, tptr);
        }
        return null;
    }

    pub fn jsonStringify(self: Threads, jws: anytype) !void {
        // This is the json we're looking to match on api/query/<term>
        // [
        //    {
        //      "authors": "The Washington Post",
        //      "matched_messages": 1,
        //      "newest_date": 1721664948,
        //      "oldest_date": 1721664948,
        //      "subject": "Biden is out. What now?",
        //      "tags": [
        //        "inbox",
        //        "unread"
        //      ],
        //      "thread_id": "0000000000031723",
        //      "total_messages": 1
        //    },
        //    {
        //      "authors": "The Washington Post",
        //      "matched_messages": 1,
        //      "newest_date": 1721603115,
        //      "oldest_date": 1721603115,
        //      "subject": "Upcoming Virtual Programs",
        //      "tags": [
        //        "inbox",
        //        "unread"
        //      ],
        //      "thread_id": "0000000000031712",
        //      "total_messages": 1
        //    },
        //    {
        //      "authors": "The Washington Post",
        //      "matched_messages": 1,
        //      "newest_date": 1721590157,
        //      "oldest_date": 1721590157,
        //      "subject": "Biden Steps Aside",
        //      "tags": [
        //        "inbox"
        //      ],
        //      "thread_id": "000000000003170d",
        //      "total_messages": 1
        //    }
        // ]
        try jws.beginArray();
        while (self.iterator.next()) |t| {
            defer t.deinit();
            try jws.beginObject();
            try jws.objectField("authors");
            try jws.write(t.getAuthors());
            try jws.objectField("matched_messages");
            try jws.write(t.getMatchedMessages());
            try jws.objectField("newest_date");
            try jws.write(t.getNewestDate());
            try jws.objectField("oldest_date");
            try jws.write(t.getOldestDate());
            try jws.objectField("subject");
            try jws.write(t.getSubject());
            try jws.objectField("tags");
            var tags = t.getTags() catch return error.OutOfMemory;
            try tags.jsonStringify(jws);
            try jws.objectField("thread_id");
            try jws.write(t.getThreadId());
            try jws.objectField("total_messages");
            try jws.write(t.getTotalMessages());
            try jws.endObject();
        }
        try jws.endArray();
    }
};

pub const NotmuchDb = struct {
    db: notmuch.Db,
    path: [:0]u8,
    allocator: std.mem.Allocator,
    email: Email,

    /// If email is owned, it will be deinitialized when the database is closed
    /// it is considered owned if openNotmuchDb is called with a null email_engine
    /// parameter.
    email_owned: bool,

    pub fn close(self: *NotmuchDb) void {
        self.db.close();
        self.db.deinit();
        self.allocator.free(self.path);
        if (self.email_owned) self.email.deinit();
    }

    pub fn search(self: *NotmuchDb, query: []const u8) !Threads {
        var query_buf: [1024:0]u8 = undefined;
        const query_z = try std.fmt.bufPrintZ(&query_buf, "{s}", .{query});
        const ti = try self.allocator.create(notmuch.Db.ThreadIterator);
        ti.* = try self.db.searchThreads(query_z);
        return Threads.init(self.allocator, ti);
    }

    pub fn getThread(self: *NotmuchDb, thread_id: []const u8) !Thread {
        var query_buf: [1024:0]u8 = undefined;
        const query_z = try std.fmt.bufPrintZ(&query_buf, "thread:{s}", .{thread_id});
        var thread_iter = try self.db.searchThreads(query_z);
        defer thread_iter.deinit();

        const thread = thread_iter.next();
        if (thread) |t| {
            const tptr = try self.allocator.create(notmuch.Db.Thread);
            tptr.* = t;
            return Thread.init(self.allocator, tptr);
        }
        return error.ThreadNotFound;
    }
};

/// Opens a notmuch database at the specified path
///
/// This function initializes GMime and opens a notmuch database at the specified path.
/// If email_engine is null, a new Email instance will be created and owned by the returned NotmuchDb.
/// Otherwise, the provided email_engine will be used and not owned by the NotmuchDb.
///
/// Parameters:
///   allocator: Memory allocator used for database operations
///   relative_path: Path to the notmuch database relative to current directory
///   email_engine: Optional Email instance to use, or null to create a new one
///
/// Returns:
///   NotmuchDb struct with an open database connection
///
/// Error: Returns error if database cannot be opened or path cannot be resolved
pub fn openNotmuchDb(allocator: std.mem.Allocator, relative_path: []const u8, email_engine: ?Email) !NotmuchDb {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    const db_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ cwd, relative_path });

    const db = try notmuch.Db.open(db_path, null);

    const email = email_engine orelse Email.init();

    return .{
        .db = db,
        .path = db_path,
        .allocator = allocator,
        .email = email,
        .email_owned = email_engine == null,
    };
}

test "ensure all references are observed" {
    std.testing.refAllDeclsRecursive(@This());
}

test "open database with public api" {
    const allocator = std.testing.allocator;
    var db = try openNotmuchDb(allocator, "mail", null);
    defer db.close();
}

test "can stringify general queries" {
    const allocator = std.testing.allocator;
    // const db_path = try std.fs.path.join(
    //     allocator,
    //     std.fs.cwd(),
    //     "mail",
    // );
    var db = try openNotmuchDb(allocator, "mail", null);
    defer db.close();
    var threads = try db.search("Tablets");
    defer threads.deinit();
    const actual = try std.json.stringifyAlloc(allocator, threads, .{ .whitespace = .indent_2 });
    defer allocator.free(actual);
    try std.testing.expectEqualStrings(
        \\[
        \\  {
        \\    "authors": "Top Medications",
        \\    "matched_messages": 1,
        \\    "newest_date": 1721484138,
        \\    "oldest_date": 1721484138,
        \\    "subject": "***SPAM*** Tablets without a prescription",
        \\    "tags": [
        \\      "inbox"
        \\    ],
        \\    "thread_id": "0000000000000001",
        \\    "total_messages": 1
        \\  }
        \\]
    , actual);
}

test "can stringify specific threads" {
    if (true) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    var db = try openNotmuchDb(allocator, "mail", null);
    defer db.close();
    var threads = try db.search("Tablets");
    defer threads.deinit();

    var maybe_first_thread = try threads.next();
    defer if (maybe_first_thread) |*t| t.deinit();
    try std.testing.expect(maybe_first_thread != null);
    const first_thread = maybe_first_thread.?;
    const actual = try std.json.stringifyAlloc(allocator, first_thread, .{ .whitespace = .indent_2 });
    defer allocator.free(actual);
    try std.testing.expectEqualStrings(
        \\[
        \\  {
        \\    "from": "Top Medications <mail@youpharm.co>",
        \\    "to": "emil@lerch.org",
        \\    "cc": null,
        \\    "bcc": null,
        \\    "date": "Sat, 20 Jul 2024 16:02:18 +0200",
        \\    "subject": "***SPAM*** Tablets without a prescription",
        \\    "content": "...content...",
        \\    "content_type": "text/html",
        \\    "attachments": [],
        \\    "message_id": "01010190d6bfe4e1-185e2720-e415-4086-8865-9604cde886c2-000000@us-west-2.amazonses.com"
        \\  }
        \\]
    , actual);
}
