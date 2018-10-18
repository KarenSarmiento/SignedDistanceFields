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
#define FLOOR 2
#define TORUS 3

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

// floor positioned at y = 1.
float floorPlane(vec3 pt) {
  return pt.y +1;
}

float torus(vec3 pt) {
  // Shift to (0,3,0)
  pt -= vec3(0, 3, 0);
  vec2 t = vec2(3, 1);
  vec2 q = vec2(length(pt.xy) - t.x, pt.z);
  return length(q) - t.y;
}

float torusAndFloor(vec3 pt) {
  float torus = torus(pt);
  float floor = floorPlane(pt);
  return min(torus, floor);
}

vec3 getNormal(vec3 pt, int shapeType) {
  if (shapeType == CUBE)
      return normalize(GRADIENT(pt, cube));
  else if (shapeType == SPHERE)
      return normalize(GRADIENT(pt, sphere));
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

float shadow(vec3 pt, vec3 lightPos, int shapeType) {
  vec3 lightDir = normalize(lightPos - pt);
  float kd = 1;
  int step = 0;
  for (float t = 0.1; t < length(lightPos - pt) && step < RENDER_DEPTH && kd > 0.001; ) {
    float d = abs(torusAndFloor(pt + t * lightDir));
    if (d < 0.001) {
      kd = 0;
    } else {
      kd = min(kd, 16 * d / t);
    }
    t += d;
    step++;
  }
  return kd;
}

float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;

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

  float shadowCoefficient = 1.0;
  for (int i = 0; i < LIGHT_POS.length(); i++) {
    shadowCoefficient = min(shadowCoefficient, shadow(pt, LIGHT_POS[i], shapeType));
  }
  return shade(camPos, pt, n) * c * shadowCoefficient + 0.1 /*ambient*/;
}

///////////////////////////////////////////////////////////////////////////////}

vec3 raymarch(vec3 camPos, vec3 rayDir) {
  int step = 0;
  float t = 0;

  int takenShape;
  for (float d = 1000; step < RENDER_DEPTH && abs(d) > CLOSE_ENOUGH; t += abs(d)) {
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
    return illuminate(camPos, rayDir, camPos + t * rayDir, takenShape) ;
  }
}

///////////////////////////////////////////////////////////////////////////////

void main() {
  color = raymarch(camPos, getRayDir());
}