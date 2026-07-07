#!/usr/bin/env bash
# Claude Code PostToolUse hook.
# Detects image files that a tool (Write / Bash) just produced and adds them to
# a local HTML gallery (~/.claude/image-gallery/index.html, plain file://).
# Push-driven: no server, no polling. When new images appear the hook
# regenerates the page and reloads the already-open gallery tab in Chrome via
# AppleScript; if no tab has it open, it opens one in the background (open -g).
#
# Page features: lightbox modal (click to zoom, Esc / arrows), 50-per-page
# pagination, copy-path buttons, broken images auto-hidden. Entries whose file
# was deleted are pruned from the log (log capped at 500, page shows last 200).
#
# Dedup by "path|mtime" so the same image isn't re-added, but a regenerated
# file (new mtime) shows up again at the top.

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"

# Collect candidate text from input + response.
text=$(printf '%s' "$input" | jq -r '
  [ .tool_input.file_path?,
    .tool_input.command?,
    (.tool_response | if type=="string" then . else tostring end)? ]
  | map(select(. != null)) | join("\n")' 2>/dev/null)

[ -z "$text" ] && exit 0

gallery="$HOME/.claude/image-gallery"
mkdir -p "$gallery" 2>/dev/null || exit 0
log="$gallery/entries.tsv"   # <mtime_epoch> TAB <abs_path>
state="$gallery/seen.txt"    # dedupe keys: <abs_path>|<mtime>
index="$gallery/index.html"
touch "$log" "$state" 2>/dev/null || exit 0

added=0
while IFS= read -r p; do
  case "$p" in
    /*) abs="$p" ;;
    \~*) abs="${p/#\~/$HOME}" ;;
    *)  abs="$cwd/$p" ;;
  esac
  [ -f "$abs" ] || continue
  mt=$(stat -f %m "$abs" 2>/dev/null || echo 0)
  key="$abs|$mt"
  grep -qxF "$key" "$state" 2>/dev/null && continue
  printf '%s\n' "$key" >> "$state"
  printf '%s\t%s\n' "$mt" "$abs" >> "$log"
  added=1
done < <(printf '%s\n' "$text" \
  | grep -oiE "[^[:space:]\"'\`()<>,]+\.(png|jpe?g|gif|webp|bmp|tiff?|heic|svg)")

[ "$added" -eq 1 ] || exit 0

# Prune: drop entries whose file no longer exists, cap the log at 500 lines.
prune="$gallery/.log.tmp"
while IFS=$'\t' read -r mt abs; do
  [ -f "$abs" ] && printf '%s\t%s\n' "$mt" "$abs"
done < "$log" | tail -n 500 > "$prune" && mv "$prune" "$log"

# Rebuild the gallery page (last 200 images, newest first, 50 per page).
# Write to a temp file and mv so the browser never catches a half-written page.
tmp="$gallery/.index.tmp"
{
  cat <<'HTML'
<!doctype html>
<html lang="ja"><head><meta charset="utf-8">
<title>Claude Images</title>
<style>
  body { margin:0; padding:16px; background:#111418; color:#e6e8eb;
         font:13px/1.5 -apple-system, "Hiragino Sans", sans-serif; }
  h1 { font-size:15px; margin:0 0 14px; font-weight:600; color:#9aa4b2; }
  h1 small { font-weight:400; font-size:11px; color:#5b6673; margin-left:10px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); gap:12px; }
  .card { background:#1a1f26; border:1px solid #2a313b; border-radius:10px;
          overflow:hidden; cursor:zoom-in; }
  .card:first-child { border-color:#4ade80; }
  .card img { width:100%; height:170px; object-fit:contain; display:block;
              background:
                conic-gradient(#20262e 0 25%, #171c22 0 50%, #20262e 0 75%, #171c22 0) 0 0/20px 20px; }
  .meta { padding:8px 10px; }
  .name { font-weight:600; overflow-wrap:anywhere; }
  .time { color:#7b8794; font-size:11px; }
  .path { color:#5b6673; font-size:10px; overflow-wrap:anywhere; }
  .cp { background:none; border:1px solid #2a313b; border-radius:5px; color:#7b8794;
        cursor:pointer; font-size:10px; padding:1px 7px; margin-left:6px; }
  .cp:hover { color:#e6e8eb; border-color:#4a5560; }
  .pager { display:flex; gap:10px; justify-content:center; align-items:center; margin:18px 0 6px; }
  .pager button { background:#1a1f26; color:#e6e8eb; border:1px solid #2a313b;
                  border-radius:6px; padding:4px 14px; cursor:pointer; font:inherit; font-size:12px; }
  .pager button:disabled { opacity:.3; cursor:default; }
  .pager .info { color:#7b8794; font-size:12px; }
  #modal { position:fixed; inset:0; background:rgba(0,0,0,.88); display:none;
           flex-direction:column; align-items:center; justify-content:center;
           gap:12px; z-index:10; cursor:zoom-out; }
  #modal.open { display:flex; }
  #modal img { max-width:92vw; max-height:80vh; object-fit:contain; cursor:default;
               border-radius:6px; box-shadow:0 8px 40px rgba(0,0,0,.6); }
  #mcap { color:#9aa4b2; font-size:12px; display:flex; gap:10px; align-items:center;
          max-width:92vw; overflow-wrap:anywhere; cursor:default; }
  #mhint { color:#5b6673; font-size:11px; cursor:default; }
</style></head><body>
<h1>Claude Images<small>クリックで拡大 / ←→ で移動 / Esc で閉じる</small></h1>
<div class="grid" id="grid">
HTML
  tail -n 200 "$log" | tail -r | while IFS=$'\t' read -r mt abs; do
    [ -f "$abs" ] || continue
    ts=$(date -r "$mt" '+%m/%d %H:%M:%S' 2>/dev/null || echo "")
    esc=$(printf '%s' "$abs" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    name="${esc##*/}"
    printf '<div class="card" data-path="%s" data-src="file://%s?v=%s"><img src="file://%s?v=%s" loading="lazy"><div class="meta"><div class="name">%s</div><div class="time">%s<button class="cp">copy</button></div><div class="path">%s</div></div></div>\n' \
      "$esc" "$esc" "$mt" "$esc" "$mt" "$name" "$ts" "$esc"
  done
  cat <<'HTML'
