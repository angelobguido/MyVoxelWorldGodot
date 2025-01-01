#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(binding = 0, set = 1, std430) restrict buffer CameraData {
	vec3 camera_position;
    mat4 inv_proj;
    mat4 inv_view;
} camera_data;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    float time;
} p;

struct Sphere {
    vec3 center;
    float radius;
    vec3 color;
    float padding;
};

struct Ray {
    vec3 origin;
    vec3 direction;
};

// const mat4 inv_view = mat4(vec4(1, 0, 0, 0),
//                            vec4(0, 1, 0, 0),
//                            vec4(0, 0, 1, 0),
//                            vec4(0, 0, 0, 1));

const vec3 sun_direction = normalize(vec3(0, 0, -1.0));

bool hit(Ray ray, Sphere sphere, inout float t) {
    vec3 oc = ray.origin - sphere.center;

    float a = dot(ray.direction, ray.direction);
    float b = 2 * dot(oc, ray.direction);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;

    float discriminant = b * b - 4 * a * c;
    if (discriminant < 0) {
        return false;
    }

    float t_hit = (-b - sqrt(discriminant)) / (2 * a);
    if (t_hit < t && t_hit > 0.0001) {
        t = t_hit;
        return true;
    }
    else {
        return false;
    }
}

void main() {

    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = p.screen_size;
    mat4 inv_proj = camera_data.inv_proj;
    mat4 inv_view = camera_data.inv_view;

    if (pixel.x >= size.x || pixel.y >= size.y) {
        return;
    }

    Ray ray;
    ray.origin = camera_data.camera_position;

    vec2 coord = vec2( float(pixel.x) / float(size.x), float(pixel.y) / float(size.y));
    coord = coord * 2 - 1;

    vec4 target = inv_proj * vec4(coord.x, coord.y, 1, 1);
    ray.direction = vec3(inv_view * vec4(normalize(vec3(target) / target.w), 0));

    Sphere sphere;
    sphere.center = vec3(0.0, p.time/10, -6.0);
    sphere.radius = 1.0;
    sphere.color = vec3(1.0, 0.75, 0.5);

    float t = 99999;

    vec3 color = vec3(0.0);
    if (hit(ray, sphere, t)) {
        vec3 hit_pos = ray.origin + t * ray.direction;
        vec3 normal = normalize(hit_pos - sphere.center);
        float light_amount = max(0.0, dot(-sun_direction, normal));
        color =  light_amount*sphere.color;
    }

    imageStore(screen_tex, pixel, vec4(color, 1.0));
}