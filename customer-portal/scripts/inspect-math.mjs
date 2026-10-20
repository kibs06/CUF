// Minimal column-major mat4/vec3 helpers (glTF convention) so the
// inspector stays dependency-free apart from @gltf-transform/core.
export const mat4 = {
  multiply(a, b) {
    const out = new Array(16).fill(0)
    for (let c = 0; c < 4; c++) {
      for (let r = 0; r < 4; r++) {
        let sum = 0
        for (let k = 0; k < 4; k++) sum += a[k * 4 + r] * b[c * 4 + k]
        out[c * 4 + r] = sum
      }
    }
    return out
  },
}

export const vec3 = {
  transformMat4(out, p, m) {
    const x = p[0]
    const y = p[1]
    const z = p[2]
    const w = m[3] * x + m[7] * y + m[11] * z + m[15] || 1
    out[0] = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w
    out[1] = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w
    out[2] = (m[2] * x + m[6] * y + m[10] * z + m[14]) / w
    return out
  },
}
