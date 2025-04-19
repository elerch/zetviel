const std = @import("std");
const notmuch = @import("notmuch.zig");

// Thread representation for JSON serialization
pub const Thread = struct {
    thread: *notmuch.Db.Thread,

    pub fn init(t: *notmuch.Db.Thread) Thread {
        return .{ .thread = t };
    }

    pub fn jsonStringify(self: Thread, jws: anytype) !void {
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
            try jws.objectField("content");
            try jws.write(m.getFilename()); // TODO: Parse file
            try jws.objectField("content-type");
            try jws.write(m.getHeader("Content-Type") catch return error.OutOfMemory);

            try jws.objectField("message_id");
            try jws.write(m.getMessageId());
            try jws.endObject();
        }

        try jws.endArray();
    }
};

// Threads collection for JSON serialization
pub const Threads = struct {
    iterator: *notmuch.Db.ThreadIterator,

    pub fn init(it: *notmuch.Db.ThreadIterator) Threads {
        return .{
            .iterator = it,
        };
    }

    pub fn jsonStringify(self: Threads, jws: anytype) !void {
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

// Helper function to open a notmuch database from the current directory
pub const NotmuchDb = struct {
    db: notmuch.Db,
    path: [:0]u8,
    allocator: std.mem.Allocator,

    pub fn close(self: *NotmuchDb) void {
        self.db.close();
        self.db.deinit();
        self.allocator.free(self.path);
    }

    pub fn searchThreads(self: *NotmuchDb, query: []const u8) !Threads {
        var query_buf: [1024:0]u8 = undefined;
        const query_z = try std.fmt.bufPrintZ(&query_buf, "{s}", .{query});
        var thread_iter = try self.db.searchThreads(query_z);
        return Threads.init(&thread_iter);
    }

    pub fn getThread(self: *NotmuchDb, thread_id: []const u8) !Thread {
        var query_buf: [1024:0]u8 = undefined;
        const query_z = try std.fmt.bufPrintZ(&query_buf, "thread:{s}", .{thread_id});
        var thread_iter = try self.db.searchThreads(query_z);
        defer thread_iter.deinit();

        var thread = thread_iter.next();
        if (thread) |_| return Thread.init(&thread.?);
        return error.ThreadNotFound;
    }
};

pub fn openNotmuchDb(allocator: std.mem.Allocator, relative_path: []const u8) !NotmuchDb {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    const db_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ cwd, relative_path });

    const db = try notmuch.Db.open(db_path, null);
    return .{
        .db = db,
        .path = db_path,
        .allocator = allocator,
    };
}

test "ensure all references are observed" {
    std.testing.refAllDeclsRecursive(@This());
}

test "open database with public api" {
    const allocator = std.testing.allocator;
    var db = try openNotmuchDb(allocator, "mail");
    defer db.close();
}

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
//
// And on api/thread/<threadid>
//
// [
//   {
//     "from": "The Washington Post <email@washingtonpost.com>",
//     "to": "elerch@lerch.org",
//     "cc": null,
//     "bcc": null,
//     "date": "Sun, 21 Jul 2024 19:23:38 +0000",
//     "subject": "Biden steps aside",
//     "content": "...content...",
//     "content_type": "text/html",
//     "attachments": [],
//     "message_id": "01010190d6bfe4e1-185e2720-e415-4086-8865-9604cde886c2-000000@us-west-2.amazonses.com"
//   }
// ]

test "can stringify general queries" {
    const allocator = std.testing.allocator;
    // const db_path = try std.fs.path.join(
    //     allocator,
    //     std.fs.cwd(),
    //     "mail",
    // );

    // Current directory under test is root of project
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(path_buf[0..]);
    const db_path = try std.fs.path.joinZ(fba.allocator(), &[_][]const u8{ cwd, "mail" });
    {
        var status: notmuch.Status = undefined;
        var db = try notmuch.Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        var al = std.ArrayList(u8).init(allocator);
        defer al.deinit();
        var ti = try db.searchThreads("Tablets");
        defer ti.deinit();
        try std.json.stringify(Threads.init(&ti), .{ .whitespace = .indent_2 }, al.writer());
        const actual = al.items;
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
}

test "can stringify specific threads" {
    if (true) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    // const db_path = try std.fs.path.join(
    //     allocator,
    //     std.fs.cwd(),
    //     "mail",
    // );

    // Current directory under test is root of project
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(path_buf[0..]);
    const db_path = try std.fs.path.joinZ(fba.allocator(), &[_][]const u8{ cwd, "mail" });
    {
        var status: notmuch.Status = undefined;
        var db = try notmuch.Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        var al = std.ArrayList(u8).init(allocator);
        defer al.deinit();
        var ti = try db.searchThreads("Tablets");
        defer ti.deinit();
        var t = ti.next().?;
        try std.json.stringify(Thread.init(&t), .{ .whitespace = .indent_2 }, al.writer());
        const actual = al.items;
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
}
