const std = @import("std");
const eql = std.mem.eql;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const Flags = struct {
    count: bool = false,
    repeated: bool = false,
    uniq: bool = false,

    fn output(self: Flags, writer: *Writer, count: usize, line: []const u8) !void {
        if (self.repeated and count <= 1) return;
        if (self.uniq and count > 1) return;
        if (self.count) {
            try writer.print("{d} {s}\n", .{ count, line });
        } else {
            try writer.print("{s}\n", .{line});
        }
    }
};

const Args = struct {
    flags: Flags,
    in_file_path: ?[]const u8,
    out_file_path: ?[]const u8,

    fn parse(args: [][:0]u8) Args {
        var flags = Flags{};
        var in_file: ?[]const u8 = null;
        var out_file: ?[]const u8 = null;
        var stdin_explicit = false;

        for (args[1..]) |arg| {
            if (eql(u8, arg, "-")) {
                stdin_explicit = true;
            } else if (eql(u8, arg, "-c") or eql(u8, arg, "--count")) {
                flags.count = true;
            } else if (eql(u8, arg, "-d") or eql(u8, arg, "--repeated")) {
                flags.repeated = true;
            } else if (eql(u8, arg, "-u")) {
                flags.uniq = true;
            } else if (in_file == null and !stdin_explicit) {
                in_file = arg;
            } else {
                out_file = arg;
            }
        }
        return .{ .flags = flags, .in_file_path = in_file, .out_file_path = out_file };
    }
};

fn process(reader: *Reader, writer: *Writer, flags: Flags) !void {
    var last_line: []u8 = "";
    var count: usize = 0;

    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        if (eql(u8, last_line, line)) {
            count += 1;
        } else {
            if (count > 0) try flags.output(writer, count, last_line);
            last_line = line;
            count = 1;
        }
    } else |err| switch (err) {
        error.EndOfStream => try flags.output(writer, count, last_line),
        else => return err,
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const parsed = Args.parse(args);

    var in_buf: [8192]u8 = undefined;
    var out_buf: [8192]u8 = undefined;

    var out_file: ?std.fs.File = null;
    defer if (out_file) |f| f.close();

    var f_writer = if (parsed.out_file_path) |path| blk: {
        out_file = try std.fs.cwd().createFile(path, .{});
        break :blk out_file.?.writer(&out_buf);
    } else std.fs.File.stdout().writer(&out_buf);

    var f_reader = if (parsed.in_file_path) |path| blk: {
        const f = try std.fs.cwd().openFile(path, .{});
        break :blk f.reader(&in_buf);
    } else std.fs.File.stdin().reader(&in_buf);

    try process(&f_reader.interface, &f_writer.interface, parsed.flags);
    try f_writer.interface.flush();
}
