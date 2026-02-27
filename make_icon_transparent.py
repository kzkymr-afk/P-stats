#!/usr/bin/env python3
"""画像の白い部分を透明にし、1024x1024のアプリアイコンとして保存する"""
from PIL import Image
import sys

def main():
    src = "/Users/kazukiyoomura/.cursor/projects/Users-kazukiyoomura-Documents-AppDev-P-stats/assets/image-4900c9b7-c32b-4da4-aac9-952d94c47410.png"
    out_icon = "/Users/kazukiyoomura/Documents/AppDev/P-stats/P-stats/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    out_image = "/Users/kazukiyoomura/Documents/AppDev/P-stats/P-stats/Assets.xcassets/AppIconImage.imageset/AppIcon-1024.png"

    img = Image.open(src).convert("RGBA")
    w, h = img.size
    data = img.getdata()
    new_data = []
    # 白〜明るいグレーを透明に（閾値 250 でほぼ白、240 でゆるく）
    threshold = 248
    for item in data:
        r, g, b, a = item
        if r >= threshold and g >= threshold and b >= threshold:
            new_data.append((r, g, b, 0))
        else:
            new_data.append(item)
    img.putdata(new_data)

    out = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    out.save(out_icon, "PNG")
    out.save(out_image, "PNG")
    print("Saved:", out_icon, out_image)

if __name__ == "__main__":
    main()
