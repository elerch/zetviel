const std = @import("std");
const httpz = @import("httpz");

pub const Credentials = struct {
    username: []const u8,
    password: []const u8,
};

pub fn loadCredentials(allocator: std.mem.Allocator, path: []const u8) !Credentials {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    const username = std.mem.trim(u8, lines.next() orelse return error.InvalidCredentials, &std.ascii.whitespace);
    const password = std.mem.trim(u8, lines.next() orelse return error.InvalidCredentials, &std.ascii.whitespace);

    return .{
        .username = try allocator.dupe(u8, username),
        .password = try allocator.dupe(u8, password),
    };
}

pub const BasicAuth = struct {
    creds: Credentials,

    pub fn execute(self: *BasicAuth, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
        const auth_header = req.header("authorization") orelse {
            res.status = 401;
            return;
        };

        if (!std.mem.startsWith(u8, auth_header, "Basic ")) {
            res.status = 401;
            return;
        }

        const encoded = auth_header[6..];
        var decoded_buf: [256]u8 = undefined;
        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
            res.status = 401;
            return;
        };
        _ = std.base64.standard.Decoder.decode(&decoded_buf, encoded) catch {
            res.status = 401;
            return;
        };
        const decoded = decoded_buf[0..decoded_len];

        var parts = std.mem.splitScalar(u8, decoded, ':');
        const username = parts.next() orelse {
            res.status = 401;
            return;
        };
        const password = parts.next() orelse {
            res.status = 401;
            return;
        };

        if (!std.mem.eql(u8, username, self.creds.username) or !std.mem.eql(u8, password, self.creds.password)) {
            res.status = 401;
            return;
        }

        return executor.next();
    }
};
