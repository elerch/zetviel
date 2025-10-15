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

## Phase 2: Complete Email Parsing API
- [ ] Finish `Email.zig` implementation:
  - [ ] Extract HTML/plain text content with preference (html > plain)
  - [ ] Parse and list attachments (filename, content-type)
  - [ ] Extract all standard headers (from, to, cc, bcc, date, subject)
  - [ ] Add attachment retrieval by index
- [ ] Integrate Email parsing into `root.zig` Thread API (uncomment TODOs)
- [ ] Add HTML sanitization (simple allowlist approach)
- [ ] Add tests for new functionality
- [ ] Run `zig fmt .`

## Phase 3: HTTP Server & REST API
- [ ] Research and choose HTTP framework (defer decision)
- [ ] Add HTTP server dependency
- [ ] Implement REST endpoints:
  - [ ] `GET /api/query/<query_string>` - search threads
  - [ ] `GET /api/thread/<thread_id>` - get thread messages
  - [ ] `GET /api/attachment/<message_id>/<num>` - download attachment
  - [ ] `GET /api/message/<message_id>` - download raw .eml file
- [ ] Complete JSON serialization (extend existing in root.zig)
- [ ] Add security headers (CORS, X-Frame-Options, etc.)
- [ ] Add tests for API endpoints
- [ ] Run `zig fmt .`

## Phase 4: Static File Serving
- [ ] Implement static file serving:
  - [ ] Serve `index.html` at `/`
  - [ ] Serve static assets (JS, CSS)
  - [ ] Handle SPA routing (all paths → index.html)
- [ ] Add `--port` CLI argument
- [ ] Run `zig fmt .`

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
