#version 330

uniform vec2 resolution;
uniform float currentTime;
uniform vec3 camPos;
uniform vec3 camDir;
uniform vec3 camUp;
uniform sampler2D tex;
uniform bool showStepDepth;

in vec3 pos;

out vec3 color;

#define PI 3.1415926535897932384626433832795
#define RENDER_DEPTH 800
#define CLOSE_ENOUGH 0.00001

#define BACKGROUND -1
#define BALL 0
#define BASE 1

#define CUBE 0
#define SPHERE 1
#define SHAPEOL 2
#define SHAPEIL 3
#define SHAPEOR 4
#define SHAPEIR 5

#define GRADIENT(pt, func) vec3( \
    func(vec3(pt.x + 0.0001, pt.y, pt.z)) - func(vec3(pt.x - 0.0001, pt.y, pt.z)), \
    func(vec3(pt.x, pt.y + 0.0001, pt.z)) - func(vec3(pt.x, pt.y - 0.0001, pt.z)), \
    func(vec3(pt.x, pt.y, pt.z + 0.0001)) - func(vec3(pt.x, pt.y, pt.z - 0.0001)))

const vec3 LIGHT_POS[] = vec3[](vec3(5, 18, 10));

///////////////////////////////////////////////////////////////////////////////

vec3 getBackground(vec3 dir) {
  float u = 0.5 + atan(dir.z, -dir.x) / (2 * PI);
  float v = 0.5 - asin(dir.y) / PI;
  vec4 texColor = texture(tex, vec2(u, v));
  return texColor.rgb;
}

vec3 getRayDir() {
  vec3 xAxis = normalize(cross(camDir, camUp));
  return normalize(pos.x * (resolution.x / resolution.y) * xAxis + pos.y * camUp + 5 * camDir);
}

///////////////////////////////////////////////////////////////////////////////

float blendMin(float a, float b) {
  float k = 0.2;
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1);
  return mix(b, a, h) - k * h * (1 - h);
}

float sphere(vec3 pt) {
  return length(pt) - 1;
}

// Retuns the min distance from the point pt to the surface of the cube
float cube(vec3 pt) {
  vec3 d = abs(pt) - vec3(1, 1, 1);
  return min(max(d.x, max(d.y, d.z)), 0.0)
    + length(max(d, 0.0));
}

float shapeIL(vec3 pt) {
  float cubeIL = cube(pt - vec3(-3, 0, -3));
  float sphereIL = sphere(pt - vec3(-2, 0, -2));
  return min(cubeIL, sphereIL);
}

float shapeIR(vec3 pt) {
  float cubeIR = cube(pt - vec3(3, 0, -3));
  float sphereIR = sphere(pt - vec3(4, 0, -2));
  return max(cubeIR, -sphereIR);
}

float shapeOL(vec3 pt) {
  float cubeOL = cube(pt - vec3(-3, 0, 3));
  float sphereOL = sphere(pt - vec3(-2, 0, 4));
  return blendMin(cubeOL, sphereOL);
}

float shapeOR(vec3 pt) {
  float cubeOR = cube(pt - vec3(3, 0, 3));
  float sphereOR = sphere(pt - vec3(4, 0, 4));
  return max(cubeOR, sphereOR);
}

vec3 getNormal(vec3 pt, int shapeType) {
  if (shapeType == CUBE)
      return normalize(GRADIENT(pt, cube));
  else if (shapeType == SPHERE)
      return normalize(GRADIENT(pt, sphere));
  else if (shapeType == SHAPEIL)
      return normalize(GRADIENT(pt, shapeIL));
  else if (shapeType == SHAPEIR)
      return normalize(GRADIENT(pt, shapeIR));
  else if (shapeType == SHAPEOL)
      return normalize(GRADIENT(pt, shapeOL));
  else if (shapeType == SHAPEOR)
      return normalize(GRADIENT(pt, shapeOR));
}

vec3 getColor(vec3 pt) {
  return vec3(1);
}

///////////////////////////////////////////////////////////////////////////////

float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;

  val += 0.1;  // Ambient

  for (int i = 0; i < LIGHT_POS.length(); i++) {
    vec3 l = normalize(LIGHT_POS[i] - pt);
    val += max(dot(n, l), 0);
  }
  return val;
}

vec3 illuminate(vec3 camPos, vec3 rayDir, vec3 pt, int shapeType) {
  vec3 c, n;
  n = getNormal(pt, shapeType);
  c = getColor(pt);
  return shade(camPos, pt, n) * c;
}

///////////////////////////////////////////////////////////////////////////////}

int minVal(float a, float b) {
  if (a < b)
    return 0;
  return 1;
}

int maxVal(float a, float b) {
  if (a > b)
    return 0;
  return 1;
}

vec3 raymarch(vec3 camPos, vec3 rayDir) {
  int step = 0;
  float t = 0;

  int takenShape;
  for (float d = 1000; step < RENDER_DEPTH && abs(d) > CLOSE_ENOUGH; t += abs(d)) {
    // O = outer, I = inner, L = left, R = right
    float shapeOL = shapeOL(camPos + t * rayDir);
    float shapeIL = shapeIL(camPos + t * rayDir);
    float shapeOR = shapeOR(camPos + t * rayDir);
    float shapeIR = shapeIR(camPos + t * rayDir);

    d = min(min(shapeOL, shapeOR), min(shapeIL, shapeIR));

    // Determine shape that calculated the sdf to illuminate properly
    if (shapeOL <= shapeOR && shapeOL <= shapeIR && shapeOL <= shapeIL)
      takenShape = SHAPEOL;
    else if (shapeOR <= shapeOL && shapeOR <= shapeIR && shapeOR <= shapeIL)
      takenShape = SHAPEOR;
    else if (shapeIL <= shapeOR && shapeIL <= shapeIR && shapeIL <= shapeOL)
      takenShape = SHAPEIL;
    else if (shapeIR <= shapeOR && shapeIR <= shapeOL && shapeIR <= shapeIL)
      takenShape = SHAPEIR;
    step++;
  }

  if (step == RENDER_DEPTH) {
    return getBackground(rayDir);
  } else if (showStepDepth) {
    return vec3(float(step) / RENDER_DEPTH);
  } else {
    return illuminate(camPos, rayDir, camPos + t * rayDir, takenShape);
  }
}

///////////////////////////////////////////////////////////////////////////////

void main() {
  color = raymarch(camPos, getRayDir());
}