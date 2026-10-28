// Regenerate with Node and sharp available (npm install --no-save sharp).
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const source = await fs.readFile(path.join(root, 'app/assets/branding/app_icon.svg'), 'utf8');
  const foreground = source
    .replace(/<rect x="64" y="64"[^>]+\/>/, '')
    .replace(/<circle cx="512" cy="460"[^>]+\/>/, '');
  const res = path.join(root, 'app/android/app/src/main/res');
  for (const [density, size, foregroundSize] of [
    ['mdpi', 48, 108], ['hdpi', 72, 162], ['xhdpi', 96, 216],
    ['xxhdpi', 144, 324], ['xxxhdpi', 192, 432],
  ]) {
    const directory = path.join(res, `mipmap-${density}`);
    await fs.mkdir(directory, {recursive: true});
    await sharp(Buffer.from(source)).resize(size, size).png().toFile(path.join(directory, 'ic_launcher.png'));
    await sharp(Buffer.from(foreground)).resize(foregroundSize, foregroundSize).png().toFile(path.join(directory, 'ic_launcher_foreground.png'));
  }
  await sharp(Buffer.from(source)).resize(512,512).png().toFile(path.join(root,'app/assets/branding/app_icon.png'));
  const directory = path.join(res, 'mipmap-anydpi-v26');
  await fs.mkdir(directory, {recursive: true});
  await fs.writeFile(path.join(directory, 'ic_launcher.xml'), `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
`);
  await fs.writeFile(path.join(res, 'values/launcher_colors.xml'), `<?xml version="1.0" encoding="utf-8"?>
<resources><color name="launcher_background">#B31B24</color></resources>
`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
