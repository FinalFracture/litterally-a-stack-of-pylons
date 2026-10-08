extends RefCounted

## World-locked Gaussian terrain. A chunk only caches a window.
## Each sample is a function of the world seed and the cell, so a shared
## edge matches the neighbor without a fade.
const _Layout = preload("res://scripts/road_chunk_layout.gd")

const GRID_M := 8.0
const MACRO_SIGMA_M := 80.0
# Pre-fit at 2.2 m / 0.45 m: height -6.232..5.766, grade 0.0975.
# Grade was already under 0.12. Both amplitudes use the same scale, 0.1909,
# so the shape is unchanged and height stays inside HEIGHT_MIN/MAX.
const MACRO_AMP_M := 0.42
const MESO_SIGMA_M := 24.0
const MESO_AMP_M := 0.0859
const FEATURE_SIGMA_M := 40.0
const HEIGHT_MIN := -1.2
const HEIGHT_MAX := 3.0
const GRADE_MAX := 0.12

const _SALT_MACRO := 11
const _SALT_MESO := 29
const _SALT_FEATURE := 47
const _SALT_PAIR := 8191

var _world_seed: int = 1
var _macro_k: PackedFloat32Array = PackedFloat32Array()
var _meso_k: PackedFloat32Array = PackedFloat32Array()
var _feature_k: PackedFloat32Array = PackedFloat32Array()
var _macro_rms: float = 1.0
var _meso_rms: float = 1.0
var _feature_rms: float = 1.0


func setup(world_seed: int) -> void:
	_world_seed = world_seed & 0x7fffffff
	if _world_seed == 0:
		_world_seed = 1
	_macro_k = _make_kernel(MACRO_SIGMA_M)
	_meso_k = _make_kernel(MESO_SIGMA_M)
	_feature_k = _make_kernel(FEATURE_SIGMA_M)
	_macro_rms = _kernel_rms(_macro_k)
	_meso_rms = _kernel_rms(_meso_k)
	_feature_rms = _kernel_rms(_feature_k)


func skirt_cells() -> int:
	return int(ceil(3.0 * MACRO_SIGMA_M / GRID_M))


func build_chunk(chunk: Vector2i) -> Dictionary:
	var origin_x: float = float(chunk.x) * _Layout.CHUNK_SIZE_M
	var origin_z: float = float(chunk.y) * _Layout.CHUNK_SIZE_M
	var x0: int = int(floor(origin_x / GRID_M))
	var z0: int = int(floor(origin_z / GRID_M))
	# Half-open chunk [origin, origin + size). A cell that straddles the far edge is included.
	var x1: int = int(floor((origin_x + _Layout.CHUNK_SIZE_M - 0.000001) / GRID_M))
	var z1: int = int(floor((origin_z + _Layout.CHUNK_SIZE_M - 0.000001) / GRID_M))
	var skirt: int = skirt_cells()
	var ox0: int = x0 - skirt
	var oz0: int = z0 - skirt
	var nx: int = x1 - x0 + 1 + skirt * 2
	var nz: int = z1 - z0 + 1 + skirt * 2
	var macro: PackedFloat32Array = _fill_octave(ox0, oz0, nx, nz, _macro_k, _macro_rms, _SALT_MACRO)
	var meso: PackedFloat32Array = _fill_octave(ox0, oz0, nx, nz, _meso_k, _meso_rms, _SALT_MESO)
	var feature: PackedFloat32Array = _fill_octave(ox0, oz0, nx, nz, _feature_k, _feature_rms, _SALT_FEATURE)
	var height: PackedFloat32Array = PackedFloat32Array()
	var slope_x: PackedFloat32Array = PackedFloat32Array()
	var slope_z: PackedFloat32Array = PackedFloat32Array()
	var grade: PackedFloat32Array = PackedFloat32Array()
	var count: int = nx * nz
	height.resize(count)
	slope_x.resize(count)
	slope_z.resize(count)
	grade.resize(count)
	for i in count:
		height[i] = MACRO_AMP_M * macro[i] + MESO_AMP_M * meso[i]
	var step: float = 2.0 * GRID_M
	for z in nz:
		for x in nx:
			var i2: int = z * nx + x
			if x == 0 or x == nx - 1 or z == 0 or z == nz - 1:
				continue
			var dhdx: float = (height[i2 + 1] - height[i2 - 1]) / step
			var dhdz: float = (height[i2 + nx] - height[i2 - nx]) / step
			slope_x[i2] = dhdx
			slope_z[i2] = dhdz
			grade[i2] = sqrt(dhdx * dhdx + dhdz * dhdz)
	return {
		"x0": ox0,
		"z0": oz0,
		"nx": nx,
		"nz": nz,
		"chunk_x0": x0,
		"chunk_x1": x1,
		"chunk_z0": z0,
		"chunk_z1": z1,
		"height": height,
		"feature": feature,
		"slope_x": slope_x,
		"slope_z": slope_z,
		"grade": grade,
	}


