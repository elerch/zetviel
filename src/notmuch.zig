//! Zig bindings for the notmuch email indexing library.
//!
//! This module provides a safe Zig interface to the notmuch C library,
//! allowing for searching, tagging, and managing email messages indexed
//! by notmuch.
//!
//! Main components:
//! - `Db`: Database access and query operations
//! - `Thread`: Email thread representation
//! - `Message`: Individual email message access
//! - `Status`: Error handling and status reporting
//!
//! Example usage:
//! ```
//! var status: Status = undefined;
//! var db = try Db.open("/path/to/maildir", &status);
//! defer db.close();
//!
//! var threads = try db.searchThreads("from:example.com");
//! defer threads.deinit();
//!
//! while (threads.next()) |thread| {
//!     defer thread.deinit();
//!     std.debug.print("Thread: {s}\n", .{thread.getSubject()});
//! }
//! ```

const std = @import("std");
const c = @import("c.zig").c;

pub const Status = struct {
    err: ?anyerror = null,
    status: c.notmuch_status_t = c.NOTMUCH_STATUS_SUCCESS,
    msg: ?[*:0]u8 = null,

    pub fn deinit(status: *Status) void {
        if (status.msg) |m| std.c.free(m);
        status.err = undefined;
        status.status = c.NOTMUCH_STATUS_SUCCESS;
        status.msg = null;
    }

    pub fn statusString(status: Status) []const u8 {
        return std.mem.span(c.notmuch_status_to_string(status.status));
    }
};
pub const Db = struct {
    handle: *c.notmuch_database_t,

    pub fn open(path: [:0]const u8, status: ?*Status) !Db {
        var db: ?*c.notmuch_database_t = null;
        var err: ?[*:0]u8 = null;

        const open_status = c.notmuch_database_open_with_config(
            path,
            c.NOTMUCH_DATABASE_MODE_READ_ONLY,
            "",
            null,
            &db,
            @ptrCast(&err),
        );
        defer if (err) |e| if (status == null) std.c.free(e);
        if (open_status != c.NOTMUCH_STATUS_SUCCESS) {
            if (status) |s| s.* = .{
                .msg = err,
                .status = open_status,
                .err = error.CouldNotOpenDatabase,
            };
            return error.CouldNotOpenDatabase;
        }
        if (db == null) unreachable; // If we opened the database successfully, this should never be null
        if (status) |s| s.* = .{};
        return .{ .handle = db.? };
    }

    pub fn close(db: *Db) void {
        _ = c.notmuch_database_close(db.handle);
    }
    pub fn deinit(db: *Db) void {
        _ = c.notmuch_database_destroy(db.handle);
        db.handle = undefined;
    }

    //
    // Execute a query for threads, returning a notmuch_threads_t object
    // which can be used to iterate over the results. The returned threads
    // object is owned by the query and as such, will only be valid until
    // notmuch_query_destroy.
    //
    // Typical usage might be:
    //
    //     notmuch_query_t *query;
    //     notmuch_threads_t *threads;
    //     notmuch_thread_t *thread;
    //     notmuch_status_t stat;
    //
    //     query = notmuch_query_create (database, query_string);
    //
    //     for (stat = notmuch_query_search_threads (query, &threads);
    //          stat == NOTMUCH_STATUS_SUCCESS &&
    //          notmuch_threads_valid (threads);
    //          notmuch_threads_move_to_next (threads))
    //     {
    //         thread = notmuch_threads_get (threads);
    //         ....
    //         notmuch_thread_destroy (thread);
    //     }
    //
    //     notmuch_query_destroy (query);
    //
    // Note: If you are finished with a thread before its containing
    // query, you can call notmuch_thread_destroy to clean up some memory
    // sooner (as in the above example). Otherwise, if your thread objects
    // are long-lived, then you don't need to call notmuch_thread_destroy
    // and all the memory will still be reclaimed when the query is
    // destroyed.
    //
    // Note that there's no explicit destructor needed for the
    // notmuch_threads_t object. (For consistency, we do provide a
    // notmuch_threads_destroy function, but there's no good reason
    // to call it if the query is about to be destroyed).
    pub fn searchThreads(db: Db, query: [:0]const u8) !ThreadIterator {
        const nm_query = c.notmuch_query_create(db.handle, query);
        if (nm_query == null) return error.CouldNotCreateQuery;
        const handle = nm_query.?;
        errdefer c.notmuch_query_destroy(handle);
        // SAFETY: out paramter in notmuch_query_search_threads
        var threads: ?*c.notmuch_threads_t = undefined;
        const status = c.notmuch_query_search_threads(handle, &threads);
        if (status != c.NOTMUCH_STATUS_SUCCESS) return error.CouldNotSearchThreads;
        return .{
            .query = handle,
            .thread_state = threads orelse return error.CouldNotSearchThreads,
        };
    }
    pub const TagsIterator = struct {
        tags_state: *c.notmuch_tags_t,
        first: bool = true,

        pub fn next(self: *TagsIterator) ?[]const u8 {
            if (!self.first) c.notmuch_tags_move_to_next(self.tags_state);
            self.first = false;
            if (c.notmuch_tags_valid(self.tags_state) == 0) return null;
            return std.mem.span(c.notmuch_tags_get(self.tags_state));
        }

        pub fn jsonStringify(self: *TagsIterator, jws: anytype) !void {
            try jws.beginArray();
            while (self.next()) |t| try jws.write(t);
            try jws.endArray();
        }
        // Docs imply strongly not to bother with deinitialization here

    };

    pub const Message = struct {
        message_handle: *c.notmuch_message_t,

        pub fn getHeader(self: Message, header: [:0]const u8) ?[]const u8 {
            const val = c.notmuch_message_get_header(self.message_handle, header) orelse {
                std.log.err("notmuch returned null for header '{s}' on message {s} (file: {s})", .{ header, self.getMessageId(), self.getFilename() });
                return null;
            };
            const ziggy_val = std.mem.span(val);
            if (ziggy_val.len == 0) return null;
            return ziggy_val;
        }
        pub fn getMessageId(self: Message) []const u8 {
            return std.mem.span(c.notmuch_message_get_message_id(self.message_handle));
        }
        pub fn getFilename(self: Message) []const u8 {
            return std.mem.span(c.notmuch_message_get_filename(self.message_handle));
        }

        pub fn deinit(self: Message) void {
            c.notmuch_message_destroy(self.message_handle);
        }
    };
    pub const MessageIterator = struct {
        messages_state: *c.notmuch_messages_t,
        first: bool = true,

        pub fn next(self: *MessageIterator) ?Message {
            if (!self.first) c.notmuch_messages_move_to_next(self.messages_state);
            self.first = false;
            if (c.notmuch_messages_valid(self.messages_state) == 0) return null;
            const message = c.notmuch_messages_get(self.messages_state) orelse return null;
            return .{
                .message_handle = message,
            };
        }

        // Docs imply strongly not to bother with deinitialization here

    };
    pub const Thread = struct {
        thread_handle: *c.notmuch_thread_t,

        /// Get the thread ID of 'thread'.
        ///
        /// The returned string belongs to 'thread' and as such, should not be
        /// modified by the caller and will only be valid for as long as the
        /// thread is valid, (which is until deinit() or the query from which
        /// it derived is destroyed).
        pub fn getThreadId(self: Thread) []const u8 {
            return std.mem.span(c.notmuch_thread_get_thread_id(self.thread_handle));
        }

        /// The returned string is a comma-separated list of the names of the
        /// authors of mail messages in the query results that belong to this
        /// thread.
        pub fn getAuthors(self: Thread) []const u8 {
            return std.mem.span(c.notmuch_thread_get_authors(self.thread_handle));
        }

        /// Gets the date of the newest message in 'thread' as a time_t value
        pub fn getNewestDate(self: Thread) u64 {
            return @intCast(c.notmuch_thread_get_newest_date(self.thread_handle));
        }

        /// Gets the date of the oldest message in 'thread' as a time_t value
        pub fn getOldestDate(self: Thread) u64 {
            return @intCast(c.notmuch_thread_get_oldest_date(self.thread_handle));
        }

        /// Gets the tags of the thread
        pub fn getTags(self: Thread) !TagsIterator {
            return .{
                .tags_state = c.notmuch_thread_get_tags(self.thread_handle) orelse return error.CouldNotGetIterator,
            };
        }

        /// Get the subject of 'thread' as a UTF-8 string.
        ///
        /// The subject is taken from the first message (according to the query
        /// order---see notmuch_query_set_sort) in the query results that
        /// belongs to this thread.
        pub fn getSubject(self: Thread) []const u8 {
            return std.mem.span(c.notmuch_thread_get_subject(self.thread_handle));
        }

        /// Get the total number of messages in 'thread' that matched the search
        ///
        /// This count includes only the messages in this thread that were
        /// matched by the search from which the thread was created and were
        /// not excluded by any exclude tags passed in with the query (see
        pub fn getMatchedMessages(self: Thread) c_int {
            return c.notmuch_thread_get_matched_messages(self.thread_handle);
        }

        /// Get the total number of messages in 'thread'.
        ///
        /// This count consists of all messages in the database belonging to
        /// this thread. Contrast with notmuch_thread_get_matched_messages() .
        pub fn getTotalMessages(self: Thread) c_int {
            return c.notmuch_thread_get_total_messages(self.thread_handle);
        }

        /// Get the total number of files in 'thread'.
        ///
        /// This sums notmuch_message_count_files over all messages in the
        /// thread
        pub fn getTotalFiles(self: Thread) c_int {
            return c.notmuch_thread_get_total_files(self.thread_handle);
        }

        pub fn getMessages(self: Thread) !MessageIterator {
            return .{
                .messages_state = c.notmuch_thread_get_messages(self.thread_handle) orelse return error.CouldNotGetIterator,
            };
        }

        pub fn deinit(self: Thread) void {
            c.notmuch_thread_destroy(self.thread_handle);
            // self.thread_handle = undefined;
        }
    };
    pub const ThreadIterator = struct {
        query: *c.notmuch_query_t,
        thread_state: *c.notmuch_threads_t,
        first: bool = true,

        pub fn next(self: *ThreadIterator) ?Thread {
            if (!self.first) c.notmuch_threads_move_to_next(self.thread_state);
            self.first = false;
            if (c.notmuch_threads_valid(self.thread_state) == 0) return null;
            const thread = c.notmuch_threads_get(self.thread_state) orelse return null;
            return .{
                .thread_handle = thread,
            };
        }

        pub fn deinit(self: *ThreadIterator) void {
            c.notmuch_query_destroy(self.query);
            self.query = undefined;
        }
    };
};

