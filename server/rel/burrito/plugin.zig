// The tlon launcher's plugin (Burrito calls burrito_plugin_entry before it boots the VM): for
// `tlon office`, exec the office TUI with the real terminal instead of booting the server. The TUI
// for this target rides here xz-compressed (staged by Server.Package.Office); it is written out once
// into the launcher's install dir, which is named by the build, so a new build never runs an old TUI.
const std = @import("std");
const builtin = @import("builtin");
const c = std.c;

const OFFICE_XZ = @embedFile("office.xz");

extern "c" fn _NSGetArgc() *c_int;
extern "c" fn _NSGetArgv() *[*:null]?[*:0]u8;

pub fn burrito_plugin_entry(install_dir: []const u8, program_manifest_json: []const u8) void {
    _ = program_manifest_json;
    const gpa = std.heap.c_allocator;
    const argv = args(gpa) catch return;
    if (argv.len < 2 or !std.mem.eql(u8, std.mem.span(argv[1].?), "office")) return;
    office(gpa, install_dir, argv) catch |e| {
        std.debug.print("tlon office: {t}\n", .{e});
        c.exit(1);
    };
}

fn office(gpa: std.mem.Allocator, install_dir: []const u8, argv: []const ?[*:0]const u8) !void {
    const path = try std.fmt.allocPrintSentinel(gpa, "{s}/tlon-office", .{install_dir}, 0);
    if (c.access(path, 1) != 0) try unpack(gpa, path);
    // the TUI's own argv: its path, then whatever followed `office`
    const tui_argv = try gpa.allocSentinel(?[*:0]const u8, argv.len - 1, null);
    tui_argv[0] = path;
    for (argv[2..], 1..) |a, i| tui_argv[i] = a;
    _ = c.execve(path, tui_argv, @ptrCast(c.environ));
    return error.ExecFailed;
}

fn unpack(gpa: std.mem.Allocator, path: [:0]const u8) !void {
    var input: std.Io.Reader = .fixed(OFFICE_XZ);
    var xz = try std.compress.xz.Decompress.init(&input, gpa, try gpa.alloc(u8, 1 << 16));
    defer xz.deinit();
    const bytes = try xz.reader.allocRemaining(gpa, .unlimited);
    const tmp = try std.fmt.allocPrintSentinel(gpa, "{s}.part", .{path}, 0);
    const fd = c.open(tmp, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c.mode_t, 0o755));
    if (fd < 0) return error.CannotWrite;
    var off: usize = 0;
    while (off < bytes.len) {
        const n = c.write(fd, bytes[off..].ptr, bytes.len - off);
        if (n <= 0) return error.CannotWrite;
        off += @intCast(n);
    }
    _ = c.close(fd);
    if (c.chmod(tmp, 0o755) != 0 or c.rename(tmp, path) != 0) return error.CannotWrite;
}

// this process's argv: macOS hands it over through libc; Linux has it in /proc
fn args(gpa: std.mem.Allocator) ![]const ?[*:0]const u8 {
    if (builtin.os.tag == .macos) {
        const n: usize = @intCast(_NSGetArgc().*);
        return @ptrCast(_NSGetArgv().*[0..n]);
    }
    const fd = c.open("/proc/self/cmdline", .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.NoArgs;
    defer _ = c.close(fd);
    var buf: std.ArrayList(u8) = .empty;
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = c.read(fd, &chunk, chunk.len);
        if (n <= 0) break;
        try buf.appendSlice(gpa, chunk[0..@intCast(n)]);
    }
    var list: std.ArrayList(?[*:0]const u8) = .empty;
    var start: usize = 0;
    for (buf.items, 0..) |b, i| if (b == 0) {
        buf.items[i] = 0;
        try list.append(gpa, @ptrCast(buf.items[start..i :0].ptr));
        start = i + 1;
    };
    return list.items;
}
