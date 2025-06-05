#!/usr/bin/env python3
from PIL import Image, ImageDraw
import os
import math

def create_gradient_background(size):
    """Create a black to gray radial gradient background"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    center = size // 2
    max_radius = int(size * 0.7)
    for r in range(max_radius, 0, -1):
        alpha = 1 - (r / max_radius)
        gray_value = int(120 * alpha)
        color = (gray_value, gray_value, gray_value, 255)
        left = center - r
        top = center - r
        right = center + r
        bottom = center + r
        draw.ellipse([left, top, right, bottom], fill=color)
    return img

def draw_c_logo(draw, size):
    """Draw a smaller, centered white C logo with more padding"""
    center = size // 2
    # Make the C about 58% of the icon size
    outer_radius = int(size * 0.29)  # ~58% diameter for more padding
    stroke_width = int(size * 0.09)
    # Arc angles
    start_angle = 45
    end_angle = 315
    bbox = [
        center - outer_radius,
        center - outer_radius,
        center + outer_radius,
        center + outer_radius
    ]
    draw.arc(bbox, start_angle, end_angle, fill=(255, 255, 255, 255), width=stroke_width)
    # End caps
    cap_radius = stroke_width // 2
    top_x = center + outer_radius * math.cos(math.radians(315))
    top_y = center + outer_radius * math.sin(math.radians(315))
    draw.ellipse([
        top_x - cap_radius, top_y - cap_radius,
        top_x + cap_radius, top_y + cap_radius
    ], fill=(255, 255, 255, 255))
    bottom_x = center + outer_radius * math.cos(math.radians(45))
    bottom_y = center + outer_radius * math.sin(math.radians(45))
    draw.ellipse([
        bottom_x - cap_radius, bottom_y - cap_radius,
        bottom_x + cap_radius, bottom_y + cap_radius
    ], fill=(255, 255, 255, 255))

def squircle_mask(size):
    # Superellipse: |x/a|^n + |y/b|^n = 1, n=5 for macOS
    n = 5.0
    a = b = size / 2
    cx = cy = size / 2
    mask = Image.new('L', (size, size), 0)
    pixels = mask.load()
    for y in range(size):
        for x in range(size):
            dx = abs(x - cx) / a
            dy = abs(y - cy) / b
            if (dx ** n + dy ** n) <= 1:
                pixels[x, y] = 255
    return mask

def create_icon(size):
    img = create_gradient_background(size)
    draw = ImageDraw.Draw(img)
    draw_c_logo(draw, size)
    # Use squircle mask for true macOS look
    mask = squircle_mask(size)
    img.putalpha(mask)
    return img

def main():
    sizes = [16, 32, 128, 256, 512, 1024]
    output_dir = "CALAPP/Assets.xcassets/AppIcon.appiconset"
    print("🎨 Creating new squircle app icon...")
    for size in sizes:
        print(f"  📱 Generating {size}x{size} icon...")
        icon = create_icon(size)
        filename = f"icon_{size}x{size}.png"
        filepath = os.path.join(output_dir, filename)
        icon.save(filepath, "PNG")
        if size <= 256:
            filename_2x = f"icon_{size}x{size}@2x.png"
            filepath_2x = os.path.join(output_dir, filename_2x)
            icon_2x = create_icon(size * 2)
            icon_2x.save(filepath_2x, "PNG")
            print(f"  📱 Generating {size}x{size}@2x icon...")
    print("✅ New squircle app icon created successfully!")

if __name__ == "__main__":
    main() 