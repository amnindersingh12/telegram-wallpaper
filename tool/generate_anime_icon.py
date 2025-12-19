#!/usr/bin/env python3
"""Generate an aesthetic anime-style cat icon for the app."""
from pathlib import Path
import math

def clamp(x):
    return max(0, min(255, int(x)))

def lerp(a, b, t):
    return a + (b - a) * t

def dist(x1, y1, x2, y2):
    return math.sqrt((x2-x1)**2 + (y2-y1)**2)

def generate_icon():
    out_dir = Path('assets/icons')
    out_dir.mkdir(parents=True, exist_ok=True)
    ppm_path = out_dir / 'app_icon.ppm'

    w = h = 512

    # Colors - anime aesthetic palette
    bg_dark = (22, 22, 28)
    bg_light = (32, 32, 42)
    accent = (138, 180, 248)  # Soft blue
    accent2 = (186, 135, 245)  # Soft purple
    face = (252, 250, 255)
    face_shadow = (235, 230, 245)
    pink = (255, 182, 193)
    dark = (35, 35, 45)

    cx, cy = w//2, h//2 + 10

    pixels = []
    for y in range(h):
        for x in range(w):
            # Gradient background
            t = y / h
            r = clamp(lerp(bg_dark[0], bg_light[0], t))
            g = clamp(lerp(bg_dark[1], bg_light[1], t))
            b = clamp(lerp(bg_dark[2], bg_light[2], t))
            
            # Subtle diagonal accent glow
            glow_dist = abs((x + y) - w) / w
            if glow_dist < 0.4:
                glow_t = 1 - (glow_dist / 0.4)
                r = clamp(r + accent2[0] * 0.08 * glow_t)
                g = clamp(g + accent2[1] * 0.08 * glow_t)
                b = clamp(b + accent2[2] * 0.08 * glow_t)

            # Soft circular glow behind cat
            d = dist(x, y, cx, cy)
            glow_r = w * 0.38
            if d < glow_r:
                glow_t = 1 - (d / glow_r)
                r = clamp(r + accent[0] * 0.15 * glow_t)
                g = clamp(g + accent[1] * 0.15 * glow_t)
                b = clamp(b + accent[2] * 0.15 * glow_t)

            # Cat ears (triangles)
            ear_size = int(w * 0.18)
            ear_y_offset = int(h * 0.32)
            
            # Left ear
            lex, ley = cx - int(w * 0.16), cy - ear_y_offset
            if y < cy - int(h * 0.15):
                ear_width = ear_size * (1 - (cy - ear_y_offset - y) / ear_size) if y > ley - ear_size else 0
                if abs(x - lex) < ear_width * 0.6 and y > ley - ear_size:
                    r, g, b = face
                    if abs(x - lex) < ear_width * 0.35 and y > ley - ear_size * 0.7:
                        r, g, b = pink[0], pink[1], pink[2]
            
            # Right ear
            rex, rey = cx + int(w * 0.16), cy - ear_y_offset
            if y < cy - int(h * 0.15):
                ear_width = ear_size * (1 - (cy - ear_y_offset - y) / ear_size) if y > rey - ear_size else 0
                if abs(x - rex) < ear_width * 0.6 and y > rey - ear_size:
                    r, g, b = face
                    if abs(x - rex) < ear_width * 0.35 and y > rey - ear_size * 0.7:
                        r, g, b = pink[0], pink[1], pink[2]

            # Cat head (oval)
            head_rx = int(w * 0.30)
            head_ry = int(h * 0.26)
            dx = (x - cx) / head_rx
            dy = (y - cy) / head_ry
            if dx*dx + dy*dy < 1:
                shade_t = (y - (cy - head_ry)) / (head_ry * 2)
                r = clamp(lerp(face[0], face_shadow[0], shade_t * 0.3))
                g = clamp(lerp(face[1], face_shadow[1], shade_t * 0.3))
                b = clamp(lerp(face[2], face_shadow[2], shade_t * 0.3))

            # Eyes (large anime style)
            eye_r = int(w * 0.072)
            eye_y = cy - int(h * 0.02)
            left_ex = cx - int(w * 0.12)
            right_ex = cx + int(w * 0.12)
            
            for ex in [left_ex, right_ex]:
                ed = dist(x, y, ex, eye_y)
                if ed < eye_r:
                    r, g, b = dark
                    iris_r = eye_r * 0.82
                    if ed < iris_r:
                        iris_t = ed / iris_r
                        r = clamp(lerp(accent[0], accent2[0], iris_t))
                        g = clamp(lerp(accent[1], accent2[1], iris_t))
                        b = clamp(lerp(accent[2], accent2[2], iris_t))
                    pupil_r = eye_r * 0.35
                    if ed < pupil_r:
                        r, g, b = 20, 20, 25
                    hl_x, hl_y = ex - eye_r * 0.25, eye_y - eye_r * 0.3
                    hl_d = dist(x, y, hl_x, hl_y)
                    if hl_d < eye_r * 0.28:
                        r, g, b = 255, 255, 255
                    hl2_x, hl2_y = ex + eye_r * 0.2, eye_y + eye_r * 0.2
                    hl2_d = dist(x, y, hl2_x, hl2_y)
                    if hl2_d < eye_r * 0.12:
                        r, g, b = 255, 255, 255

            # Blush
            blush_r = int(w * 0.055)
            blush_y = cy + int(h * 0.06)
            for bx in [cx - int(w * 0.19), cx + int(w * 0.19)]:
                bd = dist(x, y, bx, blush_y)
                if bd < blush_r:
                    dx_f = (x - cx) / head_rx
                    dy_f = (y - cy) / head_ry
                    if dx_f*dx_f + dy_f*dy_f < 1:
                        blend = 0.35 * (1 - bd/blush_r)
                        r = clamp(r * (1-blend) + pink[0] * blend)
                        g = clamp(g * (1-blend) + pink[1] * blend)
                        b = clamp(b * (1-blend) + pink[2] * blend)

            # Nose
            nose_y = cy + int(h * 0.04)
            nose_size = int(w * 0.025)
            if abs(x - cx) < nose_size and y > nose_y - nose_size and y < nose_y + nose_size//2:
                if abs(x - cx) < (nose_y + nose_size//2 - y) * 0.7:
                    r, g, b = 255, 180, 190

            # Mouth
            mouth_y = cy + int(h * 0.08)
            mouth_w = int(w * 0.06)
            if y > mouth_y - 3 and y < mouth_y + 8:
                expected_y = mouth_y + int(4 * math.sin((x - (cx - mouth_w//2)) / mouth_w * math.pi))
                if x > cx - mouth_w and x < cx and abs(y - expected_y) < 3:
                    r, g, b = dark
                expected_y2 = mouth_y + int(4 * math.sin((x - cx) / mouth_w * math.pi))
                if x > cx and x < cx + mouth_w and abs(y - expected_y2) < 3:
                    r, g, b = dark

            # Sparkles
            sparkles = [(int(w*0.18), int(h*0.22), 8), (int(w*0.82), int(h*0.28), 10), 
                        (int(w*0.75), int(h*0.75), 7), (int(w*0.15), int(h*0.72), 6)]
            for sx, sy, sr in sparkles:
                sd = dist(x, y, sx, sy)
                if sd < sr:
                    angle = math.atan2(y - sy, x - sx)
                    star_r = sr * (0.4 + 0.6 * abs(math.cos(angle * 2)))
                    if sd < star_r:
                        blend = 0.8 * (1 - sd/star_r)
                        r = clamp(r + (255 - r) * blend)
                        g = clamp(g + (255 - g) * blend)
                        b = clamp(b + (255 - b) * blend)

            pixels.append((r, g, b))

    with ppm_path.open('w') as f:
        f.write('P3\n')
        f.write(f'{w} {h}\n')
        f.write('255\n')
        for (r,g,b) in pixels:
            f.write(f'{r} {g} {b} ')

    print('Wrote', ppm_path)

if __name__ == '__main__':
    generate_icon()