</div>
<div class="pager">
  <button id="prev">← 前</button>
  <span class="info" id="pinfo"></span>
  <button id="next">次 →</button>
</div>
<div id="modal">
  <img id="mimg" alt="">
  <div id="mcap"><span id="mpath"></span><button class="cp" id="mcopy">パスをコピー</button></div>
  <div id="mhint">クリックで閉じる</div>
</div>
<script>
const PER = 50;
let page = 0, curIdx = -1;
const grid = document.getElementById('grid');
const modal = document.getElementById('modal');
const mimg = document.getElementById('mimg');
const mpath = document.getElementById('mpath');

function cards() { return Array.from(grid.children).filter(c => !c.dataset.broken); }

function render() {
  const vis = cards();
  const pages = Math.max(1, Math.ceil(vis.length / PER));
  if (page >= pages) page = pages - 1;
  Array.from(grid.children).forEach(c => c.style.display = 'none');
  vis.slice(page * PER, (page + 1) * PER).forEach(c => c.style.display = '');
  document.getElementById('pinfo').textContent = (page + 1) + ' / ' + pages + ' ページ（全 ' + vis.length + ' 件）';
  document.getElementById('prev').disabled = page === 0;
  document.getElementById('next').disabled = page >= pages - 1;
}

// error イベントはバブルしないので capture で拾い、壊れた画像のカードを隠す
grid.addEventListener('error', e => {
  const card = e.target.closest('.card');
  if (card) { card.dataset.broken = '1'; render(); }
}, true);

function copy(btn, text, label) {
  (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject())
    .then(() => { btn.textContent = 'copied!'; })
    .catch(() => { window.prompt('コピーしてください:', text); })
    .finally(() => setTimeout(() => { btn.textContent = label; }, 900));
}

grid.addEventListener('click', e => {
  const card = e.target.closest('.card');
  if (!card) return;
  const cp = e.target.closest('.cp');
  if (cp) { copy(cp, card.dataset.path, 'copy'); return; }
  openModal(cards().indexOf(card));
});

function openModal(i) {
  const vis = cards();
  if (i < 0 || i >= vis.length) return;
  curIdx = i;
  mimg.src = vis[i].dataset.src;
  mpath.textContent = vis[i].dataset.path;
  page = Math.floor(i / PER);
  render();
  modal.classList.add('open');
}
function closeModal() { modal.classList.remove('open'); mimg.src = ''; curIdx = -1; }

modal.addEventListener('click', e => {
  if (e.target.id === 'mcopy') { copy(e.target, mpath.textContent, 'パスをコピー'); return; }
  if (e.target === mimg || e.target.closest('#mcap')) return;
  closeModal();
});
document.addEventListener('keydown', e => {
  if (!modal.classList.contains('open')) return;
  if (e.key === 'Escape') closeModal();
  if (e.key === 'ArrowRight') openModal(curIdx + 1);
  if (e.key === 'ArrowLeft') openModal(curIdx - 1);
});
document.getElementById('prev').onclick = () => { page--; render(); };
document.getElementById('next').onclick = () => { page++; render(); };
render();
</script>
</body></html>
HTML
} > "$tmp" && mv "$tmp" "$index"

# Reload the gallery tab if one is open in Chrome; otherwise open it in the
# background (-g keeps focus in the terminal). Only script Chrome when it is
# already running so `tell application` doesn't launch it as a side effect.
if pgrep -xq "Google Chrome" 2>/dev/null; then
  found=$(osascript -e '
    tell application "Google Chrome"
      set found to false
      repeat with w in windows
        repeat with t in tabs of w
          if URL of t contains "image-gallery/index.html" then
            reload t
            set found to true
          end if
        end repeat
      end repeat
      return found
    end tell' 2>/dev/null)
  [ "$found" = "true" ] && exit 0
fi
open -g "$index" 2>/dev/null || true

exit 0
