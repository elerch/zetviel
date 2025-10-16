Zetviel
-------

A web-based email client for [notmuch](https://notmuchmail.org/), written in Zig.

As some background, I've had some issues with the very usable [netviel](https://github.com/DavidMStraub/netviel).
I wanted to address those issues, but also simplify the deployment. And, I like Zig,
so I decided this was small enough I'd just re-write the thing to make my own.

Features
--------

- REST API for notmuch queries
- Thread and message viewing
- Attachment handling
- Basic authentication for API routes
- Security headers for safe browsing
- Configurable port

Building
--------

If you have notmuch installed (libnotmuch-dev on a debian-based system),
`zig build` is all you need. If you are using nix, you can `nix develop`, which
will install the necessary notmuch header/library, and the build system will
detect and use that. Again, `zig build` will work in that instance, but you must
`nix develop` first.

Usage
-----

```sh
# Start server on default port (5000)
zetviel

# Start server on custom port
zetviel --port 8080

# Show help
zetviel --help

# Show version
zetviel --version
```

Configuration
-------------

- `NOTMUCH_PATH` environment variable: Path to notmuch database (default: `mail`)
- `ZETVIEL_CREDS` environment variable: Path to credentials file (default: `.zetviel_creds`)
- `--port`: HTTP server port (default: 5000)

### Authentication

Zetviel requires basic authentication for all API routes. Create a credentials file with:

```sh
echo 'username' > .zetviel_creds
echo 'password' >> .zetviel_creds
```

Or set a custom path:

```sh
export ZETVIEL_CREDS=/path/to/credentials
```

The credentials file should contain two lines:
1. Username
2. Password

Static files (HTML, CSS, JS) are served without authentication.

API Endpoints
-------------

- `GET /api/query/<query>` - Search threads using notmuch query syntax
- `GET /api/thread/<thread_id>` - Get messages in a thread
- `GET /api/message/<message_id>` - Get message details with content
- `GET /api/attachment/<message_id>/<num>` - Get attachment metadata
- `GET /api/auth/status` - Check authentication status

Security
--------

**WARNING**: Zetviel binds to 0.0.0.0 by default, making it accessible on all network interfaces.
While basic authentication is required for API routes, this is intended for local or trusted network use only.
Do not expose Zetviel directly to the internet without additional security measures such as:
- Running behind a reverse proxy with HTTPS
- Using a VPN or SSH tunnel
- Implementing additional authentication layers
- Restricting access via firewall rules
