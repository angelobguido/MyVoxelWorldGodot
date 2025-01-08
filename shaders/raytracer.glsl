#[compute]
#version 450

#define GLOBAL_SEED 10
#define LIMIT 200
#define WORLD_SIZE 500
#define EPSILON 1e-4
#define ACCUMULATIONS 1

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(binding = 0, set = 2) uniform sampler2D noise_tex;

layout(binding = 0, set = 1, std430) restrict buffer CameraData {
	vec3 position;
    mat4 inv_proj;
    mat4 inv_view;
} camera_data;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
} params;

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

struct HitPayload {
    float hit_distance;
    vec3 position;
    vec3 normal;
    int material_index;
};

struct Material {
    vec3 albedo;
    float roughness;
    float metallic;
    vec3 emission_color;
    float emission_power;
};

const Material[] materials = {
    Material(vec3(0,0,0), 0, 0, vec3(1), 0),
    Material(vec3(0.7,0.4,0), 1, 0, vec3(1,0,0), 0),
    Material(vec3(0,0.7,0.1), 0.7, 0, vec3(0,1,0), 0),
    Material(vec3(0.5,0.5,0.5), 0, 0, vec3(1,1,1), 10),
    Material(vec3(0.7,0.7,0.9), 0.3, 0, vec3(1,1,1), 0)
};

const vec3 sun_direction = normalize(vec3(0, -1, 0));
const vec3 sun_emission_color = vec3(1.0, 1.0, 0.9);
const float sun_emission_power = 1.0;

const ivec3 grid_size = ivec3(WORLD_SIZE, 100, WORLD_SIZE);
const int bounces = 10;
const vec3 background_color = vec3(0.6, 0.7, 0.9);

int ray_remaining_distance = LIMIT;

