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
- `--port`: HTTP server port (default: 5000)

API Endpoints
-------------

- `GET /api/query/<query>` - Search threads using notmuch query syntax
- `GET /api/thread/<thread_id>` - Get messages in a thread
- `GET /api/message/<message_id>` - Get message details with content
- `GET /api/attachment/<message_id>/<num>` - Get attachment metadata

Security
--------

**WARNING**: Zetviel is intended for local use only. It binds to 127.0.0.1 and should
not be exposed to the internet without additional security measures.
