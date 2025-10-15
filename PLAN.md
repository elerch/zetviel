# Zetviel Development Plan

## Project Rules
1. **Always run `zig fmt .` after any change to a zig file**
2. **Before considering a task complete: `zig build` must have no errors/output**
3. **Before considering a task complete: all tests must pass with `zig build test`**

## Goal
Create a netviel clone with improvements:
- Visual indication that server is working
- URL changes with UI state for deep linking
- Custom frontend (not copying netviel's JavaScript)

## Phase 1: Upgrade Zig ✅ COMPLETE
- [x] Update `build.zig.zon` to Zig 0.15.2
- [x] Update `.mise.toml` to use Zig 0.15.2
- [x] Fix breaking changes in `build.zig` (Module API, alignment issues)
- [x] Fix breaking changes in `src/main.zig` (stdout API)
- [x] Fix JSON API changes in `src/root.zig` (converted OutOfMemory to WriteFailed)
- [x] Verify all tests pass
- [x] Run `zig fmt .`

## Phase 2: Complete Email Parsing API ✅ COMPLETE
- [x] Finish `Email.zig` implementation:
  - [x] Extract HTML/plain text content with preference (html > plain)
  - [x] Parse and list attachments (filename, content-type)
  - [x] Extract all standard headers (from, to, cc, bcc, date, subject)
  - [x] Add attachment retrieval by index (getAttachments method)
- [x] Integrate Email parsing into `root.zig` Thread API
- [x] Add tests for new functionality (existing tests pass)
- [x] Run `zig fmt .`

## Phase 3: HTTP Server & REST API ✅ COMPLETE
- [x] Research and choose HTTP framework (httpz)
- [x] Add HTTP server dependency
- [x] Implement REST endpoints:
  - [x] `GET /api/query/<query_string>` - search threads
  - [x] `GET /api/thread/<thread_id>` - get thread messages
  - [x] `GET /api/attachment/<message_id>/<num>` - download attachment
  - [x] `GET /api/message/<message_id>` - get message details
- [x] Complete JSON serialization (extend existing in root.zig)
- [x] Add security headers via httpz middleware
- [x] Add tests for API endpoints
- [x] Run `zig fmt .`

## Phase 4: Static File Serving ✅ COMPLETE
- [x] Implement static file serving:
  - [x] Serve `index.html` at `/`
  - [x] Serve static assets (placeholder 404 handler)
  - [x] Handle SPA routing (all non-API paths ready)
- [x] Add `--port` CLI argument
- [x] Run `zig fmt .`

## Phase 5: Frontend Development
- [ ] Design minimal UI (list threads, view messages, search)
- [ ] Implement frontend features:
  - [ ] Thread list view
  - [ ] Message detail view
  - [ ] Search functionality
  - [ ] Visual server status indicator
  - [ ] URL-based routing for deep linking
  - [ ] Attachment download links
- [ ] Ensure API compatibility

## Phase 6: Polish
- [ ] Add proper error handling throughout
- [ ] Add logging
- [ ] Update README with usage instructions
- [ ] Add configuration options (NOTMUCH_PATH env var)
- [ ] Security audit and warnings (local-only usage)
- [ ] Run `zig fmt .`

## Notes
- Frontend will be custom-built, not copied from netviel
- HTTP framework choice deferred to Phase 3
- HTML sanitization will use simple allowlist approach (not porting bleach)

## Current Status
Ready to begin Phase 1: Zig upgrade to 0.15.2
