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
#define FLOOR 6
#define TORUS 7

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

// floor positioned at y = 1.
float floorPlane(vec3 pt) {
  return pt.y +1;
}

float torus(vec3 pt) {
  // Shift to (0,3,0)
  pt -= vec3(0, 3, 0);
  vec2 t = vec2(3, 1);
  vec2 q = vec2(length(pt.xz) - t.x, pt.y);
  return length(q) - t.y;
}

// 2D version are the same as 3D with z plane removed.

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
  else if (shapeType == FLOOR)
      return normalize(GRADIENT(pt, floorPlane));
  else if (shapeType == TORUS)
      return normalize(GRADIENT(pt, torus));
}

vec3 getColor(vec3 pt, int shapeType) {
  if (shapeType == FLOOR) {
    // calculate min distance to other objects from current position and return
    // colour based off of this value.
    float d = torus(pt);

    // turn pixel black if d % 5 is in the range [4.75, 5)
    float d_black = d - floor(d / 5)*5;
    if (d_black >= 4.75) {
      return vec3(0, 0, 0);
    }
    // Gives a value in the range [0,1)
    float d_dec = d - floor(d);

    // We wish to get a color within the range green (0.4, 1, 0.4) and (0.4, 0.4, 1)
    return vec3(0.4, 1 - 0.6 * d_dec, 0.4 + 0.6 * d_dec);
  }
  return vec3(1);
}

///////////////////////////////////////////////////////////////////////////////

float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;

  val += 0.1;  // Ambient

  for (int i = 0; i < LIGHT_POS.length(); i++) {
    // the incidenct ray is the light position - the intersection
    vec3 incidentRay = normalize(pt - LIGHT_POS[i]);
    vec3 reflectedRay = reflect(incidentRay, n);
    vec3 view = normalize(eye - pt);
    val += pow(max(dot(reflectedRay, view), 0), 256);

    vec3 l = normalize(LIGHT_POS[i] - pt);
    val += max(dot(n, l), 0);
  }
  return val;
}

vec3 illuminate(vec3 camPos, vec3 rayDir, vec3 pt, int shapeType) {
  vec3 c, n;
  n = getNormal(pt, shapeType);
  c = getColor(pt, shapeType);
  return shade(camPos, pt, n) * c;
}

///////////////////////////////////////////////////////////////////////////////}

vec3 raymarch(vec3 camPos, vec3 rayDir) {
  int step = 0;
  float t = 0;

  int takenShape;
  for (float d = 1000; step < RENDER_DEPTH && abs(d) > CLOSE_ENOUGH; t += abs(d)) {
    // O = outer, I = inner, L = left, R = right
    float torus = torus(camPos + t * rayDir);
    float floor = floorPlane(camPos + t * rayDir);

    // Determine shape that calculated the sdf to illuminate properly
    if (torus < floor) {
      d = torus;
      takenShape = TORUS;
    } else {
      d = floor;
      takenShape = FLOOR;
    }
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