#!/usr/bin/env python3
"""Reference chunk seeds (splitmix64), independent of Godot. Usage: reference_chunk_seed.py SEED CX CZ"""
import sys
M = (1 << 64) - 1
def sm(x):
    z = (x + 0x9E3779B97F4A7C15) & M
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M
    return z ^ (z >> 31)
def chunk_seed(seed, cx, cz):
    inner = sm(((cx * 0x9E3779B97F4A7C15) & M) ^ ((cz * 0xC2B2AE3D27D4EB4F) & M))
    n = sm((seed & M) ^ inner) & 0x7FFFFFFFFFFFFFFF
    return n or 1
if __name__ == "__main__":
    s, x, z = (int(a) for a in sys.argv[1:4])
    print(chunk_seed(s, x, z))