uint PCGHash(uint seed)
{
    uint state = seed * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

int accessWorldRandom(int x, int y, int z){

    vec2 uv = vec2(x, z) / vec2(grid_size.x, grid_size.z);

    float noise = texture(noise_tex, uv).r;

    if(y > int(noise * grid_size.y))
        return 0;

    int unified_value = x + y * 1000 + z * 1000000;

    return int(PCGHash(unified_value + GLOBAL_SEED))%5;
}

// Utility function to calculate intersection with grid boundaries
bool intersectGridBounds(Ray ray, out ivec3 voxel_position, out float t_entry, out vec3 normal) {

    vec3 step = sign(ray.direction);

    vec3 t_min = (vec3(0.0) - ray.origin) / ray.direction;
    vec3 t_max = (vec3(grid_size) - ray.origin) / ray.direction;

    vec3 t1 = min(t_min, t_max);
    vec3 t2 = max(t_min, t_max);

    t_entry = max(max(t1.x, t1.y), t1.z);

    if(t_entry == t1.x){
        normal = vec3(-step.x, 0, 0);
    } else if(t_entry == t1.y){
        normal = vec3(0, -step.y, 0);
    } else{
        normal = vec3(0, 0, -step.z);
    }

    float tExit = min(min(t2.x, t2.y), t2.z);

    if (t_entry > tExit) {
        return false; // No intersection with grid
    }

    if (t_entry < 0){
        return false;
    }

    vec3 intersectionPoint = ray.origin + ray.direction * t_entry;

    intersectionPoint += EPSILON * normalize(ray.direction);

    voxel_position = ivec3(floor(intersectionPoint));

    return true;
}

HitPayload traceRay(Ray ray) {
    HitPayload payload;
    payload.hit_distance = 0.0;
    payload.normal = vec3(0.0);
    payload.material_index = 0;

    ivec3 voxel_position;
    float t = 0;
    vec3 normal = vec3(0);

    vec3 invDir = 1.0 / ray.direction;
    ivec3 stepInGrid = ivec3(sign(ray.direction));

    // If the ray starts inside the grid, use the original ray origin
    if (!(ray.origin.x < 0.0 || ray.origin.x >= float(grid_size.x) ||
    ray.origin.y < 0.0 || ray.origin.y >= float(grid_size.y) ||
    ray.origin.z < 0.0 || ray.origin.z >= float(grid_size.z))) {
        voxel_position = ivec3(floor(ray.origin));
    }

    // If it is outside check if it will intersect the grid or not
    else{
        if (!intersectGridBounds(ray, voxel_position, t, normal)){
            payload.hit_distance = -1;
            return payload;
        }

    }

    // Calculate t_max and t_delta
    vec3 t_max = (vec3(voxel_position + stepInGrid*0.5 + 0.5) - ray.origin) * invDir;
    vec3 t_delta = abs(invDir);

    
    while (ray_remaining_distance>0) {
        ray_remaining_distance--;

        // Check if the current voxel is out of the grid bounds
        if (voxel_position.x < 0 || voxel_position.x >= grid_size.x ||
        voxel_position.y < 0 || voxel_position.y >= grid_size.y ||
        voxel_position.z < 0 || voxel_position.z >= grid_size.z) {
            payload.hit_distance = -1;
            return payload;
        }

        // Check if the current voxel is a block
        // if (world[voxel_position.x + voxel_position.z * grid_size.x + voxel_position.y * grid_size.x * grid_size.z] != 0) {
        //     payload.material_index = world[voxel_position.x + voxel_position.z * grid_size.x + voxel_position.y * grid_size.x * grid_size.z];
        //     payload.hit_distance = t;
        //     payload.normal = normal;
        //     payload.position = ray.direction * t + ray.origin;
        //     return payload; // Hit
        // }
        if (accessWorldRandom(voxel_position.x, voxel_position.y, voxel_position.z) != 0) {
            payload.material_index = accessWorldRandom(voxel_position.x, voxel_position.y, voxel_position.z);
            payload.hit_distance = t;
            payload.normal = normal;
            payload.position = ray.direction * t + ray.origin;
            return payload; // Hit
        }

        // Traverse the grid
        if (t_max.x < t_max.y) {
            if (t_max.x < t_max.z) {
                voxel_position.x += stepInGrid.x;
                t = t_max.x;
                normal = vec3(-stepInGrid.x, 0, 0);
                t_max.x += t_delta.x;
            } else {
                voxel_position.z += stepInGrid.z;
                t = t_max.z;
                normal = vec3(0, 0, -stepInGrid.z);
                t_max.z += t_delta.z;
            }
        } else {
            if (t_max.y < t_max.z) {
                voxel_position.y += stepInGrid.y;
                t = t_max.y;
                normal = vec3(0, -stepInGrid.y, 0);
                t_max.y += t_delta.y;
            } else {
                voxel_position.z += stepInGrid.z;
                t = t_max.z;
                normal = vec3(0, 0, -stepInGrid.z);
                t_max.z += t_delta.z;
            }
        }

    }

    payload.hit_distance = -1;
    return payload;
}

float randFloat(inout uint seed){
    seed = PCGHash(seed);
    return float(seed)/float(0xFFFFFFFF);
}

vec3 randSphere(inout uint seed){
    return normalize(vec3(
        2*(randFloat(seed) - 0.5),
        2*(randFloat(seed) - 0.5),
        2*(randFloat(seed) - 0.5)
    ));

}

vec3 randHemisphere(inout uint seed, vec3 normal){
    vec3 v = randSphere(seed);
    return v * sign(dot(v, normal));
}

vec3 getDirectionLight(vec3 light_direction, vec3 emission, vec3 normal, vec3 contribution){

    light_direction = normalize(light_direction);
    
    float diff = max(dot(normal, -light_direction), 0);

    vec3 diffuse = emission * diff;

    return diffuse*contribution;
}

bool isSkyVisible(vec3 surface_position, vec3 direction){

    Ray ray;
    ray.origin = surface_position;
    ray.direction = direction;

    HitPayload payload = traceRay(ray);

    return (payload.hit_distance < 0);

}

vec3 calculateDirectLight(vec3 surface_position, vec3 normal, vec3 contribution){
    vec3 light = vec3(0);
    vec3 pre_light; // Used to test if the light is strong enough to worth sending rays
    float threshold = EPSILON;

    // Sun light
    pre_light = getDirectionLight(sun_direction, sun_emission_color*sun_emission_power, normal, contribution);
    if (length(pre_light) > threshold){
        int last_remaining_distance = ray_remaining_distance;
        ray_remaining_distance = LIMIT;
        if(isSkyVisible(surface_position, -sun_direction)){
            light += pre_light;
        }
        ray_remaining_distance = last_remaining_distance;
    }

    return light;
}

void main() {

    vec3 camera_position = camera_data.position;
    mat4 inverseViewMatrix = camera_data.inv_view;
    mat4 inverseProjectionMatrix = camera_data.inv_proj;

    ivec2 pixelPos = ivec2(gl_GlobalInvocationID.xy);
    vec2 screen_size = params.screen_size;
    if (pixelPos.x >= screen_size.x || pixelPos.y >= screen_size.y) {
        return;
    }

    //uint seed = uint((pixelPos.x<<16) + (pixelPos.y) + rendererRandom);
    uint seed = uint((pixelPos.x<<16) + (pixelPos.y));

    Ray ray;

    vec2 coord = vec2( float(pixelPos.x) / float(screen_size.x), float(pixelPos.y) / float(screen_size.y));
    coord = coord * 2 - 1;

    vec4 target = inverseProjectionMatrix * vec4(coord.x, coord.y, 1, 1);
    vec3 camera_ray_direction = normalize(vec3(inverseViewMatrix * vec4(normalize(vec3(target) / target.w), 0)));

    ray.origin = camera_position;
    ray.direction = camera_ray_direction;
    HitPayload payload;
    Material material;

    vec3 accumulated_light = vec3(0);
    int accumulations_per_trace = ACCUMULATIONS;

    for(int i = 0; i < accumulations_per_trace; i++){

        seed += i;
        vec3 light = vec3(0);
        vec3 contribution = vec3(1);
        vec3 normal;

        ray.origin = camera_position;
        ray.direction = camera_ray_direction;

        for (int j = 0; j < bounces; j++) {
            seed += j;

            //Russian Roulette stop the ray by chance if the contribution is too low
            float r = randFloat(seed);
            if (r > length(contribution) / length(vec3(1)) * 2){
                break;
            }
            payload = traceRay(ray);

            if (payload.hit_distance < 0) {
                light += background_color * contribution;
                break;
            }

            material = materials[payload.material_index];
            vec3 perfectReflection = reflect(ray.direction, payload.normal); //Get the perfect reflection direction for future calculations on indirect light
            normal = payload.normal;

            //Translate ray contact with object to avoid imprecisions
            ray.origin = payload.position + payload.normal * EPSILON;

            //Get pixel color based on the material contribuition
            contribution *= material.albedo;
            light += material.emission_color*material.emission_power*contribution;

            if(material.emission_power > 1)
                    break; //Break if it is an emissive object (it doesn't matter)

            //Direct light calculation
            //light += calculateDirectLight(ray.origin, normal, contribution);

            //Indirect light continue
            //Change the ray direction to a random direction following the surface diffuse properties
            ray.direction = normalize(randHemisphere(seed, normal) + perfectReflection*(1/(material.roughness+EPSILON)-1));

        }

        // Ambient light
        accumulated_light += clamp(light, 0, 1);
        ray_remaining_distance = LIMIT;
    }


    imageStore(screen_tex, pixelPos, vec4(accumulated_light/float(accumulations_per_trace), 1.0));

    // ivec2 pixelPos = ivec2(gl_GlobalInvocationID.xy);
    // vec2 screen_size = params.screen_size;
    // if (pixelPos.x >= screen_size.x || pixelPos.y >= screen_size.y) {
    //     return;
    // }

    // vec2 uv = vec2(pixelPos) / screen_size;

    // float noise = texture(noise_tex, uv).r;

    // if(noise < 0.6){
    //     imageStore(screen_tex, pixelPos, vec4(0, 0, 0, 1.0));
    //     return;
    // }

    // imageStore(screen_tex, pixelPos, vec4(noise, noise, noise, 1.0));

}