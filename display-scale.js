// How much to magnify the pages for the screen they are on.
//
// The kiosk page and the settings screen are laid out in CSS pixels for a
// 1080p TV. Windows scales a display by whatever "Scale" is set to in its
// display settings (100 %, 150 %, 300 % ...), which is rarely what a lobby TV
// needs: a 4K TV at 100 % shows everything at half size, at 300 % at one and
// a half times. The pages are therefore zoomed so that the total is
//
//     short side of the screen in physical pixels / 1080
//
// and every screen shows the layout a 1080p screen shows: 4K -> 2x, 1440p ->
// 1.35x, 720p -> 0.65x. The short side makes a portrait screen come out the
// same as its landscape twin. Rounded to 5 % steps, limited to 0.5x-4x.
// config.json can pin a value with "displayScale": 1.5 (a TV far across a
// hall may want more than the calculated size). No Electron dependency, so
// it is unit-tested with plain node. Same file as app/display-scale.js in
// Fieldlink-Pi-Kiosk apart from this comment.
const DESIGN_SHORT_SIDE = 1080;
const MIN_SCALE = 0.5;
const MAX_SCALE = 4;

function clamp(n) { return Math.min(MAX_SCALE, Math.max(MIN_SCALE, n)); }

// override: config.displayScale. A usable number wins; anything else is ignored.
function parseOverride(value) {
  const n = typeof value === 'string' ? parseFloat(value) : value;
  return typeof n === 'number' && Number.isFinite(n) && n > 0 ? clamp(n) : null;
}

// physical: { width, height } in physical pixels. → the total magnification.
function scaleFor(physical, override) {
  const pinned = parseOverride(override);
  if (pinned) return pinned;
  const short = Math.min(Number(physical && physical.width) || 0, Number(physical && physical.height) || 0);
  if (!short) return 1;
  return clamp(Math.round(short / DESIGN_SHORT_SIDE * 20) / 20);
}

// The zoom factor to give the page: Windows already scales by its own setting
// (deviceScaleFactor), and only the remainder is ours to add.
function zoomFor(physical, deviceScaleFactor, override) {
  const dsf = Number(deviceScaleFactor) > 0 ? Number(deviceScaleFactor) : 1;
  return Math.round(scaleFor(physical, override) / dsf * 1000) / 1000;
}

module.exports = { scaleFor, zoomFor, parseOverride, DESIGN_SHORT_SIDE, MIN_SCALE, MAX_SCALE };