func _make_kernel(sigma_m: float) -> PackedFloat32Array:
	var sigma_cells: float = sigma_m / GRID_M
	var radius: int = int(ceil(3.0 * sigma_cells))
	var n: int = radius * 2 + 1
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(n)
	var sum: float = 0.0
	for i in n:
		var k: int = i - radius
		var g: float = exp(-0.5 * float(k) * float(k) / (sigma_cells * sigma_cells))
		weights[i] = g
		sum += g
	for j in n:
		weights[j] = weights[j] / sum
	return weights


func _kernel_rms(kernel: PackedFloat32Array) -> float:
	var sum_sq: float = 0.0
	var n: int = kernel.size()
	for dz in n:
		var kz: float = kernel[dz]
		for dx in n:
			var w: float = kernel[dx] * kz
			sum_sq += w * w
	return sqrt(sum_sq)


func _fill_octave(ox0: int, oz0: int, nx: int, nz: int, kernel: PackedFloat32Array, rms: float, salt: int) -> PackedFloat32Array:
	var radius: int = kernel.size() >> 1
	var noise_x0: int = ox0 - radius
	var noise_z0: int = oz0 - radius
	var noise_nx: int = nx + radius * 2
	var noise_nz: int = nz + radius * 2
	var noise: PackedFloat32Array = PackedFloat32Array()
	noise.resize(noise_nx * noise_nz)
	for z in noise_nz:
		var iz: int = noise_z0 + z
		var row_i: int = z * noise_nx
		for x in noise_nx:
			noise[row_i + x] = _gaussian(noise_x0 + x, iz, salt)
	var horiz: PackedFloat32Array = PackedFloat32Array()
	horiz.resize(noise_nz * nx)
	var ks: int = kernel.size()
	for z2 in noise_nz:
		var base: int = z2 * noise_nx
		var dest: int = z2 * nx
		for x2 in nx:
			var acc: float = 0.0
			for k in ks:
				acc += kernel[k] * noise[base + x2 + k]
			horiz[dest + x2] = acc
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(nx * nz)
	var inv_rms: float = 1.0 / rms
	for z3 in nz:
		var dest_row: int = z3 * nx
		for x3 in nx:
			var acc2: float = 0.0
			for k2 in ks:
				acc2 += kernel[k2] * horiz[(z3 + k2) * nx + x3]
			out[dest_row + x3] = acc2 * inv_rms
	return out


func _gaussian(ix: int, iz: int, salt: int) -> float:
	var u1: float = _unit(_hash(ix, iz, salt))
	var u2: float = _unit(_hash(ix, iz, salt + _SALT_PAIR))
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func _unit(h: int) -> float:
	return (float(h) + 1.0) / 4294967297.0


func _hash(ix: int, iz: int, salt: int) -> int:
	var n: int = _u32(_world_seed)
	n = _u32(n + _u32(ix * 374761393))
	n = _u32(n + _u32(iz * 668265263))
	n = _u32(n + _u32(salt * 1442695041))
	n = _u32((n ^ (n >> 16)) * 0x7feb352d)
	n = _u32((n ^ (n >> 15)) * 0x846ca68b)
	n = _u32(n ^ (n >> 16))
	return n


func _u32(n: int) -> int:
	return n & 0xffffffff
