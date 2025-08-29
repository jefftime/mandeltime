const std = @import("std");
const print = std.debug.print;
const sqrt = std.math.sqrt;
const pow = std.math.pow;
const exp = std.math.exp;
const cos = std.math.cos;

const float = f64;

const WIDTH: usize = 8192;
const HEIGHT: usize = 8192;
const NTHREADS: usize = 12;

const RESOLUTION: vec2 = .{ .x = WIDTH, .y = HEIGHT };
const E: float = 2.71828;
const SCALE: float = 11.5;
const BAILOUT: float = 2.0;
const PI: float = 3.141592653589;
const ITERLIMIT: usize = 2000;

const vec3 = struct {
    x: float,
    y: float,
    z: float,

    pub fn cosine(a: vec3) vec3 {
        return .{
            .x = cos(a.x),
            .y = cos(a.y),
            .z = cos(a.z),
        };
    }

    pub fn add(a: vec3, b: vec3) vec3 {
        return .{
            .x = a.x + b.x,
            .y = a.y + b.y,
            .z = a.z + b.z,
        };
    }

    pub fn mul(a: vec3, b: vec3) vec3 {
        return .{
            .x = a.x * b.x,
            .y = a.y * b.y,
            .z = a.z * b.z,
        };
    }

    pub fn mulf(a: vec3, b: float) vec3 {
        return .{
            .x = a.x * b,
            .y = a.y * b,
            .z = a.z * b,
        };
    }
};

const vec2 = struct {
    x: float,
    y: float,

    pub fn mag(a: vec2) float {
        return sqrt(pow(float, a.x, 2.0) + pow(float, a.y, 2.0));
    }

    pub fn add(a: vec2, b: vec2) vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: vec2, b: vec2) vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn mul(a: vec2, b: vec2) vec2 {
        return .{ .x = a.x * b.x, .y = a.y * b.y };
    }

    pub fn mulf(a: vec2, b: float) vec2 {
        return .{ .x = a.x * b, .y = a.y * b };
    }

    pub fn div(a: vec2, b: vec2) vec2 {
        return .{ .x = a.x / b.x, .y = a.y / b.y };
    }

    pub fn divf(a: vec2, b: float) vec2 {
        return .{ .x = a.x / b, .y = a.y / b };
    }

    pub fn i_mul(a: vec2, b: vec2) vec2 {
        return .{
            .x = (a.x * b.x) - (a.y * b.y),
            .y = (a.x * b.y) + (a.y * b.x),
        };
    }
};

const Image = struct {
    width: u32,
    height: u32,
    data: []u8, // [r, g, b, r, g, b, ...]

    pub fn init(al: std.mem.Allocator, width: u32, height: u32) !Image {
        return .{
            .width = width,
            .height = height,
            .data = try al.alloc(u8, width * height * 3),
        };
    }

    pub fn get(self: *Image, x: usize, y: usize) ?[]u8 {
        if (x >= self.width or y >= self.height) return null;

        const start = ((y * self.width) + x) * 3;
        return self.data[start .. start + 3];
    }

    pub fn to_ppm(self: *Image, file: std.fs.File) !void {
        var header: [24]u8 = undefined;

        _ = try file.write(try std.fmt.bufPrint(&header, "P6 {} {} {} ", .{ self.width, self.height, 255 }));
        _ = try file.write(self.data);
    }
};

fn color(t: float) [3]u8 {
    const a = vec3{ .x = 0.5, .y = 0.5, .z = 0.5 };
    const b = vec3{ .x = 0.5, .y = 0.5, .z = 0.5 };
    const c = vec3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    const d = vec3{ .x = 0.3, .y = 0.2, .z = 0.2 };
    const result = a.add(b.mul(c.mulf(t).add(d).mulf(2.0 * PI).cosine()));
    // print("result: {}\n", .{result});

    return .{
        @intFromFloat(255.0 * result.x),
        @intFromFloat(255.0 * result.y),
        @intFromFloat(255.0 * result.z),
    };
}

fn shade(frag_coord: vec2) [3]u8 {
    var pos = frag_coord.mulf(2.0).sub(RESOLUTION).divf(RESOLUTION.y);
    const scalefactor = E / exp(SCALE + 1.0);
    pos = pos.mulf(scalefactor);

    var z: vec2 = .{ .x = 0.0, .y = 0.0 };
    var c = pos;
    c = c.add(.{ .x = -0.74273, .y = 0.1157 });
    var iter: usize = 0;
    while (z.mag() < BAILOUT) {
        z = z.i_mul(z).add(c);
        iter += 1;
        if (iter >= ITERLIMIT) break;
    }

    const density: float = @as(float, @floatFromInt(iter)) / @as(float, @floatFromInt(ITERLIMIT));

    return if (iter >= ITERLIMIT)
        .{ 0, 0, 0 }
    else
        color(density);
}

fn thread_fn(index: usize, image: *Image) void {
    const hstart = (HEIGHT / NTHREADS) * index;
    const hend = (HEIGHT / NTHREADS) * (index + 1);

    for (hstart..hend) |j| {
        for (0..WIDTH) |i| {
            const pixel = image.get(i, j) orelse @panic("Invalid index");
            const frag_color = shade(.{
                .x = @floatFromInt(i),
                .y = @floatFromInt(j),
            });
            pixel[0] = frag_color[0];
            pixel[1] = frag_color[1];
            pixel[2] = frag_color[2];
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = arena.allocator();

    var image = try Image.init(al, WIDTH, HEIGHT);

    var threads: [NTHREADS]std.Thread = undefined;
    inline for (0..NTHREADS) |i| {
        threads[i] = try std.Thread.spawn(
            .{ .allocator = al },
            thread_fn,
            .{ i, &image },
        );
    }
    inline for (threads) |thread| thread.join();

    // for (0..HEIGHT) |j| {
    //     for (0..WIDTH) |i| {
    //         const pixel = image.get(i, j) orelse @panic("Invalid index");
    //         const frag_color = shade(.{
    //             .x = @floatFromInt(i),
    //             .y = @floatFromInt(j),
    //         });
    //         pixel[0] = frag_color[0];
    //         pixel[1] = frag_color[1];
    //         pixel[2] = frag_color[2];
    //     }
    // }

    var outfile = try std.fs.cwd().createFile("out.ppm", .{});
    defer outfile.close();

    try image.to_ppm(outfile);

    return;
}
