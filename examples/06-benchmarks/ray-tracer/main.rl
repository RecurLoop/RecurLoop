// ============================================================================
// RecurLoop Application Benchmark — Fixed-Point Ray Tracer
//
// A deterministic, single-file ray tracer for the current typed `fn` backend.
// Geometry and lighting use signed i64 fixed-point arithmetic with scale 1e6.
//
// Exercises:
//   - tight nested arithmetic loops
//   - records and pointer arrays
//   - malloc/free and ownership
//   - recursive reflections
//   - ray/sphere intersection
//   - diffuse lighting and hard shadows
//   - framebuffer generation
//   - deterministic checksum validation
//   - standalone executable emission
//
// Build:
//   make example EXAMPLE=06-benchmarks/ray-tracer BUILD_TYPE=Release
//
// Run:
//   /tmp/recurloop-raytracer
//   /tmp/recurloop-raytracer 640 360
//   /tmp/recurloop-raytracer 800 450 2
//
// Output:
//   /tmp/recurloop-raytracer.ppm
// ============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
extern putchar(character:i64) -> i64 abi sysv-amd64
extern fopen(path:u8*, mode:u8*) -> u8* abi sysv-amd64
extern fclose(stream:u8*) -> i64 abi sysv-amd64
extern fprintf(stream:u8*, format:u8*, ...) -> i64 abi sysv-amd64
extern fwrite(pointer:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64


// ============================================================================
// Utilities and fixed-point math
// ============================================================================

let Util = []

let Util:parse_i64 = fn (text:u8*) -> i64 {
    var i = 0
    var sign = 1
    var value = 0

    if text[0] == 45 {
        sign = -1
        i = 1
    }

    while text[i] >= 48 && text[i] <= 57 {
        value = value * 10 + text[i] - 48
        i += 1
    }

    return value * sign
}

let FP = []

// 1.0 == 1_000_000
let FP:mul = fn (left:i64, right:i64) -> i64 {
    return left * right / 1000000
}

let FP:div = fn (left:i64, right:i64) -> i64 {
    if right == 0 {
        return 0
    }
    return left * 1000000 / right
}

let FP:abs = fn (value:i64) -> i64 {
    if value < 0 {
        return -value
    }
    return value
}

// sqrt(value / SCALE) * SCALE == isqrt(value * SCALE)
let FP:sqrt = fn (value:i64) -> i64 {
    if value <= 0 {
        return 0
    }

    var n = value * 1000000
    var x = n
    var i = 0

    while i < 48 {
        var next = (x + n / x) / 2
        if next == x {
            return x
        }
        if next == x - 1 {
            return next
        }
        x = next
        i += 1
    }

    return x
}

let FP:clamp01 = fn (value:i64) -> i64 {
    if value < 0 {
        return 0
    }
    if value > 1000000 {
        return 1000000
    }
    return value
}

let FP:to_byte = fn (value:i64) -> i64 {
    var clamped = FP:clamp01(value)
    var gamma = FP:sqrt(clamped)
    return gamma * 255 / 1000000
}


// ============================================================================
// Domain model
// ============================================================================

record Material {
    r:i64
    g:i64
    b:i64
    reflectivity:i64
}

record Sphere {
    x:i64
    y:i64
    z:i64
    radius:i64
    material:i64
}

record Ray {
    ox:i64
    oy:i64
    oz:i64
    dx:i64
    dy:i64
    dz:i64
}

record Color {
    r:i64
    g:i64
    b:i64
}

record Hit {
    t:i64
    sphere:Sphere*
}

record Scene {
    sphere_count:i64
    material_count:i64
    spheres:Sphere**
    materials:Material**
}

record RenderStats {
    primary_rays:i64
    trace_calls:i64
    sphere_tests:i64
    shadow_rays:i64
    reflection_rays:i64
    pixels:i64
    checksum:i64
    min_channel:i64
    max_channel:i64
}

record TraceScratch {
    rays:Ray**
    colors:Color**
    hits:Hit**
    temp_hit:Hit*
    shadow_ray:Ray*
    shadow_hit:Hit*
}


// ============================================================================
// Basic lifecycle helpers
// ============================================================================

let Material:new = fn (r:i64, g:i64, b:i64, reflectivity:i64) -> Material* {
    var material:Material* = cast(Material*, malloc(32))
    material.r = r
    material.g = g
    material.b = b
    material.reflectivity = reflectivity
    return material
}

let Material:destroy = fn (self:Material*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Sphere:new = fn (x:i64, y:i64, z:i64, radius:i64, material:i64) -> Sphere* {
    var sphere:Sphere* = cast(Sphere*, malloc(40))
    sphere.x = x
    sphere.y = y
    sphere.z = z
    sphere.radius = radius
    sphere.material = material
    return sphere
}

let Sphere:destroy = fn (self:Sphere*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Ray:new = fn () -> Ray* {
    var ray:Ray* = cast(Ray*, malloc(48))
    ray.ox = 0
    ray.oy = 0
    ray.oz = 0
    ray.dx = 0
    ray.dy = 0
    ray.dz = -1000000
    return ray
}

let Ray:destroy = fn (self:Ray*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Color:new = fn () -> Color* {
    var color:Color* = cast(Color*, malloc(24))
    color.r = 0
    color.g = 0
    color.b = 0
    return color
}

let Color:destroy = fn (self:Color*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Hit:new = fn () -> Hit* {
    var hit:Hit* = cast(Hit*, malloc(16))
    hit.t = -1
    hit.sphere = cast(Sphere*, 0)
    return hit
}

let Hit:destroy = fn (self:Hit*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let RenderStats:new = fn () -> RenderStats* {
    var stats:RenderStats* = cast(RenderStats*, malloc(72))
    stats.primary_rays = 0
    stats.trace_calls = 0
    stats.sphere_tests = 0
    stats.shadow_rays = 0
    stats.reflection_rays = 0
    stats.pixels = 0
    stats.checksum = 17
    stats.min_channel = 255
    stats.max_channel = 0
    return stats
}

let RenderStats:destroy = fn (self:RenderStats*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let RenderStats:add_pixel = fn (self:RenderStats*, r:i64, g:i64, b:i64) -> i64 {
    self.pixels += 1

    if r < self.min_channel {
        self.min_channel = r
    }
    if g < self.min_channel {
        self.min_channel = g
    }
    if b < self.min_channel {
        self.min_channel = b
    }
    if r > self.max_channel {
        self.max_channel = r
    }
    if g > self.max_channel {
        self.max_channel = g
    }
    if b > self.max_channel {
        self.max_channel = b
    }

    self.checksum = (self.checksum * 131 + r * 17 + g * 19 + b * 23 + self.pixels) % 2147483647
    return 0
}


// ============================================================================
// Vector/ray operations
// ============================================================================

let Ray:normalize_direction = fn (self:Ray*) -> i64 {
    var xx = FP:mul(self.dx, self.dx)
    var yy = FP:mul(self.dy, self.dy)
    var zz = FP:mul(self.dz, self.dz)
    var length = FP:sqrt(xx + yy + zz)

    if length <= 1 {
        self.dx = 0
        self.dy = 0
        self.dz = -1000000
        return 0
    }

    self.dx = FP:div(self.dx, length)
    self.dy = FP:div(self.dy, length)
    self.dz = FP:div(self.dz, length)
    return 0
}

let Sphere:intersect = fn (self:Sphere*, ray:Ray*, out:Hit*) -> i64 {
    var lx = ray.ox - self.x
    var ly = ray.oy - self.y
    var lz = ray.oz - self.z

    var b = FP:mul(lx, ray.dx) + FP:mul(ly, ray.dy) + FP:mul(lz, ray.dz)
    var c = FP:mul(lx, lx) + FP:mul(ly, ly) + FP:mul(lz, lz) - FP:mul(self.radius, self.radius)
    var discriminant = FP:mul(b, b) - c

    if discriminant < 0 {
        out.t = -1
        out.sphere = cast(Sphere*, 0)
        return 0
    }

    var root = FP:sqrt(discriminant)
    var t0 = -b - root
    var t1 = -b + root

    if t0 > 100 {
        out.t = t0
        out.sphere = self
        return 1
    }

    if t1 > 100 {
        out.t = t1
        out.sphere = self
        return 1
    }

    out.t = -1
    out.sphere = cast(Sphere*, 0)
    return 0
}


// ============================================================================
// Scene lifecycle
// ============================================================================

let Scene:new = fn (sphere_capacity:i64, material_capacity:i64) -> Scene* {
    var scene:Scene* = cast(Scene*, malloc(32))
    scene.sphere_count = 0
    scene.material_count = 0
    scene.spheres = cast(Sphere**, malloc(sphere_capacity * 8))
    scene.materials = cast(Material**, malloc(material_capacity * 8))
    return scene
}

let Scene:add_material = fn (self:Scene*, material:Material*) -> i64 {
    var index = self.material_count
    self.materials[index] = material
    self.material_count += 1
    return index
}

let Scene:add_sphere = fn (self:Scene*, sphere:Sphere*) -> i64 {
    self.spheres[self.sphere_count] = sphere
    self.sphere_count += 1
    return 0
}

let Scene:destroy = fn (self:Scene*) -> i64 {
    var i = 0
    while i < self.sphere_count {
        Sphere:destroy(self.spheres[i])
        i += 1
    }

    i = 0
    while i < self.material_count {
        Material:destroy(self.materials[i])
        i += 1
    }

    free(cast(u8*, self.spheres))
    free(cast(u8*, self.materials))
    free(cast(u8*, self))
    return 0
}

let Scene:demo = fn () -> Scene* {
    var scene = Scene:new(16, 16)

    var red = Scene:add_material(scene, Material:new(820000, 160000, 120000, 100000))
    var blue = Scene:add_material(scene, Material:new(120000, 240000, 880000, 180000))
    var green = Scene:add_material(scene, Material:new(160000, 720000, 280000, 50000))
    var gold = Scene:add_material(scene, Material:new(920000, 620000, 120000, 280000))
    var mirror = Scene:add_material(scene, Material:new(720000, 780000, 860000, 720000))
    var ground = Scene:add_material(scene, Material:new(660000, 680000, 720000, 40000))

    Scene:add_sphere(scene, Sphere:new(-1550000, -50000, -1450000, 950000, red))
    Scene:add_sphere(scene, Sphere:new(0, 250000, -2150000, 1200000, blue))
    Scene:add_sphere(scene, Sphere:new(1650000, -180000, -1750000, 820000, green))
    Scene:add_sphere(scene, Sphere:new(-650000, 1550000, -3250000, 550000, gold))
    Scene:add_sphere(scene, Sphere:new(1050000, 1280000, -3050000, 470000, mirror))
    Scene:add_sphere(scene, Sphere:new(0, -1001050000, -2000000, 1000000000, ground))

    return scene
}


// ============================================================================
// Scratch storage
// ============================================================================

let TraceScratch:new = fn () -> TraceScratch* {
    var scratch:TraceScratch* = cast(TraceScratch*, malloc(48))
    scratch.rays = cast(Ray**, malloc(4 * 8))
    scratch.colors = cast(Color**, malloc(4 * 8))
    scratch.hits = cast(Hit**, malloc(4 * 8))

    var i = 0
    while i < 4 {
        scratch.rays[i] = Ray:new()
        scratch.colors[i] = Color:new()
        scratch.hits[i] = Hit:new()
        i += 1
    }

    scratch.temp_hit = Hit:new()
    scratch.shadow_ray = Ray:new()
    scratch.shadow_hit = Hit:new()
    return scratch
}

let TraceScratch:destroy = fn (self:TraceScratch*) -> i64 {
    var i = 0
    while i < 4 {
        Ray:destroy(self.rays[i])
        Color:destroy(self.colors[i])
        Hit:destroy(self.hits[i])
        i += 1
    }

    Hit:destroy(self.temp_hit)
    Ray:destroy(self.shadow_ray)
    Hit:destroy(self.shadow_hit)
    free(cast(u8*, self.rays))
    free(cast(u8*, self.colors))
    free(cast(u8*, self.hits))
    free(cast(u8*, self))
    return 0
}


// ============================================================================
// Matching and shading
// ============================================================================

let Scene:nearest = fn (self:Scene*, ray:Ray*, best:Hit*, temp:Hit*, stats:RenderStats*) -> i64 {
    best.t = 2000000000
    best.sphere = cast(Sphere*, 0)

    var i = 0
    while i < self.sphere_count {
        stats.sphere_tests += 1
        Sphere:intersect(self.spheres[i], ray, temp)

        if temp.t > 100 && temp.t < best.t {
            best.t = temp.t
            best.sphere = temp.sphere
        }

        i += 1
    }

    if cast(i64, best.sphere) == 0 {
        best.t = -1
        return 0
    }
    return 1
}

let Scene:shadowed = fn (self:Scene*, ray:Ray*, temp:Hit*, stats:RenderStats*) -> i64 {
    var i = 0
    stats.shadow_rays += 1

    while i < self.sphere_count {
        stats.sphere_tests += 1
        Sphere:intersect(self.spheres[i], ray, temp)
        if temp.t > 100 && temp.t < 1000000000 {
            return 1
        }
        i += 1
    }
    return 0
}

let Scene:trace = fn (self:Scene*, scratch:TraceScratch*, depth:i64, ray:Ray*, color:Color*, stats:RenderStats*) -> i64 {
    stats.trace_calls += 1

    var best = scratch.hits[depth]
    if Scene:nearest(self, ray, best, scratch.temp_hit, stats) == 0 {
        var horizon = (ray.dy + 1000000) / 2
        horizon = FP:clamp01(horizon)
        color.r = 80000 + FP:mul(340000, horizon)
        color.g = 120000 + FP:mul(420000, horizon)
        color.b = 200000 + FP:mul(580000, horizon)
        return 0
    }

    var sphere = best.sphere
    var material = self.materials[sphere.material]

    var px = ray.ox + FP:mul(ray.dx, best.t)
    var py = ray.oy + FP:mul(ray.dy, best.t)
    var pz = ray.oz + FP:mul(ray.dz, best.t)

    var nx = FP:div(px - sphere.x, sphere.radius)
    var ny = FP:div(py - sphere.y, sphere.radius)
    var nz = FP:div(pz - sphere.z, sphere.radius)

    var lx = -550000
    var ly = 800000
    var lz = 300000
    var light_len = FP:sqrt(FP:mul(lx, lx) + FP:mul(ly, ly) + FP:mul(lz, lz))
    lx = FP:div(lx, light_len)
    ly = FP:div(ly, light_len)
    lz = FP:div(lz, light_len)

    var diffuse = FP:mul(nx, lx) + FP:mul(ny, ly) + FP:mul(nz, lz)
    if diffuse < 0 {
        diffuse = 0
    }

    var shadow = scratch.shadow_ray
    shadow.ox = px + FP:mul(nx, 1000)
    shadow.oy = py + FP:mul(ny, 1000)
    shadow.oz = pz + FP:mul(nz, 1000)
    shadow.dx = lx
    shadow.dy = ly
    shadow.dz = lz

    if Scene:shadowed(self, shadow, scratch.shadow_hit, stats) != 0 {
        diffuse = FP:mul(diffuse, 180000)
    }

    var brightness = 100000 + FP:mul(diffuse, 900000)
    var base_r = FP:mul(material.r, brightness)
    var base_g = FP:mul(material.g, brightness)
    var base_b = FP:mul(material.b, brightness)

    if depth < 2 && material.reflectivity > 1000 {
        var reflection = scratch.rays[depth + 1]
        var reflected_color = scratch.colors[depth + 1]
        var ndotd = FP:mul(ray.dx, nx) + FP:mul(ray.dy, ny) + FP:mul(ray.dz, nz)
        var twice = ndotd * 2

        reflection.ox = px + FP:mul(nx, 2000)
        reflection.oy = py + FP:mul(ny, 2000)
        reflection.oz = pz + FP:mul(nz, 2000)
        reflection.dx = ray.dx - FP:mul(twice, nx)
        reflection.dy = ray.dy - FP:mul(twice, ny)
        reflection.dz = ray.dz - FP:mul(twice, nz)
        Ray:normalize_direction(reflection)

        stats.reflection_rays += 1
        Scene:trace(self, scratch, depth + 1, reflection, reflected_color, stats)

        var keep = 1000000 - material.reflectivity
        color.r = FP:mul(base_r, keep) + FP:mul(reflected_color.r, material.reflectivity)
        color.g = FP:mul(base_g, keep) + FP:mul(reflected_color.g, material.reflectivity)
        color.b = FP:mul(base_b, keep) + FP:mul(reflected_color.b, material.reflectivity)
    } else {
        color.r = base_r
        color.g = base_g
        color.b = base_b
    }

    return 0
}


// ============================================================================
// Renderer
// ============================================================================

let render = fn (scene:Scene*, width:i64, height:i64, samples:i64, framebuffer:u8*, stats:RenderStats*) -> i64 {
    var scratch = TraceScratch:new()
    defer TraceScratch:destroy(scratch)

    var aspect = width * 1000000 / height
    var y = 0

    while y < height {
        var x = 0
        while x < width {
            var sum_r = 0
            var sum_g = 0
            var sum_b = 0
            var sample = 0

            while sample < samples {
                var jitter_x = 500000
                var jitter_y = 500000

                if samples > 1 {
                    var sx = sample % 2
                    var sy = (sample / 2) % 2
                    jitter_x = 250000 + sx * 500000
                    jitter_y = 250000 + sy * 500000
                }

                var fx = (x * 1000000 + jitter_x) / width
                var fy = (y * 1000000 + jitter_y) / height
                var screen_x = FP:mul(fx * 2 - 1000000, aspect)
                var screen_y = 1000000 - fy * 2

                var ray = scratch.rays[0]
                ray.ox = 0
                ray.oy = 450000
                ray.oz = 4600000
                ray.dx = screen_x
                ray.dy = FP:mul(screen_y, 920000) - 60000
                ray.dz = -1720000
                Ray:normalize_direction(ray)

                var color = scratch.colors[0]
                Scene:trace(scene, scratch, 0, ray, color, stats)
                sum_r += color.r
                sum_g += color.g
                sum_b += color.b
                stats.primary_rays += 1
                sample += 1
            }

            var avg_r = sum_r / samples
            var avg_g = sum_g / samples
            var avg_b = sum_b / samples
            var r = FP:to_byte(avg_r)
            var g = FP:to_byte(avg_g)
            var b = FP:to_byte(avg_b)

            var offset = (y * width + x) * 3
            framebuffer[offset + 0] = cast(u8, r)
            framebuffer[offset + 1] = cast(u8, g)
            framebuffer[offset + 2] = cast(u8, b)
            RenderStats:add_pixel(stats, r, g, b)

            x += 1
        }
        y += 1
    }

    return 0
}


// ============================================================================
// Output and preview
// ============================================================================

let write_ppm = fn (path:u8*, width:i64, height:i64, framebuffer:u8*) -> i64 {
    var file = fopen(path, "wb")
    if cast(i64, file) == 0 {
        return -1
    }

    fprintf(file, "P6\n%lld %lld\n255\n", width, height)
    fwrite(framebuffer, 1, width * height * 3, file)
    fclose(file)
    return 0
}

let print_preview = fn (width:i64, height:i64, framebuffer:u8*) -> i64 {
    var preview_w = 64
    var preview_h = 20

    if width < preview_w {
        preview_w = width
    }
    if height < preview_h {
        preview_h = height
    }

    printf("\nPreview\n-------\n")

    var py = 0
    while py < preview_h {
        var y = py * height / preview_h
        var px = 0

        while px < preview_w {
            var x = px * width / preview_w
            var offset = (y * width + x) * 3
            var lum = (framebuffer[offset + 0] * 3 + framebuffer[offset + 1] * 6 + framebuffer[offset + 2]) / 10

            var symbol = 32
            if lum >= 26 {
                symbol = 46
            }
            if lum >= 52 {
                symbol = 58
            }
            if lum >= 78 {
                symbol = 45
            }
            if lum >= 104 {
                symbol = 61
            }
            if lum >= 130 {
                symbol = 43
            }
            if lum >= 156 {
                symbol = 42
            }
            if lum >= 182 {
                symbol = 35
            }
            if lum >= 208 {
                symbol = 37
            }
            if lum >= 234 {
                symbol = 64
            }
            putchar(symbol)
            px += 1
        }

        printf("\n")
        py += 1
    }
    return 0
}


// ============================================================================
// Self-test
// ============================================================================

let self_test = fn () -> i64 {
    var passed = 0

    var root = FP:sqrt(9000000)
    if root >= 2999999 && root <= 3000001 {
        passed += 1
    }

    var ray = Ray:new()
    defer Ray:destroy(ray)
    ray.dx = 3000000
    ray.dy = 4000000
    ray.dz = 0
    Ray:normalize_direction(ray)
    if ray.dx >= 599999 && ray.dx <= 600001 && ray.dy >= 799999 && ray.dy <= 800001 {
        passed += 1
    }

    var sphere = Sphere:new(0, 0, 0, 1000000, 0)
    defer Sphere:destroy(sphere)
    var hit = Hit:new()
    defer Hit:destroy(hit)

    ray.ox = 0
    ray.oy = 0
    ray.oz = 3000000
    ray.dx = 0
    ray.dy = 0
    ray.dz = -1000000
    Sphere:intersect(sphere, ray, hit)
    if hit.t >= 1999999 && hit.t <= 2000001 {
        passed += 1
    }

    ray.oy = 3000000
    Sphere:intersect(sphere, ray, hit)
    if hit.t < 0 {
        passed += 1
    }

    if FP:to_byte(0) == 0 && FP:to_byte(1000000) == 255 {
        passed += 1
    }

    var mid = FP:to_byte(250000)
    if mid >= 127 && mid <= 128 {
        passed += 1
    }

    return passed
}


// ============================================================================
// Report and entry point
// ============================================================================

let print_report = fn (width:i64, height:i64, samples:i64, stats:RenderStats*) -> i64 {
    printf("\n============================================================\n")
    printf(" RecurLoop Fixed-Point Ray Tracer Benchmark\n")
    printf("============================================================\n")
    printf("resolution:          %lld x %lld\n", width, height)
    printf("samples / pixel:     %lld\n", samples)
    printf("primary rays:        %lld\n", stats.primary_rays)
    printf("trace calls:         %lld\n", stats.trace_calls)
    printf("sphere tests:        %lld\n", stats.sphere_tests)
    printf("shadow rays:         %lld\n", stats.shadow_rays)
    printf("reflection rays:     %lld\n", stats.reflection_rays)
    printf("pixels:              %lld\n", stats.pixels)
    printf("channel range:       %lld .. %lld\n", stats.min_channel, stats.max_channel)
    printf("checksum:            %lld\n", stats.checksum)
    printf("output:              /tmp/recurloop-raytracer.ppm\n")
    printf("============================================================\n")
    return 0
}

emit executable "/tmp/recurloop-raytracer" raytracer_main = fn (argc:i64, argv:u8**) -> i64 {
    var width = 480
    var height = 270
    var samples = 1

    if argc > 1 {
        width = Util:parse_i64(argv[1])
    }
    if argc > 2 {
        height = Util:parse_i64(argv[2])
    }
    if argc > 3 {
        samples = Util:parse_i64(argv[3])
    }

    if width <= 0 || height <= 0 {
        printf("error: width and height must be greater than zero\n")
        return 1
    }

    if samples < 1 {
        samples = 1
    }
    if samples > 4 {
        samples = 4
    }

    var test_score = self_test()
    if test_score != 6 {
        printf("self-test failed: %lld/6 checks passed\n", test_score)
        return 2
    }
    printf("self-test: 6/6 checks passed\n")

    var scene = Scene:demo()
    defer Scene:destroy(scene)
    var stats = RenderStats:new()
    defer RenderStats:destroy(stats)
    var framebuffer:u8* = cast(u8*, malloc(width * height * 3))
    defer free(framebuffer)

    render(scene, width, height, samples, framebuffer, stats)

    if write_ppm("/tmp/recurloop-raytracer.ppm", width, height, framebuffer) != 0 {
        printf("error: failed to write PPM output\n")
        return 3
    }

    print_report(width, height, samples, stats)
    print_preview(width, height, framebuffer)
    printf("done\n")
    return 0
}

link clear

debug:stats
