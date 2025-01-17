// zig type definitions for facilio lib
// or maybe let's just make it zap directly...

const std = @import("std");
const fio = @import("fio.zig");

pub usingnamespace @import("fio.zig");
pub usingnamespace @import("endpoint.zig");
pub usingnamespace @import("util.zig");
pub usingnamespace @import("http.zig");
pub usingnamespace @import("mustache.zig");
pub usingnamespace @import("http_auth.zig");

pub const Log = @import("log.zig");

const util = @import("util.zig");

const _module = @This();

// TODO: replace with comptime debug logger like in log.zig
var _debug: bool = false;

pub fn start(args: fio.fio_start_args) void {
    fio.fio_start(args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (_debug) {
        std.debug.print("[zap] - " ++ fmt, args);
    }
}

pub fn enableDebugLog() void {
    _debug = true;
}

pub fn startWithLogging(args: fio.fio_start_args) void {
    debug = true;
    fio.fio_start(args);
}

pub const ListenError = error{
    AlreadyListening,
    ListenError,
};

pub const HttpError = error{
    HttpSendBody,
    HttpSetContentType,
    HttpSetHeader,
};

pub const HttpParam = struct {
    key: []const u8,
    value: []const u8,
};

pub const ContentType = enum {
    TEXT,
    HTML,
    JSON,
};

pub const SimpleRequest = struct {
    path: ?[]const u8,
    query: ?[]const u8,
    body: ?[]const u8,
    method: ?[]const u8,
    h: [*c]fio.http_s,

    const Self = @This();

    pub fn sendBody(self: *const Self, body: []const u8) HttpError!void {
        const ret = fio.http_send_body(self.h, @intToPtr(
            *anyopaque,
            @ptrToInt(body.ptr),
        ), body.len);
        debug("SimpleRequest.sendBody(): ret = {}\n", .{ret});
        if (ret == -1) return error.HttpSendBody;
    }

    pub fn sendJson(self: *const Self, json: []const u8) HttpError!void {
        if (self.setContentType(.JSON)) {
            if (fio.http_send_body(self.h, @intToPtr(
                *anyopaque,
                @ptrToInt(json.ptr),
            ), json.len) != 0) return error.HttpSendBody;
        } else |err| return err;
    }

    pub fn setContentType(self: *const Self, c: ContentType) HttpError!void {
        const s = switch (c) {
            .TEXT => "text/plain",
            .JSON => "application/json",
            else => "text/html",
        };
        debug("setting content-type to {s}\n", .{s});
        return self.setHeader("content-type", s);
    }

    /// shows how to use the logger
    pub fn setContentTypeWithLogger(
        self: *const Self,
        c: ContentType,
        logger: *const Log,
    ) HttpError!void {
        const s = switch (c) {
            .TEXT => "text/plain",
            .JSON => "application/json",
            else => "text/html",
        };
        logger.log("setting content-type to {s}\n", .{s});
        return self.setHeader("content-type", s);
    }

    pub fn setContentTypeFromPath(self: *const Self) !void {
        const t = fio.http_mimetype_find2(self.h.*.path);
        if (fio.is_invalid(t) == 1) return error.HttpSetContentType;
        const ret = fio.fiobj_hash_set(
            self.h.*.private_data.out_headers,
            fio.HTTP_HEADER_CONTENT_TYPE,
            t,
        );
        if (ret == -1) return error.HttpSetContentType;
    }

    pub fn getHeader(self: *const Self, name: []const u8) ?[]const u8 {
        const hname = fio.fiobj_str_new(util.toCharPtr(name), name.len);
        defer fio.fiobj_free_wrapped(hname);
        return util.fio2str(fio.fiobj_hash_get(self.h.*.headers, hname));
    }

    pub fn setHeader(self: *const Self, name: []const u8, value: []const u8) HttpError!void {
        const hname: fio.fio_str_info_s = .{
            .data = util.toCharPtr(name),
            .len = name.len,
            .capa = name.len,
        };

        debug("setHeader: hname = {}\n", .{hname});
        const vname: fio.fio_str_info_s = .{
            .data = util.toCharPtr(value),
            .len = value.len,
            .capa = value.len,
        };
        debug("setHeader: vname = {}\n", .{vname});
        const ret = fio.http_set_header2(self.h, hname, vname);

        // FIXME without the following if, we get errors in release builds
        // at least we don't have to log unconditionally
        if (ret == -1) {
            std.debug.print("***************** zap.zig:145\n", .{});
        }
        debug("setHeader: ret = {}\n", .{ret});

        // Note to self:
        // const new_fiobj_str = fio.fiobj_str_new(name.ptr, name.len);
        // fio.fiobj_free(new_fiobj_str);

        if (ret == 0) return;
        return error.HttpSetHeader;
    }

    pub fn setStatusNumeric(self: *const Self, status: usize) void {
        self.h.*.status = status;
    }

    pub fn setStatus(self: *const Self, status: _module.StatusCode) void {
        self.h.*.status = @intCast(usize, @enumToInt(status));
    }

    pub fn nextParam(self: *const Self) ?HttpParam {
        if (self.h.*.params == 0) return null;
        var key: fio.FIOBJ = undefined;
        const value = fio.fiobj_hash_pop(self.h.*.params, &key);
        if (value == fio.FIOBJ_INVALID) {
            return null;
        }
        return HttpParam{
            .key = util.fio2str(key).?,
            .value = util.fio2str(value).?,
        };
    }
};

pub const HttpRequestFn = *const fn (r: [*c]fio.http_s) callconv(.C) void;
pub const SimpleHttpRequestFn = *const fn (SimpleRequest) void;

pub const SimpleHttpListenerSettings = struct {
    port: usize,
    interface: [*c]const u8 = null,
    on_request: ?SimpleHttpRequestFn,
    on_response: ?*const fn ([*c]fio.http_s) callconv(.C) void = null,
    public_folder: ?[]const u8 = null,
    max_clients: ?isize = null,
    max_body_size: ?usize = null,
    timeout: ?u8 = null,
    log: bool = false,
};

pub const SimpleHttpListener = struct {
    settings: SimpleHttpListenerSettings,

    const Self = @This();
    var the_one_and_only_listener: ?*SimpleHttpListener = null;

    pub fn init(settings: SimpleHttpListenerSettings) Self {
        return .{
            .settings = settings,
        };
    }

    // we could make it dynamic by passing a SimpleHttpListener via udata
    pub fn theOneAndOnlyRequestCallBack(r: [*c]fio.http_s) callconv(.C) void {
        if (the_one_and_only_listener) |l| {
            var req: SimpleRequest = .{
                .path = util.fio2str(r.*.path),
                .query = util.fio2str(r.*.query),
                .body = util.fio2str(r.*.body),
                .method = util.fio2str(r.*.method),
                .h = r,
            };
            l.settings.on_request.?(req);
        }
    }

    pub fn listen(self: *Self) !void {
        var pfolder: [*c]const u8 = null;
        var pfolder_len: usize = 0;

        if (self.settings.public_folder) |pf| {
            debug("SimpleHttpListener.listen(): public folder is {s}\n", .{pf});
            pfolder_len = pf.len;
            pfolder = pf.ptr;
        }

        var x: fio.http_settings_s = .{
            .on_request = if (self.settings.on_request) |_| Self.theOneAndOnlyRequestCallBack else null,
            .on_upgrade = null,
            .on_response = self.settings.on_response,
            .on_finish = null,
            .udata = null,
            .public_folder = pfolder,
            .public_folder_length = pfolder_len,
            .max_header_size = 32 * 1024,
            .max_body_size = self.settings.max_body_size orelse 50 * 1024 * 1024,
            .max_clients = self.settings.max_clients orelse 100,
            .tls = null,
            .reserved1 = 0,
            .reserved2 = 0,
            .reserved3 = 0,
            .ws_max_msg_size = 0,
            .timeout = self.settings.timeout orelse 5,
            .ws_timeout = 0,
            .log = if (self.settings.log) 1 else 0,
            .is_client = 0,
        };
        // TODO: BUG: without this print/sleep statement, -Drelease* loop forever
        // in debug2 and debug3 of hello example
        // std.debug.print("X\n", .{});
        std.time.sleep(500 * 1000 * 1000);

        var portbuf: [100]u8 = undefined;
        const printed_port = try std.fmt.bufPrintZ(&portbuf, "{d}", .{self.settings.port});

        // pub fn bufPrintZ(buf: []u8, comptime fmt: []const u8, args: anytype) BufPrintError![:0]u8 {
        //     const result = try bufPrint(buf, fmt ++ "\x00", args);
        //     return result[0 .. result.len - 1 :0];
        // }
        if (fio.http_listen(printed_port.ptr, self.settings.interface, x) == -1) {
            return error.ListenError;
        }

        // set ourselves up to handle requests:
        // TODO: do we mind the race condition?
        // the SimpleHttpRequestFn will check if this is null and not process
        // the request if it isn't set. hence, if started under full load, the
        // first request(s) might not be serviced, as long as it takes from
        // fio.http_listen() to here
        Self.the_one_and_only_listener = self;
    }
};

//
// lower level listening
//
pub const ListenSettings = struct {
    on_request: ?*const fn ([*c]fio.http_s) callconv(.C) void = null,
    on_upgrade: ?*const fn ([*c]fio.http_s, [*c]u8, usize) callconv(.C) void = null,
    on_response: ?*const fn ([*c]fio.http_s) callconv(.C) void = null,
    on_finish: ?*const fn ([*c]fio.struct_http_settings_s) callconv(.C) void = null,
    public_folder: ?[]const u8 = null,
    max_header_size: usize = 32 * 1024,
    max_body_size: usize = 50 * 1024 * 1024,
    max_clients: isize = 100,
    keepalive_timeout_s: u8 = 5,
    log: bool = false,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }
};

