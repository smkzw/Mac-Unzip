#!/usr/bin/env python3
"""ArchiveWorkbench App Icon Generator - generates all macOS icon sizes."""
import struct, zlib, os, math

def create_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xffffffff)
        return struct.pack(">I", len(data)) + c + crc
    sig = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    ihdr = chunk(b"IHDR", ihdr_data)
    raw_data = b""
    for y in range(height):
        raw_data += b"\x00"
        for x in range(width):
            idx = (y * width + x) * 4
            raw_data += bytes(pixels[idx:idx+4])
    compressed = zlib.compress(raw_data, 9)
    idat = chunk(b"IDAT", compressed)
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend

def lerp(a, b, t): return int(a + (b - a) * t)

def generate_icon(size):
    pixels = [0] * (size * size * 4)
    bg_top, bg_bottom = (74, 144, 217), (123, 104, 238)
    corner_radius = size * 0.225
    zw, zcx = size * 0.12, size * 0.5
    ztop, zbot = size * 0.15, size * 0.85
    tc = max(6, int(size / 40))
    th = (zbot - ztop) / tc
    tw = zw * 0.8
    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            in_shape = True
            r = corner_radius
            if x < r and y < r:
                if (x-r)**2 + (y-r)**2 > r**2: in_shape = False
            elif x > size-r and y < r:
                if (x-(size-r))**2 + (y-r)**2 > r**2: in_shape = False
            elif x < r and y > size-r:
                if (x-r)**2 + (y-(size-r))**2 > r**2: in_shape = False
            elif x > size-r and y > size-r:
                if (x-(size-r))**2 + (y-(size-r))**2 > r**2: in_shape = False
            if not in_shape:
                pixels[idx:idx+4] = [0,0,0,0]; continue
            t = y / size
            rv = lerp(bg_top[0], bg_bottom[0], t)
            gv = lerp(bg_top[1], bg_bottom[1], t)
            bv = lerp(bg_top[2], bg_bottom[2], t)
            dx = (x - size*0.5) / (size*0.5)
            dy = (y - size*0.35) / (size*0.5)
            hl = max(0, 1 - math.sqrt(dx*dx+dy*dy)) * 0.15
            rv = min(255, int(rv + hl*80))
            gv = min(255, int(gv + hl*80))
            bv = min(255, int(bv + hl*60))
            iz = False
            if abs(x - zcx) < zw*0.15 and ztop <= y <= zbot: iz = True
            if ztop <= y <= zbot:
                ti = int((y - ztop) / th)
                ty = (y - ztop) % th
                tp = ti % 2
                lx = zcx - zw*0.5
                if tp == 0 and abs(x-lx) < tw*0.5 and ty < th*0.6: iz = True
                rx = zcx + zw*0.5
                if tp == 1 and abs(x-rx) < tw*0.5 and ty < th*0.6: iz = True
            py = ztop + th*0.5
            ps = zw * 1.2
            if abs(x-zcx) < ps*0.5 and abs(y-py) < ps*0.4: iz = True
            if iz: pixels[idx:idx+4] = [229,229,229,255]
            else: pixels[idx:idx+4] = [rv,gv,bv,255]
    return create_png(size, size, pixels)

def main():
    sizes = {"icon_16x16.png":16,"icon_16x16@2x.png":32,"icon_32x32.png":32,
             "icon_32x32@2x.png":64,"icon_128x128.png":128,"icon_128x128@2x.png":256,
             "icon_256x256.png":256,"icon_256x256@2x.png":512,"icon_512x512.png":512,
             "icon_512x512@2x.png":1024}
    sd = os.path.dirname(os.path.abspath(__file__))
    pr = os.path.dirname(sd)
    od = os.path.join(pr, "ArchiveWorkbench/App/Resources/Assets.xcassets/AppIcon.appiconset")
    os.makedirs(od, exist_ok=True)
    for fn, sz in sizes.items():
        print(f"Generating {fn} ({sz}x{sz})...")
        with open(os.path.join(od, fn), "wb") as f: f.write(generate_icon(sz))
    print("Done!")

if __name__ == "__main__": main()
