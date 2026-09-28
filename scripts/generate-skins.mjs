import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";

const width = 1536, height = 969;
const palettes = {
  aurora: [[118,91,241],[219,97,174],[255,152,109]],
  ember: [[48,17,20],[169,44,44],[255,104,72]],
  tide: [[8,45,69],[9,127,139],[92,224,181]],
  mono: [[9,9,9],[45,45,45],[80,80,80]]
};
const table = new Uint32Array(256);
for (let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;table[n]=c>>>0;}
function crc(type,data){let c=0xffffffff;for(const b of Buffer.concat([Buffer.from(type),data]))c=table[(c^b)&255]^(c>>>8);return (c^0xffffffff)>>>0;}
function chunk(type,data){const head=Buffer.alloc(8);head.writeUInt32BE(data.length);head.write(type,4);const tail=Buffer.alloc(4);tail.writeUInt32BE(crc(type,data));return Buffer.concat([head,data,tail]);}
function png(colors){const raw=Buffer.alloc((width*4+1)*height);for(let y=0;y<height;y++){const row=y*(width*4+1);for(let x=0;x<width;x++){const t=(x/width*.65+y/height*.35)*2;const i=Math.min(1,Math.floor(t)),f=t-i;const a=colors[i],b=colors[Math.min(2,i+1)];const p=row+1+x*4;for(let k=0;k<3;k++)raw[p+k]=Math.round(a[k]*(1-f)+b[k]*f);raw[p+3]=255;}}const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=6;return Buffer.concat([Buffer.from("89504e470d0a1a0a","hex"),chunk("IHDR",ihdr),chunk("IDAT",deflateSync(raw,{level:9})),chunk("IEND",Buffer.alloc(0))]);}
mkdirSync(new URL("../wallet-web/skins/",import.meta.url),{recursive:true});
for(const [name,colors] of Object.entries(palettes))writeFileSync(new URL(`../wallet-web/skins/${name}.png`,import.meta.url),png(colors));
