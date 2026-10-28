#!/usr/bin/env python3
"""Render a clearly labelled synthetic stage around actual Godot captures."""
import argparse,json,subprocess
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

def main():
 p=argparse.ArgumentParser();p.add_argument('captures',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
 frames=json.loads((a.captures/'frames.json').read_text());out=a.captures/'stage';out.mkdir(exist_ok=True)
 font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
 regular=ImageFont.truetype(font,17);small=ImageFont.truetype(font,13);title=ImageFont.truetype(font,28)
 for item in frames:
  image=Image.new('RGBA',(960,540),'#141719');d=ImageDraw.Draw(image)
  d.rounded_rectangle((24,24,936,516),radius=24,fill='#1d2123',outline='#343a3c',width=1)
  d.text((48,42),'LEEMON 0.18',font=title,fill='#f5c454')
  d.text((48,83),'Сценарная демонстрация · настоящий рендерер персонажа',font=small,fill='#b6bfc1')
  d.text((48,108),'Без реальных действий на ПК и без модельного вывода',font=small,fill='#899598')
  d.rounded_rectangle((48,153,912,198),radius=10,fill='#282d2f')
  d.text((64,165),item['label'],font=regular,fill='#e8edef')
  d.line((50,486,910,486),fill='#42413a',width=1)
  hero=Image.open(a.captures/item['file']).convert('RGBA')
  image.alpha_composite(hero,(item['x']-160,item['y']-250))
  if 'bubble' in item:
   bubble=Image.open(a.captures/item['bubble']).convert('RGBA')
   image.alpha_composite(bubble,(item['bubble_x']-160,item['bubble_y']-250))
  image.convert('RGB').save(out/('stage_%03d.png'%item['frame']))
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-framerate','20','-i',str(out/'stage_%03d.png'),'-c:v','libx264','-pix_fmt','yuv420p','-crf','19','-movflags','+faststart',str(a.output)],check=True)
 print(a.output,a.output.stat().st_size,'bytes;9seconds;20fps presentation, not runtime performance')
if __name__=='__main__':main()