test "can get status" {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(path_buf[0..]);
    const db_path = try std.fs.path.joinZ(fba.allocator(), &[_][]const u8{ cwd, "mail" });
    {
        var status: Status = undefined;
        var db = try Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        try std.testing.expectEqualStrings("No error occurred", status.statusString());
    }
    {
        var db = try Db.open(db_path, null);
        defer db.deinit();
        defer db.close();
    }
    {
        var status: Status = undefined;
        try std.testing.expectError(error.CouldNotOpenDatabase, Db.open(
            "NON-EXISTANT",
            &status,
        ));
        defer status.deinit();
        try std.testing.expectEqualStrings(
            "Path supplied is illegal for this function",
            status.statusString(),
        );
    }
}

test "can search threads" {
    // const allocator = std.testing.allocator;
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
        var status: Status = undefined;
        var db = try Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        try std.testing.expectEqualStrings("No error occurred", status.statusString());
        var t_iter = try db.searchThreads("Tablets");
        defer t_iter.deinit();
        var inx: usize = 0;
        while (t_iter.next()) |t| : (inx += 1) {
            defer t.deinit();
            try std.testing.expectEqual(@as(c_int, 1), t.getTotalMessages());
            try std.testing.expectEqualStrings("0000000000000001", t.getThreadId());
            var message_iter = try t.getMessages();
            var jnx: usize = 0;
            while (message_iter.next()) |m| : (jnx += 1) {
                defer m.deinit();
                try std.testing.expectStringEndsWith(m.getFilename(), "/1721591945.R4187135327503631514.nucman:2,S");
            }
            try std.testing.expectEqual(@as(usize, 1), jnx);
        }
        try std.testing.expectEqual(@as(usize, 1), inx);
    }
}
