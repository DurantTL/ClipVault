#!/usr/bin/env python3
from pathlib import Path
import struct, zlib, math, json

def png(path, size):
    rows=[]
    r=size*0.22
    for y in range(size):
        row=bytearray([0])
        for x in range(size):
            # rounded rect alpha
            dx=max(r-x,0,x-(size-1-r)); dy=max(r-y,0,y-(size-1-r))
            outside=dx*dx+dy*dy>r*r
            if outside:
                row += bytes([0,0,0,0]); continue
            t=(x+y)/(2*size)
            R=int(35+(130-35)*t); G=int(115+(70-115)*t); B=int(245+(230-245)*t)
            # vault/card
            if size*.22<x<size*.78 and size*.32<y<size*.68:
                R,G,B=245,248,255
            if size*.28<x<size*.72 and size*.38<y<size*.62:
                R,G,B=45,85,185
            # play triangle
            if size*.43<x<size*.62 and abs((y-size*.5)) < (x-size*.43)*.65:
                R,G,B=255,255,255
            # checkmark green lower right
            cx,cy=size*.70,size*.72
            if (x-cx)**2+(y-cy)**2 < (size*.15)**2:
                R,G,B=42,210,105
            # check strokes
            if abs((y-(cy+size*.02)) - 0.65*(x-(cx-size*.08))) < size*.025 and cx-size*.11<x<cx-size*.02:
                R,G,B=255,255,255
            if abs((y-(cy+size*.08)) + 0.75*(x-(cx-size*.02))) < size*.025 and cx-size*.02<x<cx+size*.11:
                R,G,B=255,255,255
            row += bytes([R,G,B,255])
        rows.append(bytes(row))
    raw=b''.join(rows)
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    path.write_bytes(data)

out=Path('ClipVault/Assets.xcassets/AppIcon.appiconset')
out.mkdir(parents=True, exist_ok=True)
items=[]
for pts,scale,pixels in [(16,'1x',16),(16,'2x',32),(32,'1x',32),(32,'2x',64),(128,'1x',128),(128,'2x',256),(256,'1x',256),(256,'2x',512),(512,'1x',512),(512,'2x',1024)]:
    name=f'icon_{pixels}.png'
    png(out/name,pixels)
    items.append({'idiom':'mac','size':f'{pts}x{pts}','scale':scale,'filename':name})
(out/'Contents.json').write_text(json.dumps({'images':items,'info':{'author':'xcode','version':1}},indent=2))
