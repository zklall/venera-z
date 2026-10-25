#include <flutter/runtime_effect.glsl>

// The engine supplies the backdrop texture and its physical size.
uniform vec2 u_texture_size;
uniform vec2 u_surface_size;
uniform vec2 u_origin;
uniform vec4 u_radii;
uniform float u_edge_width;
uniform float u_refraction;
uniform float u_pixel_ratio;
uniform vec4 u_tint;
uniform float u_light_intensity;
uniform sampler2D u_backdrop;

out vec4 frag_color;

void main() {
  vec2 position = FlutterFragCoord().xy;
  float scale = u_pixel_ratio;
  vec2 half_size = u_surface_size * scale * 0.5;
  vec2 p = position - u_origin * scale - half_size;
  float radius = p.y < 0.0
      ? (p.x < 0.0 ? u_radii.x : u_radii.y)
      : (p.x < 0.0 ? u_radii.w : u_radii.z);
  radius = min(radius * scale, min(half_size.x, half_size.y));
  vec2 q = abs(p) - half_size + radius;
  float distance = length(max(q, vec2(0.0)))
      + min(max(q.x, q.y), 0.0) - radius;
  float inside = max(-distance, 0.0);
  float edge_width = min(u_edge_width * scale,
                         min(u_surface_size.x, u_surface_size.y) * scale * 0.24);
  float edge = 1.0 - smoothstep(0.0, max(edge_width, 1.0), inside);

  vec2 normal;
  if (max(q.x, q.y) > 0.0) {
    normal = normalize(max(q, vec2(0.0)) + vec2(0.00001)) * sign(p);
  } else {
    normal = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
  }
  // Only the bevel bends the image. The clear centre samples its exact pixel.
  vec2 source = position - normal * (u_refraction * scale * edge * edge);
  vec2 uv = clamp(source / u_texture_size,
                  vec2(0.5) / u_texture_size,
                  vec2(1.0) - vec2(0.5) / u_texture_size);
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 backdrop = texture(u_backdrop, uv);
  // Leave the curved rim clear. Tint increases towards the flat centre so a
  // readable panel does not paint over its own refraction and specular light.
  float tint = u_tint.a * smoothstep(0.0, edge_width * 1.35, inside);
  vec3 body = mix(backdrop.rgb, u_tint.rgb * backdrop.a, tint);
  float light = dot(normal, normalize(vec2(-0.55, -0.83)));
  float light_falloff = mix(5.0, 3.0, clamp(u_light_intensity - 1.0, 0.0, 1.0));
  float highlight = max(light, 0.0) * pow(edge, light_falloff) * 0.16 * u_light_intensity;
  float shade = max(-light, 0.0) * pow(edge, 3.0) * 0.10 * u_light_intensity;
  frag_color = vec4(body * (1.0 - shade) +
                     vec3(highlight) * backdrop.a,
                   backdrop.a);
}
