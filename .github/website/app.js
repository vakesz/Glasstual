const repository = "vakesz/Glasstual";
const releaseFallback = `https://github.com/${repository}/releases/latest`;

const downloadButtons = document.querySelectorAll("#download-button, #download-button-bottom");
const releaseNote = document.querySelector("#release-note");

async function loadLatestRelease() {
  if (!downloadButtons.length) return;
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(`GitHub returned ${response.status}`);

    const release = await response.json();
    const download = release.assets?.find((asset) => asset.name.endsWith(".zip"));
    const destination = download?.browser_download_url ?? release.html_url ?? releaseFallback;

    for (const button of downloadButtons) {
      button.href = destination;
      button.querySelector("span").textContent = `Download ${release.tag_name}`;
    }
    if (releaseNote) releaseNote.textContent = `${release.name ?? release.tag_name} is signed and notarized. Free and open source.`;
  } catch {
    for (const button of downloadButtons) button.href = releaseFallback;
  }
}

// Transcript style preview: a two-option segmented control over static sample rows.
const picker = document.querySelector("#style-picker");
const sample = document.querySelector("#style-sample");
if (picker && sample) {
  picker.hidden = false;
  picker.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-style]");
    if (!button) return;
    sample.dataset.style = button.dataset.style;
    for (const option of picker.querySelectorAll("button")) {
      option.setAttribute("aria-pressed", String(option === button));
    }
  });
}

// Hide optional gallery items whose images are not published.
for (const item of document.querySelectorAll("[data-optional]")) {
  const image = item.querySelector("img");
  const hide = () => { item.hidden = true; };
  if (image.complete && image.naturalWidth === 0 && image.currentSrc) hide();
  image.addEventListener("error", hide, { once: true });
}

loadLatestRelease();