pub fn listen(port: [*c]const u8, interface: [*c]const u8, settings: ListenSettings) ListenError!void {
    var pfolder: [*c]const u8 = null;
    var pfolder_len: usize = 0;

    if (settings.public_folder) |pf| {
        pfolder_len = pf.len;
        pfolder = pf.ptr;
    }
    var x: fio.http_settings_s = .{
        .on_request = settings.on_request,
        .on_upgrade = settings.on_upgrade,
        .on_response = settings.on_response orelse null,
        .on_finish = settings.on_finish,
        .udata = null,
        .public_folder = pfolder,
        .public_folder_length = pfolder_len,
        .max_header_size = settings.max_header_size,
        .max_body_size = settings.max_body_size,
        .max_clients = settings.max_clients,
        .tls = null,
        .reserved1 = 0,
        .reserved2 = 0,
        .reserved3 = 0,
        .ws_max_msg_size = 0,
        .timeout = settings.keepalive_timeout_s,
        .ws_timeout = 0,
        .log = if (settings.log) 1 else 0,
        .is_client = 0,
    };
    // TODO: BUG: without this print/sleep statement, -Drelease* loop forever
    // in debug2 and debug3 of hello example
    // std.debug.print("X\n", .{});
    std.time.sleep(500 * 1000 * 1000);

    if (fio.http_listen(port, interface, x) == -1) {
        return error.ListenError;
    }
}

// lower level sendBody
pub fn sendBody(request: [*c]fio.http_s, body: []const u8) HttpError!void {
    const ret = fio.http_send_body(request, @intToPtr(
        *anyopaque,
        @ptrToInt(body.ptr),
    ), body.len);
    debug("sendBody(): ret = {}\n", .{ret});
    if (ret != -1) return error.HttpSendBody;
}
